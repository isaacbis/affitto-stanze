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

/* =========================
   APP CONFIG
========================= */
app.set('trust proxy', 1);
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

app.use(express.urlencoded({ extended: true }));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

app.use(
  session({
    secret: process.env.SESSION_SECRET || 'cambia-questo-secret-subito',
    resave: false,
    saveUninitialized: false,
    cookie: {
      secure: process.env.NODE_ENV === 'production',
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

/* =========================
   GENERIC HELPERS
========================= */
function nowIso() {
  return new Date().toISOString();
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

function isBookingCancellable(bookingDate, startHour) {
  const bookingStart = buildBookingStartDate(bookingDate, startHour);
  const now = new Date();
  const diffMs = bookingStart.getTime() - now.getTime();

  // cancellabile solo se mancano PIÙ di 60 minuti
  return diffMs > 60 * 60 * 1000;
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
  const snap = await usersCol
    .where('username', '==', String(username))
    .limit(1)
    .get();

  if (snap.empty) return null;

  const doc = snap.docs[0];
  return { id: doc.id, ...doc.data() };
}

async function getActiveRoomsSortedByName() {
  const snap = await roomsCol.where('active', '==', true).get();
  return snap.docs
    .map(doc => ({ id: doc.id, ...doc.data() }))
    .sort((a, b) => String(a.name || '').localeCompare(String(b.name || ''), 'it'));
}

async function getActiveUsersSortedByUsername() {
  const snap = await usersCol.get();

  return snap.docs
    .map(doc => ({ id: doc.id, ...doc.data() }))
    .filter(u => u.role === 'user' && u.active === true)
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

  const hash = await bcrypt.hash('admin123', 10);

  await usersCol.add({
    username: 'admin',
    password_hash: hash,
    role: 'admin',
    active: true,
    created_at: nowIso()
  });

  console.log('Admin creato: username=admin password=admin123');
}

/* =========================
   AUTH MIDDLEWARE
========================= */
function requireAdmin(req, res, next) {
  if (!req.session.user) return res.redirect('/login');
  if (req.session.user.role !== 'admin') return res.status(403).send('Accesso negato');
  next();
}

function requireUser(req, res, next) {
  if (!req.session.user) return res.redirect('/login');
  if (req.session.user.role !== 'user') return res.status(403).send('Accesso negato');
  next();
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
    const { username, password } = req.body;

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
    res.clearCookie('connect.sid');
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
    const today = dateToYmd(new Date());

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
    const users = await getAllUsers();

    res.render('admin-users', {
      users,
      error: null,
      success: null
    });
  } catch (err) {
    console.error('Errore lista utenti:', err);
    res.status(500).send('Errore lista utenti');
  }
});

app.post('/admin/users/create', requireAdmin, async (req, res) => {
  try {
    const { username, password, role } = req.body;

    if (!username || !password || !role) {
      const users = await getAllUsers();
      return res.render('admin-users', {
        users,
        error: 'Compila tutti i campi',
        success: null
      });
    }

    if (!isValidRole(role)) {
      const users = await getAllUsers();
      return res.render('admin-users', {
        users,
        error: 'Ruolo non valido',
        success: null
      });
    }

    const existing = await getUserByUsername(username);
    if (existing) {
      const users = await getAllUsers();
      return res.render('admin-users', {
        users,
        error: 'Username già esistente',
        success: null
      });
    }

    const hash = await bcrypt.hash(password, 10);

    await usersCol.add({
      username: String(username).trim(),
      password_hash: hash,
      role,
      active: true,
      created_at: nowIso()
    });

    res.redirect('/admin/users');
  } catch (err) {
    console.error('Errore creazione utente:', err);
    const users = await getAllUsers().catch(() => []);
    res.render('admin-users', {
      users,
      error: 'Errore inserimento utente',
      success: null
    });
  }
});

app.post('/admin/users/toggle/:id', requireAdmin, async (req, res) => {
  try {
    const id = String(req.params.id);
    const user = await getUserById(id);

    if (!user) return res.redirect('/admin/users');

    await usersCol.doc(id).update({
      active: !userIsActive(user)
    });

    res.redirect('/admin/users');
  } catch (err) {
    console.error('Errore aggiornamento utente:', err);
    res.status(500).send('Errore aggiornamento utente');
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
    const rawBookings = (await getAllBookings()).sort(sortByBookingDateTimeDesc);
    const bookings = await enrichBookings(rawBookings);

    res.render('admin-bookings', { bookings });
  } catch (err) {
    console.error('Errore lista prenotazioni:', err);
    res.status(500).send('Errore lista prenotazioni');
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

const nowLocal = new Date();
const currentMonth = `${nowLocal.getFullYear()}-${String(nowLocal.getMonth() + 1).padStart(2, '0')}`;

    let startDate;
    let endDate;

    if (type === 'weekly') {
      const base = weekStart
        ? new Date(`${weekStart}T00:00:00`)
        : getWeekStartMonday(new Date());

      startDate = dateToYmd(base);
      const end = new Date(base);
      end.setDate(end.getDate() + 6);
      endDate = dateToYmd(end);
    } else {
      const monthStr = month || currentMonth;
      startDate = `${monthStr}-01`;
      endDate = monthLastDay(monthStr);
    }

    const [allBookings, users] = await Promise.all([
      getAllBookings(),
      getActiveUsersSortedByUsername()
    ]);

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

const nowDate = new Date();
const monday = new Date(nowDate);
monday.setDate(nowDate.getDate() - ((nowDate.getDay() + 6) % 7));
const effectiveWeekStart = weekStart || [
  monday.getFullYear(),
  String(monday.getMonth() + 1).padStart(2, '0'),
  String(monday.getDate()).padStart(2, '0')
].join('-');

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
    const allBookings = await getAllBookings();

    const myBookingsRaw = allBookings
      .filter(b => String(b.user_id) === String(req.session.user.id))
      .sort(sortByBookingDateTimeDesc)
      .slice(0, 10);

    const bookings = await enrichBookings(myBookingsRaw);

    res.render('user-dashboard', {
      user: req.session.user,
      bookings
    });
  } catch (err) {
    console.error('Errore dashboard utente:', err);
    res.status(500).send('Errore dashboard utente');
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
  start >= 20 ||
  end <= 8 ||
  end > 20 ||
  start >= end
) {
  return res.render('user-book-room', {
    rooms,
    error: 'Orari non validi. Puoi prenotare solo dalle 08:00 alle 20:00 ogni 30 minuti',
    success: null
  });
}

    const bookingStartDate = buildBookingStartDate(booking_date, start);
    const now = new Date();

    if (bookingStartDate.getTime() <= now.getTime()) {
      return res.render('user-book-room', {
        rooms,
        error: 'Non puoi prenotare in un orario già passato',
        success: null
      });
    }

    const existingBookings = await getBookingsForDateAndRoom(room_id, booking_date);

    const conflict = existingBookings.find(b => {
      const existingStart = Number(b.start_hour);
      const existingEnd = Number(b.end_hour);
      return !(start >= existingEnd || end <= existingStart);
    });

    if (conflict) {
      return res.render('user-book-room', {
        rooms,
        error: 'Quella fascia oraria è già prenotata per questa stanza',
        success: null
      });
    }

    const totalHours = end - start;

    await bookingsCol.add({
      user_id: String(req.session.user.id),
      room_id: String(room_id),
      booking_date: String(booking_date),
      start_hour: start,
      end_hour: end,
      total_hours: totalHours,
      status: 'active',
      created_at: nowIso()
    });

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
   START SERVER
========================= */
async function startServer() {
  try {
    await ensureDefaultAdmin();

    app.listen(PORT, () => {
      console.log(`Server avviato sulla porta ${PORT}`);
    });
  } catch (err) {
    console.error('Errore avvio server:', err);
    process.exit(1);
  }
}

startServer();