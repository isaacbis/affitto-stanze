const express = require('express');
const session = require('express-session');
const bcrypt = require('bcrypt');
const path = require('path');
const admin = require('firebase-admin');

const app = express();
const PORT = process.env.PORT || 3000;

/* =========================
   FIREBASE INIT
========================= */
function initFirebase() {
  if (admin.apps.length) {
    return admin.firestore();
  }

  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;

  if (!raw) {
    throw new Error('Variabile ambiente FIREBASE_SERVICE_ACCOUNT mancante');
  }

  let serviceAccount;
  try {
    serviceAccount = JSON.parse(raw);
  } catch (err) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT non è un JSON valido');
  }

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });

  return admin.firestore();
}

const db = initFirebase();

class FirestoreSessionStore extends session.Store {
  constructor({ firestore, collection = 'sessions' }) {
    super();
    this.col = firestore.collection(collection);
  }

  get(sid, callback) {
    this.col.doc(String(sid)).get()
      .then(doc => {
        if (!doc.exists) return callback(null, null);

        const data = doc.data() || {};
        const expiresAt = data.expiresAt?.toMillis
          ? data.expiresAt.toMillis()
          : new Date(data.expiresAt || 0).getTime();

        if (expiresAt && expiresAt <= Date.now()) {
          return this.destroy(sid, () => callback(null, null));
        }

        const parsedSession = typeof data.session === 'string'
          ? JSON.parse(data.session)
          : data.session;

        return callback(null, parsedSession || null);
      })
      .catch(err => callback(err));
  }

  set(sid, sess, callback) {
    const expiresAt = sess?.cookie?.expires
      ? new Date(sess.cookie.expires)
      : new Date(Date.now() + 1000 * 60 * 60 * 8);

    this.col.doc(String(sid)).set(
      {
        session: JSON.stringify(sess),
        expiresAt,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      },
      { merge: true }
    )
      .then(() => callback && callback(null))
      .catch(err => callback && callback(err));
  }

  destroy(sid, callback) {
    this.col.doc(String(sid)).delete()
      .then(() => callback && callback(null))
      .catch(err => callback && callback(err));
  }

  touch(sid, sess, callback) {
    const expiresAt = sess?.cookie?.expires
      ? new Date(sess.cookie.expires)
      : new Date(Date.now() + 1000 * 60 * 60 * 8);

    this.col.doc(String(sid)).set(
      {
        expiresAt,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      },
      { merge: true }
    )
      .then(() => callback && callback(null))
      .catch(err => callback && callback(err));
  }
}


/* =========================
   APP CONFIG
========================= */
const isProduction = process.env.NODE_ENV === 'production';
const sessionSecret =
  process.env.SESSION_SECRET ||
  (isProduction ? '' : 'dev-session-secret-change-me');

if (!sessionSecret) {
  throw new Error('Variabile ambiente SESSION_SECRET mancante');
}

app.set('trust proxy', 1);
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.locals.assetVersion = process.env.ASSET_VERSION || '20260327-1';

app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

const sessionStore = new FirestoreSessionStore({
  firestore: db,
  collection: 'sessions'
});

app.use(
  session({
    store: sessionStore,
    name: 'affitto_stanze.sid',
    secret: sessionSecret,
    resave: false,
    saveUninitialized: false,
    rolling: true,
    unset: 'destroy',
    cookie: {
      secure: isProduction,
      httpOnly: true,
      sameSite: 'lax',
      maxAge: 1000 * 60 * 60 * 8
    }
  })
);

/* =========================
   COLLECTION HELPERS
========================= */
const usersCol = db.collection('users');
const roomsCol = db.collection('rooms');
const bookingsCol = db.collection('bookings');

const sessionsCol = db.collection('sessions');
const bookingsArchiveCol = db.collection('bookings_archive');

const SESSION_CLEANUP_INTERVAL_MS = 1000 * 60 * 60 * 8;   // 8 ore
const BOOKINGS_CLEANUP_INTERVAL_MS = 1000 * 60 * 60 * 24; // 24 ore
const CLEANUP_BATCH_SIZE = 300;

/* =========================
   GENERIC HELPERS
========================= */
function nowIso() {
  return new Date().toISOString();
}

function normalizeUsername(value) {
  return String(value || '').trim();
}

function toBool(value) {
  return value === true || value === 1 || value === '1';
}

function sortByCreatedAtDesc(a, b) {
  const aVal = a.created_at || '';
  const bVal = b.created_at || '';
  return bVal.localeCompare(aVal);
}

function sortByDateDescHourAsc(a, b) {
  if (a.booking_date !== b.booking_date) {
    return String(b.booking_date).localeCompare(String(a.booking_date));
  }
  return Number(a.start_hour) - Number(b.start_hour);
}

function sortByBookingDateTimeDesc(a, b) {
  const dateA = buildBookingStartDate(a.booking_date, a.start_hour).getTime();
  const dateB = buildBookingStartDate(b.booking_date, b.start_hour).getTime();
  return dateB - dateA;
}

function pad2(value) {
  return String(value).padStart(2, '0');
}

function isValidHalfHour(value) {
  return Number.isFinite(value) && (value * 2) % 1 === 0;
}

function formatTimeLabel(value) {
  const numeric = Number(value);
  const hours = Math.floor(numeric);
  const minutes = numeric % 1 === 0.5 ? 30 : 0;
  return `${pad2(hours)}:${pad2(minutes)}`;
}

