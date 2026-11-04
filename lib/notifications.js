'use strict';
const { createHash, randomUUID, timingSafeEqual } = require('node:crypto');
const { rateLimit } = require('express-rate-limit');
const { createAPNsSender } = require('./apns');
const digest = value => createHash('sha256').update(value).digest('hex');
const sequenceValid = body => Number.isSafeInteger(body?.sequence) && body.sequence > 0;
const identityValid = body => /^[a-f0-9-]{36}$/i.test(body?.installation_id || '') && /^[a-f0-9]{64}$/i.test(body?.installation_secret || '');
const matchesSecret = (device, secret) => typeof device?.secret_hash==='string' && device.secret_hash.length===64 && timingSafeEqual(Buffer.from(device.secret_hash,'hex'),Buffer.from(digest(secret),'hex'));
const activeUser = user => user && [true,1,'1'].includes(user.active) && ['admin','user'].includes(user.role);

function createNotifications({db, env=process.env, send=createAPNsSender(env), now=Date.now, logger=console}) {
  const devices=db.collection('push_devices'), events=db.collection('push_events'), users=db.collection('users');
  let running=false;
  function enqueue(transaction, type, bookingId, booking) {
    const id=randomUUID(), time=now();
    transaction.set(events.doc(id),{type,booking_id:bookingId,user_id:String(booking.user_id),created_at:time,
      expires_at:time+24*60*60*1000,state:'pending',attempts:0,next_at:time,lease_until:0,delivered:[]});
  }
  async function register(userId, body) {
    if (!identityValid(body) || !sequenceValid(body) || !/^[a-f0-9]{32,512}$/i.test(body.token || '') || !['development','production'].includes(body.environment))
      return {status:400,error:'Dispositivo non valido'};
    const ref=devices.doc(body.installation_id);
    return db.runTransaction(async tx=>{
      const previous=await tx.get(ref), data=previous.data();
      if (previous.exists && !matchesSecret(data,body.installation_secret)) return {status:403,error:'Dispositivo non autorizzato'};
      if (previous.exists && body.sequence<data.sequence) return {status:409,error:'Registrazione notifiche superata'};
      const count=await tx.get(devices.where('user_id','==',String(userId)));
      const duplicates=await tx.get(devices.where('token','==',body.token.toLowerCase()));
      if (data?.user_id!==String(userId) && count.size>=20) return {status:429,error:'Troppi dispositivi registrati'};
      const unchanged=data?.user_id===String(userId) && data?.token===body.token && data?.environment===body.environment;
      for(const duplicate of duplicates.docs)if(duplicate.id!==ref.id && duplicate.data().environment===body.environment)tx.delete(duplicate.ref);
      tx.set(ref,{user_id:String(userId),token:body.token.toLowerCase(),environment:body.environment,
        secret_hash:digest(body.installation_secret),sequence:body.sequence,binding:unchanged ? data.binding : randomUUID(),
        registered_at:unchanged ? data.registered_at : now(),updated_at:now()});
      return {status:200};
    });
  }
  async function unregister(body) {
    if (!identityValid(body) || !sequenceValid(body)) return {status:400,error:'Dispositivo non valido'};
    return db.runTransaction(async tx=>{
      const ref=devices.doc(body.installation_id), snap=await tx.get(ref);
      if (snap.exists && !matchesSecret(snap.data(),body.installation_secret)) return {status:403,error:'Dispositivo non autorizzato'};
      if (snap.exists && body.sequence>=snap.data().sequence) tx.set(ref,{secret_hash:snap.data().secret_hash,sequence:body.sequence,user_id:null,updated_at:now()});
      return {status:200};
    });
  }
  function install(app, apiAuth) {
    const throttle=rateLimit({windowMs:60000,limit:60,standardHeaders:'draft-8',legacyHeaders:false});
    const reply=(res,result)=>res.status(result.status).json(result.error ? {error:result.error} : {ok:true});
    app.post('/api/v1/push/device',throttle,apiAuth,async(req,res)=>{
      try {reply(res,await register(req.apiUser.id,req.body));}
      catch {res.status(503).json({error:'Registrazione notifiche temporaneamente non disponibile'});}
    });
    // A per-installation secret also permits deferred removal after logout/offline use.
    app.delete('/api/v1/push/device',throttle,async(req,res)=>{
      try {reply(res,await unregister(req.body));}
      catch {res.status(503).json({error:'Disattivazione notifiche temporaneamente non disponibile'});}
    });
  }
  async function removeInvalid(ref,binding) {
    await db.runTransaction(async tx=>{const latest=await tx.get(ref);if(latest.exists && latest.data().binding===binding)tx.delete(ref);});
  }
  async function processEvent(ref) {
    const lease=randomUUID();
    const event=await db.runTransaction(async tx=>{
      const snap=await tx.get(ref), data=snap.data();
      if (!snap.exists || data.state!=='pending' || data.next_at>now() || data.lease_until>now())return null;
      if (data.expires_at<=now()) {tx.set(ref,{...data,state:'expired',next_at:Number.MAX_SAFE_INTEGER});return null;}
      tx.set(ref,{...data,lease,lease_until:now()+5*60*1000});return data;
    });
    if (!event)return;
    let retry=false;
    const delivered=new Set(event.delivered);
    try {
      const recipients=new Map();
      const owner=await users.doc(event.user_id).get();
      if (owner.exists && activeUser(owner.data()))recipients.set(owner.id,'owner');
      if(event.type==='created') {
        const admins=await users.where('role','==','admin').get();
        for(const admin of admins.docs)if(activeUser(admin.data()))recipients.set(admin.id,'admin');
      }
      for(const [userId,kind] of recipients) {
        const registered=await devices.where('user_id','==',userId).get();
        for(const snap of registered.docs) {
          const device=snap.data(), deliveryId=`${snap.id}:${device.binding}`;
          if(delivered.has(deliveryId) || device.registered_at>event.created_at || device.updated_at<now()-90*86400000)continue;
          // Recheck the binding and active role immediately before sending, including after a retry.
          const [current,currentUser]=await Promise.all([snap.ref.get(),users.doc(userId).get()]);
          if(!current.exists || current.data().binding!==device.binding || !currentUser.exists || !activeUser(currentUser.data()) || (kind==='admin' && currentUser.data().role!=='admin'))continue;
          const title=event.type==='deleted' ? 'Prenotazione cancellata' : kind==='admin' ? 'Nuova prenotazione' : 'Prenotazione confermata';
          const body=event.type==='deleted' ? 'Una tua prenotazione è stata cancellata. Apri l’app per controllare.' : kind==='admin' ? 'È stata prenotata una stanza. Apri l’app per i dettagli.' : 'La tua prenotazione è confermata. Apri l’app per i dettagli.';
          const result=await send(device,{aps:{alert:{title,body},sound:'default','thread-id':'prenotazioni'},event_id:ref.id,event_type:event.type,booking_id:event.booking_id,recipient_id:userId},ref.id,event.expires_at);
          if(result.ok || result.invalid) {
            if(result.invalid)await removeInvalid(snap.ref,device.binding);
            delivered.add(deliveryId);
            // Persist each delivery, so a later failure does not resend successful recipients.
            await db.runTransaction(async tx=>{const latest=await tx.get(ref);if(latest.data()?.lease===lease)tx.set(ref,{...latest.data(),delivered:[...delivered]});});
          } else {retry=true;logger.warn('APNs invio da riprovare:',result.reason);}
        }
      }
    } catch {retry=true;logger.warn('Notifiche: consegna temporaneamente non disponibile');}
    await db.runTransaction(async tx=>{
      const latest=await tx.get(ref);if(latest.data()?.lease!==lease)return;
      const attempts=event.attempts+1;
      tx.set(ref,{...latest.data(),delivered:[...delivered],attempts,state:retry ? 'pending' : 'sent',
        next_at:retry ? now()+Math.min(15*60000,10000*2**Math.min(attempts,7)) : Number.MAX_SAFE_INTEGER,lease_until:0});
    });
  }
  async function drain() {
    if(!send || running)return;
    running=true;
    try {
      const pending=await events.where('next_at','<=',now()).limit(100).get();
      for(const event of pending.docs)await processEvent(event.ref);
    } catch {logger.warn('Notifiche: coda temporaneamente non disponibile');}
    finally {running=false;}
  }
  async function cleanup() {
    for(const [collection,field,cutoff] of [[events,'expires_at',now()-7*86400000],[devices,'updated_at',now()-90*86400000]]) {
      const old=await collection.where(field,'<',cutoff).limit(300).get();
      for(const doc of old.docs)await doc.ref.delete();
    }
  }
  function start() {
    if(!send){logger.warn('Notifiche push: configurazione APNs mancante');return;}
    drain();const timer=setInterval(drain,15000);timer.unref();
    const cleaner=setInterval(()=>cleanup().catch(()=>{}),86400000);cleaner.unref();
  }
  return {enqueue,register,unregister,install,drain,start,cleanup,configured:Boolean(send)};
}
module.exports={createNotifications};
