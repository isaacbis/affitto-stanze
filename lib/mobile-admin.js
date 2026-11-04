'use strict';
const express = require('express');
const bcrypt = require('bcrypt');

function installMobileAdmin(app, deps) {
  const { db, apiAuth, getAllUsers, getAllRooms, userIsActive, roomIsActive,
    getUserById, buildAdminReportData, sendReportPDF } = deps;
  const users = db.collection('users'), rooms = db.collection('rooms'), bookings = db.collection('bookings');
  const router = express.Router();
  const failure = (status, message) => Object.assign(new Error(message), { status });
  const route = handler => async (req, res) => {
    try { await handler(req, res); }
    catch (error) {
      if (!error.status) console.error('Errore API amministratore:', error);
      res.status(error.status || 500).json({ error: error.status ? error.message : 'Operazione non riuscita. Riprova.' });
    }
  };
  const validID = value => typeof value === 'string' && value.length > 0 && !value.includes('/');
  router.use(apiAuth, (req, res, next) => req.apiUser.role === 'admin' ? next() : res.status(403).json({error: 'Accesso riservato agli amministratori'}));
  router.param('id', (req, res, next, id) => validID(id) ? next() : res.status(400).json({error:'Identificativo non valido'}));
  const publicUser = u => ({id:u.id, username:u.username, role:u.role, active:userIsActive(u)});
  const publicRoom = r => ({id:r.id, name:r.name, description:String(r.description || ''), active:roomIsActive(r)});
  router.get('/users', route(async (req,res) => res.json((await getAllUsers()).map(publicUser))));
  router.post('/users', route(async (req,res) => {
    const username = String(req.body.username || '').trim(), password = String(req.body.password || ''), role = req.body.role;
    if (!username || username.length > 128 || !password || !['admin','user'].includes(role)) throw failure(400,'Compila username, password e ruolo validi');
    const hash = await bcrypt.hash(password,10), ref = users.doc();
    await db.runTransaction(async tx => {
      const existing = await tx.get(users.where('username','==',username).limit(1));
      if (!existing.empty) throw failure(409,'Username già esistente');
      tx.set(ref,{username,password_hash:hash,role,active:true,created_at:new Date().toISOString()});
    });
    res.status(201).json({id:ref.id});
  }));
  router.post('/users/:id/toggle', route(async (req,res) => {
    const ref = users.doc(req.params.id);
    await db.runTransaction(async tx => {
      const doc = await tx.get(ref);
      if (!doc.exists) throw failure(404,'Utente non trovato');
      const user = { ...doc.data(), id:doc.id };
      if (user.role === 'admin' && userIsActive(user)) {
        if (user.id === req.apiUser.id) throw failure(400,'Non puoi disattivare il tuo account amministratore');
        const admins = await tx.get(users.where('role','==','admin'));
        if (admins.docs.filter(d => userIsActive(d.data())).length <= 1) throw failure(400,'Non puoi disattivare l’ultimo amministratore attivo');
      }
      const {id, ...data} = user;
      tx.set(ref,{...data,active:!userIsActive(user)});
    });
    res.json({ok:true});
  }));
  router.post('/users/:id/password', route(async (req,res) => {
    const user = await getUserById(req.params.id), password = String(req.body.new_password || '');
    if (!user || user.role !== 'user') throw failure(404,'Utente non trovato');
    if (!password) throw failure(400,'Inserisci una nuova password');
    if (await bcrypt.compare(password,user.password_hash || '')) throw failure(400,'La nuova password coincide con quella attuale');
    await users.doc(user.id).update({password_hash:await bcrypt.hash(password,10)});
    res.json({ok:true});
  }));
  router.get('/rooms', route(async (req,res) => res.json((await getAllRooms()).map(publicRoom))));
  router.post('/rooms', route(async (req,res) => {
    const name = String(req.body.name || '').trim(), description = String(req.body.description || '').trim();
    if (!name) throw failure(400,'Nome stanza obbligatorio');
    const ref = await rooms.add({name,description,active:true,created_at:new Date().toISOString()});
    res.status(201).json({id:ref.id});
  }));
  router.post('/rooms/:id/toggle', route(async (req,res) => {
    const ref = rooms.doc(req.params.id);
    await db.runTransaction(async tx => {
      const doc = await tx.get(ref);
      if (!doc.exists) throw failure(404,'Stanza non trovata');
      tx.set(ref,{...doc.data(),active:!roomIsActive(doc.data())});
    });
    res.json({ok:true});
  }));
  router.delete('/rooms/:id', route(async (req,res) => {
    const ref = rooms.doc(req.params.id);
    await db.runTransaction(async tx => {
      const doc = await tx.get(ref);
      if (!doc.exists) throw failure(404,'Stanza non trovata');
      const linked = await tx.get(bookings.where('room_id','==',req.params.id).limit(1));
      if (!linked.empty) throw failure(409,'Questa stanza ha prenotazioni collegate. Puoi disattivarla.');
      tx.delete(ref);
    });
    res.json({ok:true});
  }));
  router.use('/reports', (req,res,next) => {
    const {type='monthly',month,weekStart,userId} = req.query;
    const validDate = s => typeof s === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(s) && !Number.isNaN(Date.parse(s)) && new Date(s).toISOString().slice(0,10) === s;
    if (!['monthly','weekly'].includes(type) || (month !== undefined && (typeof month !== 'string' || !/^\d{4}-(0[1-9]|1[0-2])$/.test(month))) || (weekStart !== undefined && !validDate(weekStart)) || (userId && !validID(userId)))
      return res.status(400).json({error:'Periodo o filtri del report non validi'});
    next();
  });
  router.get('/reports', route(async (req,res) => {
    const report = await buildAdminReportData(req.query);
    res.json({...report, users:report.users.map(publicUser), totalHours:report.reportRows.reduce((s,r)=>s+Number(r.total_hours),0), totalBookings:report.reportRows.reduce((s,r)=>s+Number(r.total_bookings),0)});
  }));
  router.get('/reports/pdf', sendReportPDF);
  app.use('/api/v1/admin',router);
}
module.exports = { installMobileAdmin };