function buildBookingStartDate(bookingDate, startHour) {
  const [y, m, d] = bookingDate.split('-').map(Number);
  const numeric = Number(startHour);
  const hours = Math.floor(numeric);
  const minutes = numeric % 1 === 0.5 ? 30 : 0;

  return new Date(
    y,
    m - 1,
    d,
    hours,
    minutes,
    0,
    0
  );
}

function getRomeNowParts() {
  const parts = new Intl.DateTimeFormat('sv-SE', {
    timeZone: 'Europe/Rome',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false
  }).formatToParts(new Date());

  const map = Object.fromEntries(
    parts
      .filter(part => part.type !== 'literal')
      .map(part => [part.type, part.value])
  );

  return {
    booking_date: `${map.year}-${map.month}-${map.day}`,
    minutesNow:
      Number(map.hour) * 60 +
      Number(map.minute) +
      Number(map.second) / 60
  };
}

function ymdToUtcMs(ymd) {
  const [y, m, d] = String(ymd).split('-').map(Number);
  return Date.UTC(y, m - 1, d);
}

function getMinutesUntilBooking(bookingDate, startHour) {
  const nowRome = getRomeNowParts();

  const dayDiff = Math.round(
    (ymdToUtcMs(bookingDate) - ymdToUtcMs(nowRome.booking_date)) / 86400000
  );

  const bookingMinutes = Number(startHour) * 60;

  return dayDiff * 1440 + (bookingMinutes - nowRome.minutesNow);
}

function hasBookingAlreadyStarted(bookingDate, startHour) {
  return getMinutesUntilBooking(bookingDate, startHour) <= 0;
}

function isBookingCancellable(bookingDate, startHour) {
  // cancellabile solo se mancano PIÙ di 60 minuti
  return getMinutesUntilBooking(bookingDate, startHour) > 60;
}

function getWeekStartMonday(baseDate = new Date()) {
  const d = new Date(baseDate);
  const day = d.getDay(); // 0 domenica
  const diff = (day + 6) % 7; // lunedì = 0
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() - diff);
  return d;
}

function dateToYmd(date) {
  const d = new Date(date);
  return [
    d.getFullYear(),
    String(d.getMonth() + 1).padStart(2, '0'),
    String(d.getDate()).padStart(2, '0')
  ].join('-');
}

function getRomeTodayYmd() {
  return getRomeNowParts().booking_date;
}

function addDaysToYmd(ymd, days) {
  const shifted = new Date(ymdToUtcMs(ymd) + Number(days) * 86400000);

  return [
    shifted.getUTCFullYear(),
    String(shifted.getUTCMonth() + 1).padStart(2, '0'),
    String(shifted.getUTCDate()).padStart(2, '0')
  ].join('-');
}

function getWeekStartMondayYmd(baseYmd = getRomeTodayYmd()) {
  const baseDate = new Date(ymdToUtcMs(baseYmd));
  const day = baseDate.getUTCDay(); // 0 = domenica, 1 = lunedì
  const diff = (day + 6) % 7; // lunedì = 0

  return addDaysToYmd(baseYmd, -diff);
}

function monthLastDay(monthStr) {
  const d = new Date(`${monthStr}-01T00:00:00`);
  d.setMonth(d.getMonth() + 1);
  d.setDate(0);
  return dateToYmd(d);
}

function isValidRole(role) {
  return role === 'admin' || role === 'user';
}

function roomIsActive(room) {
  return toBool(room?.active);
}

function userIsActive(user) {
  return toBool(user?.active);
}

function bookingIsActive(booking) {
  return (booking?.status || 'active') === 'active';
}

/* =========================
   FIRESTORE HELPERS
========================= */
async function getAllUsers() {
  const snap = await usersCol.get();
  return snap.docs
    .map(doc => ({ id: doc.id, ...doc.data() }))
    .sort(sortByCreatedAtDesc);
}

async function getAllRooms() {
  const snap = await roomsCol.get();
  return snap.docs
    .map(doc => ({ id: doc.id, ...doc.data() }))
    .sort(sortByCreatedAtDesc);
}

async function getAllBookings() {
  const snap = await bookingsCol.get();
  return snap.docs
    .map(doc => ({ id: doc.id, ...doc.data() }))
    .sort(sortByDateDescHourAsc);
}

async function getUserById(id) {
  const doc = await usersCol.doc(String(id)).get();
  if (!doc.exists) return null;
  return { id: doc.id, ...doc.data() };
}

async function getRoomById(id) {
  const doc = await roomsCol.doc(String(id)).get();
  if (!doc.exists) return null;
  return { id: doc.id, ...doc.data() };
}

async function getBookingById(id) {
  const doc = await bookingsCol.doc(String(id)).get();
  if (!doc.exists) return null;
  return { id: doc.id, ...doc.data() };
}

async function getUserByUsername(username) {
  const normalizedUsername = normalizeUsername(username);

  if (!normalizedUsername) return null;

  const snap = await usersCol
    .where('username', '==', normalizedUsername)
    .limit(1)
    .get();

  if (snap.empty) return null;

  const doc = snap.docs[0];
  return { id: doc.id, ...doc.data() };
}

