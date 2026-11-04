'use strict';
const http2 = require('node:http2');
const { createPrivateKey, sign } = require('node:crypto');

// Credentials stay on the server. No SDK or advertising identifier is involved.
function createAPNsSender(env = process.env) {
  const config = env.APNS_CONFIG ? JSON.parse(env.APNS_CONFIG) : null;
  if (!config?.keyId || !config?.teamId || !config?.privateKey || !config?.topic) return null;
  const key = createPrivateKey(config.privateKey);
  let cachedToken, issuedAt = 0;
  function authorization() {
    const time = Math.floor(Date.now()/1000);
    if (!cachedToken || time-issuedAt > 3000) {
      const header = Buffer.from(JSON.stringify({alg:'ES256',kid:config.keyId})).toString('base64url');
      const claims = Buffer.from(JSON.stringify({iss:config.teamId,iat:time})).toString('base64url');
      const body = `${header}.${claims}`;
      cachedToken = `${body}.${sign('sha256',Buffer.from(body),{key,dsaEncoding:'ieee-p1363'}).toString('base64url')}`;
      issuedAt=time;
    }
    return cachedToken;
  }
  return async function send(device, payload, eventId, expiresAt) {
    const host = device.environment === 'development' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
    return await new Promise(resolve => {
      const client = http2.connect(host);
      let finished=false;
      const finish = value => { if (finished) return; finished=true;clearTimeout(timer);client.destroy();resolve(value); };
      const timer=setTimeout(()=>finish({retry:true,reason:'Timeout'}),10000);
      client.on('error',()=>finish({retry:true,reason:'NetworkError'}));
      const req=client.request({':method':'POST',':path':`/3/device/${device.token}`,
        authorization:`bearer ${authorization()}`,'apns-topic':config.topic,'apns-push-type':'alert',
        'apns-priority':'10','apns-expiration':String(Math.floor(expiresAt/1000)),
        'apns-collapse-id':eventId});
      let status=0, data='';
      req.on('response',headers=>{status=Number(headers[':status']);});
      req.on('data',chunk=>{if(data.length<4096)data+=chunk;});
      req.on('error',()=>finish({retry:true,reason:'NetworkError'}));
      req.on('end',()=>{
        let reason='';try{reason=JSON.parse(data).reason || '';}catch{}
        const invalid = status===410 || ['BadDeviceToken','DeviceTokenNotForTopic','Unregistered'].includes(reason);
        finish({ok:status===200,invalid,retry:!invalid && status!==200,reason:reason || `HTTP${status}`});
      });
      req.end(JSON.stringify(payload));
    });
  };
}
module.exports={createAPNsSender};
