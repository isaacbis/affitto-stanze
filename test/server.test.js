'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const { memoryFirestore } = require('./memory-firestore');
const { createLoginThrottle } = require('../lib/login-throttle');
const root = path.resolve(__dirname, '..');

async function withServer(fn) {
  const db = memoryFirestore();
  const hash = await require('bcrypt').hash('test-password', 4);
  for (const [id, role] of [['admin', 'admin'], ['alice', 'user'], ['bob', 'user']])
    await db.collection('users').doc(id).set({username: id, role, active: true, password_hash: hash});
  await db.collection('rooms').doc('room').set({name:'Sala test', active:true});
  const localRequire = createRequire(path.join(root, 'server.js'));
  const context = { require: name => name === 'firebase-admin/app' ? { getApps: () => [1] } : name === 'firebase-admin/firestore' ? {getFirestore: () => db, FieldValue:{serverTimestamp: () => new Date()}} : localRequire(name),
    __dirname: root, console, process: { env: {SESSION_SECRET: 'test-secret'}, exit: () => {throw Error('Unexpected exit');} }, setInterval };
  vm.runInNewContext(fs.readFileSync(path.join(root,'server.js'),'utf8').replace(/startServer\(\);?\s*$/, 'globalThis.testApp = app;'), context);
  const server = context.testApp.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening',resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const request = (route, {method='GET', body, cookie, ios=true}={}) => fetch(base+route, { method, redirect:'manual', headers: { ...(ios ? {'X-Affitto-Client':'ios'} : {}), ...(body ? {'Content-Type':'application/json'} : {}), ...(cookie ? {Cookie:cookie} : {}) }, body: body ? JSON.stringify(body) : undefined });
  try { await fn({db,request}); } finally { await new Promise(resolve => server.close(resolve)); }
}

test('API: login, role isolation, booking conflict, cancellation and invalid input', async () => withServer(async ({request}) => {
  const login = async username => {
    const response = await request('/api/v1/login', {method:'POST',body:{username,password:'test-password'}});
    assert.equal(response.status,200); return response.headers.get('set-cookie').split(';')[0];
  };
  assert.equal((await request('/api/v1/me')).status,401);
  assert.equal((await request('/api/v1/me',{ios:false})).status,403);
  const alice = await login('alice'); const bob = await login('bob'); const admin = await login('admin');
  assert.equal((await request('/api/v1/users',{cookie:alice})).status,403);
  const payload={room_id:'room',booking_date:'2099-01-02',start_hour:8,end_hour:9};
  const created=await request('/api/v1/bookings',{method:'POST',body:payload,cookie:alice});
  assert.equal(created.status,201); const {id}=await created.json();
  assert.equal((await request('/api/v1/bookings',{method:'POST',body:payload,cookie:bob})).status,409);
  const mine=await (await request('/api/v1/bookings',{cookie:alice})).json(); assert.equal(mine.length,1);
  const others=await (await request('/api/v1/bookings',{cookie:bob})).json(); assert.equal(others.length,0);
  assert.equal((await request(`/api/v1/bookings/${id}`,{method:'DELETE',cookie:bob})).status,404);
  assert.equal((await request('/api/v1/bookings',{method:'POST',body:{...payload,booking_date:'2099-02-30'},cookie:alice})).status,400);
  assert.equal((await request('/api/v1/bookings',{method:'POST',body:payload,cookie:admin})).status,400);
  assert.equal((await request(`/api/v1/bookings/${id}`,{method:'DELETE',cookie:alice})).status,200);
  assert.equal((await request('/api/v1/change-password',{method:'POST',cookie:alice,body:{current_password:'test-password',new_password:'new-test-password'}})).status,200);
  assert.equal((await request('/api/v1/logout',{method:'POST',cookie:alice})).status,200);
  assert.equal((await request('/api/v1/me',{cookie:alice})).status,401);
  for (const route of ['/admin/dashboard','/admin/users','/admin/rooms','/admin/bookings','/admin/reports'])
    assert.equal((await request(route,{cookie:admin})).status,200,route);
  const pdf=await request('/admin/reports/pdf',{cookie:admin}); assert.equal(pdf.status,200); assert.match(await pdf.text(),/^%PDF/);
  for (const route of ['/user/dashboard','/user/book-room','/user/my-bookings'])
    assert.equal((await request(route,{cookie:bob})).status,200,route);
}));

test('Shared throttle: account across IPs, IP across accounts, expiry and IPv6 subnet', async () => {
  let time=1000000; const db=memoryFirestore();
  const throttle=createLoginThrottle({db,now:()=>time,windowMs:1000,ipLimit:3,accountLimit:2});
  async function attempt(username,ip='127.0.0.1',url='/api/v1/login') {
    let status=200; const headers={};
    await throttle({ip,body:{username},originalUrl:url},{status(code){status=code;return this;},json(){},send(){},set(k,v){headers[k]=v;}},()=>{});
    return {status,headers};
  }
  assert.equal((await attempt('alice')).status,200);
  assert.equal((await attempt('alice','127.0.0.2','/login')).status,200);
  const blocked=await attempt('alice','127.0.0.3');assert.equal(blocked.status,429);assert.equal(blocked.headers['Retry-After'],'1');
  assert.equal((await attempt('bob')).status,200); assert.equal((await attempt('charlie')).status,200);
  assert.equal((await attempt('david')).status,429);
  time+=1001; assert.equal((await attempt('alice')).status,200);
  assert.equal((await attempt('ipv6-a','2001:db8::1')).status,200);
  assert.equal((await attempt('ipv6-b','2001:db8::2')).status,200);
  assert.equal((await attempt('ipv6-c','2001:db8::3')).status,200);
  assert.equal((await attempt('ipv6-d','2001:db8::4')).status,429);
  assert.equal((await attempt('')).status,400);
});