async function getActiveRoomsSortedByName() {
  const snap = await roomsCol.get();

  return snap.docs
    .map(doc => ({ id: doc.id, ...doc.data() }))
    .filter(room => roomIsActive(room))
    .sort((a, b) => String(a.name || '').localeCompare(String(b.name || ''), 'it'));
}

async function getActiveUsersSortedByUsername() {
  const snap = await usersCol.get();

  return snap.docs
    .map(doc => ({ id: doc.id, ...doc.data() }))
    .filter(u => u.role === 'user' && userIsActive(u))
    .sort((a, b) => String(a.username || '').localeCompare(String(b.username || ''), 'it'));
}

async function getBookingsForDateAndRoom(roomId, bookingDate) {
  const snap = await bookingsCol
    .where('room_id', '==', String(roomId))
    .where('booking_date', '==', String(bookingDate))
    .where('status', '==', 'active')
    .get();

  return snap.docs
    .map(doc => ({ id: doc.id, ...doc.data() }))
    .sort((a, b) => Number(a.start_hour) - Number(b.start_hour));
}

function bookingsOverlap(startA, endA, startB, endB) {
  return !(Number(startA) >= Number(endB) || Number(endA) <= Number(startB));
}

async function createBookingAtomically(bookingData) {
  return await db.runTransaction(async transaction => {
    const conflictQuery = bookingsCol
      .where('room_id', '==', String(bookingData.room_id))
      .where('booking_date', '==', String(bookingData.booking_date))
      .where('status', '==', 'active');

    const conflictSnap = await transaction.get(conflictQuery);

    const conflict = conflictSnap.docs.find(doc => {
      const data = doc.data();
      return bookingsOverlap(
        bookingData.start_hour,
        bookingData.end_hour,
        data.start_hour,
        data.end_hour
      );
    });

    if (conflict) {
      const err = new Error('BOOKING_CONFLICT');
      err.code = 'BOOKING_CONFLICT';
      throw err;
    }

    const newBookingRef = bookingsCol.doc();
    transaction.set(newBookingRef, {
      ...bookingData
    });

    return newBookingRef.id;
  });
}

async function enrichBookings(rawBookings) {
  const userIds = [...new Set(rawBookings.map(b => String(b.user_id)).filter(Boolean))];
  const roomIds = [...new Set(rawBookings.map(b => String(b.room_id)).filter(Boolean))];

  const userDocs = await Promise.all(userIds.map(id => getUserById(id)));
  const roomDocs = await Promise.all(roomIds.map(id => getRoomById(id)));

  const usersMap = new Map(userDocs.filter(Boolean).map(u => [String(u.id), u]));
  const roomsMap = new Map(roomDocs.filter(Boolean).map(r => [String(r.id), r]));

  return rawBookings.map(b => ({
    ...b,
    username: usersMap.get(String(b.user_id))?.username || 'Utente',
    room_name: roomsMap.get(String(b.room_id))?.name || 'Stanza'
  }));
}

async function ensureDefaultAdmin() {
  const snap = await usersCol.where('role', '==', 'admin').limit(1).get();

  if (!snap.empty) return;

  const initialAdminPassword =
    process.env.DEFAULT_ADMIN_PASSWORD ||
    (isProduction ? '' : 'admin123');

  if (!initialAdminPassword) {
    throw new Error('Variabile ambiente DEFAULT_ADMIN_PASSWORD mancante per creare l’admin iniziale');
  }

  const hash = await bcrypt.hash(initialAdminPassword, 10);

  await usersCol.add({
    username: 'admin',
    password_hash: hash,
    role: 'admin',
    active: true,
    created_at: nowIso()
  });

  console.log(`Admin creato: username=admin password=${initialAdminPassword}`);
}

/* =========================
   AUTH MIDDLEWARE
========================= */
function destroySessionAndRedirect(req, res) {
  return req.session.destroy(() => {
    res.clearCookie('affitto_stanze.sid');
    res.redirect('/login');
  });
}

function requireAdmin(req, res, next) {
  (async () => {
    try {
      const sessionUser = req.session.user;

      if (!sessionUser?.id) {
        return res.redirect('/login');
      }

      const currentUser = await getUserById(String(sessionUser.id));

      if (!currentUser || !userIsActive(currentUser) || currentUser.role !== 'admin') {
        return destroySessionAndRedirect(req, res);
      }

      // aggiorna i dati in sessione nel caso lo username sia cambiato
      req.session.user = {
        id: currentUser.id,
        username: currentUser.username,
        role: currentUser.role
      };

      return next();
    } catch (err) {
      console.error('Errore middleware admin:', err);
      return res.status(500).send('Errore autenticazione admin');
    }
  })();
}

function requireUser(req, res, next) {
  (async () => {
    try {
      const sessionUser = req.session.user;

      if (!sessionUser?.id) {
        return res.redirect('/login');
      }

      const currentUser = await getUserById(String(sessionUser.id));

      if (!currentUser || !userIsActive(currentUser) || currentUser.role !== 'user') {
        return destroySessionAndRedirect(req, res);
      }

      req.session.user = {
        id: currentUser.id,
        username: currentUser.username,
        role: currentUser.role
      };

      return next();
    } catch (err) {
      console.error('Errore middleware user:', err);
      return res.status(500).send('Errore autenticazione utente');
    }
  })();
}

