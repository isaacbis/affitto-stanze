'use strict';
const bcrypt = require('bcrypt');

async function seedReview(db, today) {
  if (process.env.FIREBASE_SERVICE_ACCOUNT) throw new Error('Review service must not have Firebase credentials');
  const password = process.env.AFFITTO_REVIEW_PASSWORD;
  if (!password || password.length < 20) throw new Error('Missing strong review password');
  const passwordHash = await bcrypt.hash(password, 10);
  const createdAt = new Date().toISOString();
  const users = db.collection('users');
  await users.doc('review-admin').set({
    username: 'play-review-admin', password_hash: passwordHash, role: 'admin', active: true, created_at: createdAt
  });
  await users.doc('review-user').set({
    username: 'play-review-user', password_hash: passwordHash, role: 'user', active: true, created_at: createdAt
  });
  const rooms = db.collection('rooms');
  await rooms.doc('demo-studio').set({
    name: 'Studio demo', active: true, description: 'Spazio fittizio per la revisione.', created_at: createdAt
  });
  await rooms.doc('demo-meeting').set({
    name: 'Sala demo', active: true, description: 'Secondo spazio di prova.', created_at: createdAt
  });
  await db.collection('bookings').doc('demo-booking').set({
    user_id: 'review-user', room_id: 'demo-studio', booking_date: today,
    start_hour: 9, end_hour: 10, total_hours: 1, status: 'active', created_at: createdAt
  });
}

module.exports = { seedReview };
