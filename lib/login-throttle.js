'use strict';
const { createHash } = require('node:crypto');
const { ipKeyGenerator } = require('express-rate-limit');

// Shared by website and iOS, including across multiple server instances/restarts.
function createLoginThrottle({ db, now = Date.now, windowMs = 15 * 60 * 1000,
  ipLimit = 60, accountLimit = 15 }) {
  const collection = db.collection('login_attempts');
  return async function loginThrottle(req, res, next) {
    const username = req.body?.username;
    const api = req.originalUrl.startsWith('/api/');
    const reply = (status, message) => api ? res.status(status).json({ error: message }) : res.status(status).send(message);
    if (typeof username !== 'string' || username.trim().length === 0 || username.length > 128)
      return reply(400, 'Inserisci uno username valido');
    const time = now();
    const keys = [
      ['ip', ipKeyGenerator(req.ip || 'unknown'), ipLimit],
      ['account', username.trim(), accountLimit]
    ];
    const refs = keys.map(([type, value]) => collection.doc(createHash('sha256').update(`${type}:${value}`).digest('hex')));
    try {
      const retryAfter = await db.runTransaction(async transaction => {
        const snapshots = await Promise.all(refs.map(ref => transaction.get(ref)));
        const states = snapshots.map(snapshot => {
          const data = snapshot.exists ? snapshot.data() : null;
          const expiry = data?.expiresAt?.toMillis ? data.expiresAt.toMillis() : new Date(data?.expiresAt || 0).getTime();
          return expiry > time ? { count: Number(data.count) || 0, expiry } : { count: 0, expiry: time + windowMs };
        });
        const blocked = states.filter((state, index) => state.count >= keys[index][2]);
        if (blocked.length) return Math.max(...blocked.map(state => Math.ceil((state.expiry - time) / 1000)));
        states.forEach((state, index) => transaction.set(refs[index], { count: state.count + 1, expiresAt: new Date(state.expiry) }));
        return 0;
      });
      res.set('Cache-Control', 'no-store');
      if (retryAfter) {
        res.set('Retry-After', String(retryAfter));
        return reply(429, 'Troppi tentativi di accesso. Riprova tra qualche minuto.');
      }
      next();
    } catch (error) {
      console.error('Errore controllo tentativi di accesso:', error.message);
      return reply(503, 'Accesso temporaneamente non disponibile. Riprova tra poco.');
    }
  };
}
module.exports = { createLoginThrottle };