async function renderAdminUsersPage(res, { error = null, success = null } = {}) {
  const users = await getAllUsers();
  return res.render('admin-users', {
    users,
    error,
    success
  });
}

async function renderUserDashboardPage(req, res, { error = null, success = null } = {}) {
  const allBookings = await getAllBookings();

  const myBookingsRaw = allBookings
    .filter(b => String(b.user_id) === String(req.session.user.id))
    .sort(sortByBookingDateTimeDesc)
    .slice(0, 10);

  const bookings = await enrichBookings(myBookingsRaw);

  return res.render('user-dashboard', {
    user: req.session.user,
    bookings,
    error,
    success
  });
}

async function renderAdminBookingsPage(res, { error = null, success = null } = {}) {
  const [rawBookings, rooms, users] = await Promise.all([
    getAllBookings(),
    getActiveRoomsSortedByName(),
    getActiveUsersSortedByUsername()
  ]);

  const bookings = await enrichBookings(rawBookings.sort(sortByBookingDateTimeDesc));

  return res.render('admin-bookings', {
    bookings,
    rooms,
    users,
    error,
    success
  });
}

/* =========================
   ROUTES - GENERIC
========================= */

app.get('/', (req, res) => {
  if (!req.session.user) return res.redirect('/login');
  if (req.session.user.role === 'admin') return res.redirect('/admin/dashboard');
  return res.redirect('/user/dashboard');
});

app.get('/login', (req, res) => {
  res.render('login', { error: null });
});

app.post('/login', async (req, res) => {
  try {
    const username = normalizeUsername(req.body.username);
    const password = String(req.body.password || '');

    if (!username || !password) {
      return res.render('login', { error: 'Compila username e password' });
    }

    const user = await getUserByUsername(username);

    if (!user || !userIsActive(user)) {
      return res.render('login', { error: 'Credenziali non valide' });
    }

    const ok = await bcrypt.compare(password, user.password_hash);
    if (!ok) {
      return res.render('login', { error: 'Credenziali non valide' });
    }

    req.session.user = {
      id: user.id,
      username: user.username,
      role: user.role
    };

    if (user.role === 'admin') return res.redirect('/admin/dashboard');
    return res.redirect('/user/dashboard');
  } catch (err) {
    console.error('Errore login:', err);
    res.status(500).send('Errore login');
  }
});

app.get('/logout', (req, res) => {
  req.session.destroy(() => {
    res.clearCookie('affitto_stanze.sid');
    res.redirect('/login');
  });
});

/* =========================
   ROUTES - ADMIN DASHBOARD
========================= */
app.get('/admin/dashboard', requireAdmin, async (req, res) => {
  try {
    const [users, rooms, bookings] = await Promise.all([
      getAllUsers(),
      getAllRooms(),
      getAllBookings()
    ]);

    const totalUsers = users.filter(u => u.role === 'user' && userIsActive(u)).length;
    const totalRooms = rooms.filter(roomIsActive).length;
const today = getRomeTodayYmd();

    const activeBookings = bookings.filter(bookingIsActive);
    const todayBookings = activeBookings.filter(b => b.booking_date === today).length;

    const latestBookingsRaw = [...activeBookings]
  .sort(sortByBookingDateTimeDesc)
  .slice(0, 10);

    const latestBookings = await enrichBookings(latestBookingsRaw);

    res.render('admin-dashboard', {
      user: req.session.user,
      totalUsers,
      totalRooms,
      todayBookings,
      latestBookings
    });
  } catch (err) {
    console.error('Errore dashboard admin:', err);
    res.status(500).send('Errore dashboard admin');
  }
});

/* =========================
   ROUTES - ADMIN USERS
========================= */


app.get('/admin/users', requireAdmin, async (req, res) => {
  try {
    return await renderAdminUsersPage(res);
  } catch (err) {
    console.error('Errore lista utenti:', err);
    res.status(500).send('Errore lista utenti');
  }
});

app.post('/admin/users/create', requireAdmin, async (req, res) => {
  try {
    const username = normalizeUsername(req.body.username);
    const password = String(req.body.password || '');
    const role = String(req.body.role || '');

    if (!username || !password || !role) {
      return await renderAdminUsersPage(res, {
        error: 'Compila tutti i campi'
      });
    }

    if (!isValidRole(role)) {
      return await renderAdminUsersPage(res, {
        error: 'Ruolo non valido'
      });
    }

    const existing = await getUserByUsername(username);
    if (existing) {
      return await renderAdminUsersPage(res, {
        error: 'Username già esistente'
      });
    }

    const hash = await bcrypt.hash(password, 10);

    await usersCol.add({
      username,
      password_hash: hash,
      role,
      active: true,
      created_at: nowIso()
    });

    return await renderAdminUsersPage(res, {
      success: 'Utente creato con successo'
    });
  } catch (err) {
    console.error('Errore creazione utente:', err);
    return await renderAdminUsersPage(res, {
      error: 'Errore inserimento utente'
    });
  }
});

