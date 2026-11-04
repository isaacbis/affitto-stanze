'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {memoryFirestore}=require('./memory-firestore');
const {createNotifications}=require('../lib/notifications');
async function setup(sender) {
  const db=memoryFirestore();let time=100000;
  const calls=[];
  const send=sender || (async(device,payload)=>{calls.push({device,payload});return {ok:true};});
  const service=createNotifications({db,env:{},send,now:()=>time,logger:{warn(){}}});
  for(const [id,role,active] of [['alice','user',true],['bob','user',true],['admin','admin',true],['disabled','admin',false]])await db.collection('users').doc(id).set({role,active});
  const bodies={};let count=0;
  async function device(user) {
    const body={installation_id:randomUUID(),installation_secret:'ab'.repeat(32),token:(++count).toString(16).padStart(64,'0'),environment:'production',sequence:1};
    assert.equal((await service.register(user,body)).status,200);bodies[user]=body;return body;
  }
  async function event(type='created',user_id='alice') {
    await db.runTransaction(tx=>service.enqueue(tx,type,'booking',{user_id,admin_note:'MUST NEVER APPEAR'}));
    return (await db.collection('push_events').get()).docs.at(-1);
  }
  return {db,service,calls,bodies,device,event,tick(ms){time+=ms;}};
}
test('Created bookings notify only their owner and active admins; cancellation only owner; private details excluded',async()=>{
  const t=await setup();for(const id of ['alice','bob','admin','disabled'])await t.device(id);
  await t.event();await t.service.drain();assert.equal(t.calls.length,2);
  assert.deepEqual(t.calls.map(c=>c.payload.recipient_id).sort(),['admin','alice']);
  assert.equal(t.calls.find(c=>c.payload.recipient_id==='alice').payload.aps.alert.title,'Prenotazione confermata');
  assert.equal(t.calls.find(c=>c.payload.recipient_id==='admin').payload.aps.alert.title,'Nuova prenotazione');
  assert.ok(t.calls.every(c=>!JSON.stringify(c.payload).includes('MUST NEVER')));
  await t.event('deleted');await t.service.drain();assert.equal(t.calls.length,3);
  assert.equal(t.calls[2].payload.recipient_id,'alice');assert.equal(t.calls[2].payload.aps.alert.title,'Prenotazione cancellata');
  await t.service.drain();assert.equal(t.calls.length,3,'Successful deliveries must not repeat');
});
test('Registration requires a valid token and protected installation identity; unlink works after logout',async()=>{
  const t=await setup(), body=await t.device('alice');
  assert.equal((await t.service.register('bob',{...body,installation_secret:'cd'.repeat(32)})).status,403);
  assert.equal((await t.service.unregister({...body,installation_secret:'cd'.repeat(32)})).status,403);
  assert.equal((await t.service.register('alice',{...body,token:'invalid'})).status,400);
  assert.equal((await t.service.register('alice',{...body,environment:'other'})).status,400);
  assert.equal((await t.service.unregister({...body,sequence:2})).status,200);
  assert.equal((await t.service.register('alice',body)).status,409,'A delayed registration cannot undo logout');
  await t.event();await t.service.drain();assert.equal(t.calls.length,0);
});
test('Account switching and reinstall retire old bindings and never replay previous events',async()=>{
  const t=await setup(), body=await t.device('alice');
  await t.event();t.tick(1);
  assert.equal((await t.service.register('bob',body)).status,200);
  await t.service.drain();assert.equal(t.calls.length,0);
  await t.event('created','bob');await t.service.drain();assert.equal(t.calls.length,1);
  t.tick(1);await t.service.register('alice',{...body,installation_id:randomUUID()});
  assert.equal((await t.db.collection('push_devices').get()).size,1,'Reinstallation removes the old token binding');
  await t.event('deleted','bob');await t.service.drain();assert.equal(t.calls.length,1);
});
test('Retries persist successful recipients; invalid APNs tokens are removed without affecting others',async()=>{
  let fail=true;const sent=[];
  const t=await setup(async(device,payload)=>{sent.push(payload.recipient_id);return payload.recipient_id==='admin' && fail ? {retry:true,reason:'ServiceUnavailable'} : {ok:true};});
  await t.device('alice');await t.device('admin');const event=await t.event();await t.service.drain();
  assert.deepEqual(sent,['alice','admin']);assert.equal((await event.ref.get()).data().state,'pending');
  t.tick(30000);fail=false;await t.service.drain();assert.deepEqual(sent,['alice','admin','admin']);
  assert.equal((await event.ref.get()).data().state,'sent');
  const invalid=await setup(async()=>({invalid:true,reason:'Unregistered'}));await invalid.device('alice');await invalid.event();await invalid.service.drain();
  assert.equal((await invalid.db.collection('push_devices').get()).size,0);
});
test('Committed events survive a worker restart; expired events and inactive users do not receive pushes',async()=>{
  const t=await setup();await t.device('alice');await t.event();
  const recovered=createNotifications({db:t.db,env:{},send:async(device,payload)=>{t.calls.push(payload);return {ok:true};},now:()=>100000,logger:{warn(){}}});
  await Promise.all([recovered.drain(),t.service.drain()]);assert.equal(t.calls.length,1);
  await t.event();await t.db.collection('users').doc('alice').update({active:false});await t.service.drain();assert.equal(t.calls.length,1);
  await t.db.collection('users').doc('alice').update({active:true});await t.event();t.tick(25*3600000);await t.service.drain();assert.equal(t.calls.length,1);
});
test('Unknown configuration stays inactive and does not attempt delivery',async()=>{
  const service=createNotifications({db:memoryFirestore(),env:{}});assert.equal(service.configured,false);await service.drain();
});