app.post('/admin/users/toggle/:id', requireAdmin, async (req, res) => {
  try {
    const id = String(req.params.id);
    const user = await getUserById(id);

    if (!user) {
      return await renderAdminUsersPage(res, {
        error: 'Utente non trovato'
      });
    }

    const isCurrentlyActive = userIsActive(user);
    const isAdmin = user.role === 'admin';
    const isSelf = String(req.session.user.id) === id;

    // Evita che un admin si disattivi da solo
    if (isAdmin && isCurrentlyActive && isSelf) {
      return await renderAdminUsersPage(res, {
        error: 'Non puoi disattivare il tuo account admin mentre sei loggato'
      });
    }

    // Evita di disattivare l’ultimo admin attivo
    if (isAdmin && isCurrentlyActive) {
      const allUsers = await getAllUsers();
      const activeAdmins = allUsers.filter(u => u.role === 'admin' && userIsActive(u));

      if (activeAdmins.length <= 1) {
        return await renderAdminUsersPage(res, {
          error: 'Non puoi disattivare l’ultimo admin attivo'
        });
      }
    }

    await usersCol.doc(id).update({
      active: !isCurrentlyActive
    });

    return await renderAdminUsersPage(res, {
      success: `Stato utente aggiornato: ${user.username}`
    });
  } catch (err) {
    console.error('Errore aggiornamento utente:', err);
    return await renderAdminUsersPage(res, {
      error: 'Errore aggiornamento utente'
    });
  }
});

app.post('/admin/users/change-password', requireAdmin, async (req, res) => {
  try {
    const { user_id, new_password } = req.body;

    if (!user_id || !new_password) {
      return await renderAdminUsersPage(res, {
        error: 'Seleziona un utente e inserisci la nuova password'
      });
    }

    const user = await getUserById(String(user_id));

    if (!user || user.role !== 'user') {
      return await renderAdminUsersPage(res, {
        error: 'Utente non trovato'
      });
    }

    const sameAsCurrent = await bcrypt.compare(String(new_password), user.password_hash || '');
    if (sameAsCurrent) {
      return await renderAdminUsersPage(res, {
        error: 'La nuova password coincide con quella attuale'
      });
    }

    const hash = await bcrypt.hash(String(new_password), 10);

    await usersCol.doc(String(user_id)).update({
      password_hash: hash
    });

    return await renderAdminUsersPage(res, {
      success: `Password aggiornata per ${user.username}`
    });
  } catch (err) {
    console.error('Errore cambio password admin:', err);

    const users = await getAllUsers().catch(() => []);
    res.render('admin-users', {
      users,
      error: 'Errore aggiornamento password utente',
      success: null
    });
  }
});

/* =========================
   ROUTES - ADMIN ROOMS
========================= */

app.get('/admin/rooms', requireAdmin, async (req, res) => {
  try {
    const rooms = await getAllRooms();
    res.render('admin-rooms', { rooms, error: null });
  } catch (err) {
    console.error('Errore lista stanze:', err);
    res.status(500).send('Errore lista stanze');
  }
});

app.post('/admin/rooms/create', requireAdmin, async (req, res) => {
  try {
    const { name, description } = req.body;

    if (!name || !String(name).trim()) {
      const rooms = await getAllRooms();
      return res.render('admin-rooms', {
        rooms,
        error: 'Nome stanza obbligatorio'
      });
    }

    await roomsCol.add({
      name: String(name).trim(),
      description: description ? String(description).trim() : '',
      active: true,
      created_at: nowIso()
    });

    res.redirect('/admin/rooms');
  } catch (err) {
    console.error('Errore creazione stanza:', err);
    res.status(500).send('Errore creazione stanza');
  }
});

app.post('/admin/rooms/toggle/:id', requireAdmin, async (req, res) => {
  try {
    const id = String(req.params.id);
    const room = await getRoomById(id);

    if (!room) return res.redirect('/admin/rooms');

    await roomsCol.doc(id).update({
      active: !roomIsActive(room)
    });

    res.redirect('/admin/rooms');
  } catch (err) {
    console.error('Errore aggiornamento stanza:', err);
    res.status(500).send('Errore aggiornamento stanza');
  }
});

app.post('/admin/rooms/delete/:id', requireAdmin, async (req, res) => {
  try {
    const id = String(req.params.id);
    const room = await getRoomById(id);

    if (!room) return res.redirect('/admin/rooms');

    const linkedBookingsSnap = await bookingsCol
      .where('room_id', '==', id)
      .limit(1)
      .get();

    if (!linkedBookingsSnap.empty) {
      const rooms = await getAllRooms();
      return res.render('admin-rooms', {
        rooms,
        error: 'Non puoi eliminare questa stanza perché ha prenotazioni collegate. Elimina prima le prenotazioni oppure disattivala.'
      });
    }

    await roomsCol.doc(id).delete();

    res.redirect('/admin/rooms');
  } catch (err) {
    console.error('Errore eliminazione stanza:', err);

    const rooms = await getAllRooms().catch(() => []);
    res.render('admin-rooms', {
      rooms,
      error: 'Errore eliminazione stanza'
    });
  }
});

/* =========================
   ROUTES - ADMIN BOOKINGS
========================= */
app.get('/admin/bookings', requireAdmin, async (req, res) => {
  try {
    return await renderAdminBookingsPage(res);
  } catch (err) {
    console.error('Errore lista prenotazioni:', err);
    res.status(500).send('Errore lista prenotazioni');
  }
});

app.get('/admin/availability', requireAdmin, async (req, res) => {
  try {
    const { room_id, booking_date } = req.query;

    if (!room_id || !booking_date) {
      return res.json({ occupiedSlots: [], bookings: [] });
    }

    const bookings = await getBookingsForDateAndRoom(room_id, booking_date);

    const simplified = bookings.map(b => ({
      start_hour: Number(b.start_hour),
      end_hour: Number(b.end_hour)
    }));

    const occupiedSlots = [];

    for (const booking of simplified) {
      for (let h = booking.start_hour; h < booking.end_hour; h += 0.5) {
        occupiedSlots.push(Number(h.toFixed(1)));
      }
    }

    res.json({
      occupiedSlots,
      bookings: simplified
    });
  } catch (err) {
    console.error('Errore caricamento disponibilità admin:', err);
    res.status(500).json({ error: 'Errore caricamento disponibilità admin' });
  }
});

app.post('/admin/bookings/create', requireAdmin, async (req, res) => {
  try {
    const { user_id, room_id, booking_date, start_hour, end_hour, admin_note } = req.body;

    const start = Number(start_hour);
    const end = Number(end_hour);

    if (!user_id || !room_id || !booking_date || Number.isNaN(start) || Number.isNaN(end)) {
      return await renderAdminBookingsPage(res, {
        error: 'Compila tutti i campi obbligatori'
      });
    }

    if (
      !isValidHalfHour(start) ||
      !isValidHalfHour(end) ||
      start < 8 ||
      start >= 20.5 ||
      end <= 8 ||
      end > 20.5 ||
      start >= end
    ) {
      return await renderAdminBookingsPage(res, {
        error: 'Orari non validi. Puoi prenotare solo dalle 08:00 alle 20:30 ogni 30 minuti'
      });
    }

    const [user, room] = await Promise.all([
      getUserById(String(user_id)),
      getRoomById(String(room_id))
    ]);

    if (!user || user.role !== 'user' || !userIsActive(user)) {
      return await renderAdminBookingsPage(res, {
        error: 'Utente non valido o disattivato'
      });
    }

    if (!room || !roomIsActive(room)) {
      return await renderAdminBookingsPage(res, {
        error: 'Stanza non disponibile'
      });
    }

    if (hasBookingAlreadyStarted(String(booking_date), start)) {
  return await renderAdminBookingsPage(res, {
    error: 'Non puoi prenotare in un orario già passato'
  });
}

    const totalHours = end - start;
const privateNote = String(admin_note || '').trim().slice(0, 1000);

try {
  await createBookingAtomically({
    user_id: String(user_id),
    room_id: String(room_id),
    booking_date: String(booking_date),
    start_hour: start,
    end_hour: end,
    total_hours: totalHours,
    status: 'active',
    admin_note: privateNote,
    created_by_admin_id: String(req.session.user.id),
    created_by_admin_username: String(req.session.user.username || ''),
    created_at: nowIso()
  });
} catch (err) {
  if (err.code === 'BOOKING_CONFLICT') {
    return await renderAdminBookingsPage(res, {
      error: 'Quella fascia oraria è già prenotata per questa stanza'
    });
  }
  throw err;
}

return await renderAdminBookingsPage(res, {
  success: 'Prenotazione inserita con successo'
});

  } catch (err) {
    console.error('Errore creazione prenotazione admin:', err);
    res.status(500).send('Errore creazione prenotazione admin');
  }
});

app.post('/admin/bookings/delete/:id', requireAdmin, async (req, res) => {
  try {
    const id = String(req.params.id);
    await bookingsCol.doc(id).delete();
    res.redirect('/admin/bookings');
  } catch (err) {
    console.error('Errore eliminazione prenotazione:', err);
    res.status(500).send('Errore eliminazione prenotazione');
  }
});


/* =========================
   ROUTES - ADMIN REPORTS
========================= */
app.get('/admin/reports', requireAdmin, async (req, res) => {
  try {
    const { type = 'monthly', month, weekStart, userId } = req.query;

const todayRome = getRomeTodayYmd();
const currentMonth = todayRome.slice(0, 7);

let startDate;
let endDate;

if (type === 'weekly') {
  startDate = weekStart || getWeekStartMondayYmd(todayRome);
  endDate = addDaysToYmd(startDate, 6);
} else {
  const monthStr = month || currentMonth;
  startDate = `${monthStr}-01`;
  endDate = monthLastDay(monthStr);
}

    const [allBookings, allUsers] = await Promise.all([
  getAllBookings(),
  getAllUsers()
]);

const users = allUsers
  .filter(u => u.role === 'user')
  .sort((a, b) => String(a.username || '').localeCompare(String(b.username || ''), 'it'));

const filteredBookings = allBookings.filter(b => {
  if (!bookingIsActive(b)) return false;
  if (String(b.booking_date) < startDate) return false;
  if (String(b.booking_date) > endDate) return false;
  if (userId && String(b.user_id) !== String(userId)) return false;
  return true;
});

const usersMap = new Map(users.map(u => [String(u.id), u.username]));

    const aggregate = new Map();

    for (const booking of filteredBookings) {
      const uid = String(booking.user_id);
      const username = usersMap.get(uid) || 'Utente';

      if (!aggregate.has(uid)) {
        aggregate.set(uid, {
          user_id: uid,
          username,
          total_hours: 0,
          total_bookings: 0
        });
      }

      const row = aggregate.get(uid);
      row.total_hours += Number(booking.total_hours || 0);
      row.total_bookings += 1;
    }

    const reportRows = [...aggregate.values()].sort((a, b) => b.total_hours - a.total_hours);

    const effectiveMonth = month || currentMonth;
const effectiveWeekStart = weekStart || getWeekStartMondayYmd(todayRome);

res.render('admin-reports', {
  reportRows,
  users,
  filters: {
    type,
    month: effectiveMonth,
    weekStart: effectiveWeekStart,
    userId: userId || ''
  },
  startDate,
  endDate
});
  } catch (err) {
    console.error('Errore report:', err);
    res.status(500).send('Errore report');
  }
});

/* =========================
   ROUTES - USER DASHBOARD
========================= */
app.get('/user/dashboard', requireUser, async (req, res) => {
  try {
    return await renderUserDashboardPage(req, res);
  } catch (err) {
    console.error('Errore dashboard utente:', err);
    res.status(500).send('Errore dashboard utente');
  }
});

app.post('/user/change-password', requireUser, async (req, res) => {
  try {
    const { current_password, new_password, confirm_password } = req.body;

    if (!current_password || !new_password || !confirm_password) {
      return await renderUserDashboardPage(req, res, {
        error: 'Compila tutti i campi per cambiare password'
      });
    }

    if (String(new_password) !== String(confirm_password)) {
      return await renderUserDashboardPage(req, res, {
        error: 'Le nuove password non coincidono'
      });
    }

    const user = await getUserById(String(req.session.user.id));

    if (!user || !userIsActive(user)) {
      return res.redirect('/logout');
    }

    const currentOk = await bcrypt.compare(String(current_password), user.password_hash || '');
    if (!currentOk) {
      return await renderUserDashboardPage(req, res, {
        error: 'La password attuale non è corretta'
      });
    }

    const sameAsCurrent = await bcrypt.compare(String(new_password), user.password_hash || '');
    if (sameAsCurrent) {
      return await renderUserDashboardPage(req, res, {
        error: 'La nuova password deve essere diversa da quella attuale'
      });
    }

    const hash = await bcrypt.hash(String(new_password), 10);

    await usersCol.doc(String(req.session.user.id)).update({
      password_hash: hash
    });

    return await renderUserDashboardPage(req, res, {
      success: 'Password aggiornata con successo'
    });
  } catch (err) {
    console.error('Errore cambio password utente:', err);
    res.status(500).send('Errore cambio password utente');
  }
});

/* =========================
   ROUTES - USER AVAILABILITY
========================= */


app.get('/user/availability', requireUser, async (req, res) => {
  try {
    const { room_id, booking_date } = req.query;

    if (!room_id || !booking_date) {
      return res.json({ occupiedSlots: [], bookings: [] });
    }

    const bookings = await getBookingsForDateAndRoom(room_id, booking_date);

    const simplified = bookings.map(b => ({
      start_hour: Number(b.start_hour),
      end_hour: Number(b.end_hour)
    }));

    const occupiedSlots = [];

    for (const booking of simplified) {
      for (let h = booking.start_hour; h < booking.end_hour; h += 0.5) {
        occupiedSlots.push(Number(h.toFixed(1)));
      }
    }

    res.json({
      occupiedSlots,
      bookings: simplified
    });
  } catch (err) {
    console.error('Errore caricamento disponibilità:', err);
    res.status(500).json({ error: 'Errore caricamento disponibilità' });
  }
});

/* =========================
   ROUTES - USER BOOK ROOM
========================= */
app.get('/user/book-room', requireUser, async (req, res) => {
  try {
    const rooms = await getActiveRoomsSortedByName();

    res.render('user-book-room', {
      rooms,
      error: null,
      success: null
    });
  } catch (err) {
    console.error('Errore pagina prenotazione:', err);
    res.status(500).send('Errore pagina prenotazione');
  }
});

app.post('/user/book-room', requireUser, async (req, res) => {
  try {
    const { room_id, booking_date, start_hour, end_hour } = req.body;
    const rooms = await getActiveRoomsSortedByName();

    const start = Number(start_hour);
const end = Number(end_hour);

if (!room_id || !booking_date || Number.isNaN(start) || Number.isNaN(end)) {
  return res.render('user-book-room', {
    rooms,
    error: 'Compila tutti i campi',
    success: null
  });
}

if (
  !isValidHalfHour(start) ||
  !isValidHalfHour(end) ||
  start < 8 ||
  start >= 20.5 ||
  end <= 8 ||
  end > 20.5 ||
  start >= end
) {
  return res.render('user-book-room', {
    rooms,
    error: 'Orari non validi. Puoi prenotare solo dalle 08:00 alle 20:30 ogni 30 minuti',
    success: null
  });
}

    const room = await getRoomById(String(room_id));

if (!room || !roomIsActive(room)) {
  return res.render('user-book-room', {
    rooms,
    error: 'Stanza non disponibile',
    success: null
  });
}

if (hasBookingAlreadyStarted(String(booking_date), start)) {
  return res.render('user-book-room', {
    rooms,
    error: 'Non puoi prenotare in un orario già passato',
    success: null
  });
}

const totalHours = end - start;


try {
  await createBookingAtomically({
    user_id: String(req.session.user.id),
    room_id: String(room_id),
    booking_date: String(booking_date),
    start_hour: start,
    end_hour: end,
    total_hours: totalHours,
    status: 'active',
    created_at: nowIso()
  });
} catch (err) {
  if (err.code === 'BOOKING_CONFLICT') {
    return res.render('user-book-room', {
      rooms,
      error: 'Quella fascia oraria è già prenotata per questa stanza',
      success: null
    });
  }
  throw err;
}

res.render('user-book-room', {
  rooms,
  error: null,
  success: 'Prenotazione inserita con successo'
});

  } catch (err) {
    console.error('Errore creazione prenotazione:', err);
    res.status(500).send('Errore creazione prenotazione');
  }
});

/* =========================
   ROUTES - USER MY BOOKINGS
========================= */
app.get('/user/my-bookings', requireUser, async (req, res) => {
  try {
    const allBookings = await getAllBookings();

    const rawBookings = allBookings
      .filter(b => String(b.user_id) === String(req.session.user.id))
      .sort(sortByBookingDateTimeDesc);

    const enriched = await enrichBookings(rawBookings);

    const bookings = enriched.map(b => ({
      ...b,
      cancellable: isBookingCancellable(b.booking_date, b.start_hour)
    }));

    res.render('user-my-bookings', {
      bookings,
      user: req.session.user
    });
  } catch (err) {
    console.error('Errore lista prenotazioni utente:', err);
    res.status(500).send('Errore lista prenotazioni utente');
  }
});

app.post('/user/bookings/delete/:id', requireUser, async (req, res) => {
  try {
    const booking = await getBookingById(req.params.id);

    if (!booking || String(booking.user_id) !== String(req.session.user.id)) {
      return res.status(404).send('Prenotazione non trovata');
    }

    if (!isBookingCancellable(booking.booking_date, booking.start_hour)) {
      return res
        .status(400)
        .send('Non puoi cancellare prenotazioni già passate o entro 1 ora dall’inizio');
    }

    await bookingsCol.doc(req.params.id).delete();

    res.redirect('/user/my-bookings');
  } catch (err) {
    console.error(err);
    res.status(500).send('Errore cancellazione prenotazione');
  }
});

/* =========================
   CLEANUP HELPERS
========================= */
function subtractMonthsFromYmd(ymd, months) {
  let [y, m, d] = String(ymd).split('-').map(Number);

  m -= Number(months);

  while (m <= 0) {
    m += 12;
    y -= 1;
  }

  const lastDayOfTargetMonth = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const safeDay = Math.min(d, lastDayOfTargetMonth);

  return `${y}-${pad2(m)}-${pad2(safeDay)}`;
}

async function cleanupExpiredSessions() {
  let totalDeleted = 0;
  const now = new Date();

  while (true) {
    const snap = await sessionsCol
      .where('expiresAt', '<=', now)
      .limit(CLEANUP_BATCH_SIZE)
      .get();

    if (snap.empty) break;

    const batch = db.batch();

    snap.docs.forEach(doc => {
      batch.delete(doc.ref);
    });

    await batch.commit();
    totalDeleted += snap.size;

    if (snap.size < CLEANUP_BATCH_SIZE) break;
  }

  if (totalDeleted > 0) {
    console.log(`[cleanup] Sessioni scadute eliminate: ${totalDeleted}`);
  }
}

async function archiveOldBookings() {
  let totalArchived = 0;
  const cutoffDate = subtractMonthsFromYmd(getRomeTodayYmd(), 3);
  const archivedAt = nowIso();

  while (true) {
    const snap = await bookingsCol
      .where('booking_date', '<', cutoffDate)
      .limit(CLEANUP_BATCH_SIZE)
      .get();

    if (snap.empty) break;

    const batch = db.batch();

    snap.docs.forEach(doc => {
      const data = doc.data();

      batch.set(
        bookingsArchiveCol.doc(doc.id),
        {
          ...data,
          original_id: doc.id,
          archived_at: archivedAt,
          archive_reason: 'older_than_3_months'
        },
        { merge: true }
      );

      batch.delete(doc.ref);
    });

    await batch.commit();
    totalArchived += snap.size;

    if (snap.size < CLEANUP_BATCH_SIZE) break;
  }

  if (totalArchived > 0) {
    console.log(
      `[cleanup] Bookings archiviate: ${totalArchived} | cutoff: ${cutoffDate}`
    );
  }
}

async function runStartupCleanup() {
  try {
    await cleanupExpiredSessions();
  } catch (err) {
    console.error('Errore pulizia sessioni:', err);
  }

  try {
    await archiveOldBookings();
  } catch (err) {
    console.error('Errore archiviazione bookings:', err);
  }
}

function startCleanupIntervals() {
  setInterval(async () => {
    try {
      await cleanupExpiredSessions();
    } catch (err) {
      console.error('Errore pulizia periodica sessioni:', err);
    }
  }, SESSION_CLEANUP_INTERVAL_MS);

  setInterval(async () => {
    try {
      await archiveOldBookings();
    } catch (err) {
      console.error('Errore pulizia periodica bookings:', err);
    }
  }, BOOKINGS_CLEANUP_INTERVAL_MS);
}


/* =========================
   START SERVER
========================= */
async function startServer() {
  try {
    await ensureDefaultAdmin();
    await runStartupCleanup();

    app.listen(PORT, () => {
      console.log(`Server avviato sulla porta ${PORT}`);
    });

    startCleanupIntervals();
  } catch (err) {
    console.error('Errore avvio server:', err);
    process.exit(1);
  }
}
startServer();