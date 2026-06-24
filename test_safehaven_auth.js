const fs = require('fs');
const crypto = require('crypto');
const axios = require('./functions/node_modules/axios');

const CLIENT_ID = 'f026f8e8f8065807ddce916e6f3cee47';
const PRIVATE_KEY = fs.readFileSync('./functions/safehaven_keys/privatekey.pem', 'utf8');
const BASE_URL = 'https://api.safehavenmfb.com';

function base64url(buf) {
  return buf.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function signJWT(payload) {
  const header = { alg: 'RS256', typ: 'JWT' };
  const enc = (obj) => base64url(Buffer.from(JSON.stringify(obj)));
  const signInput = `${enc(header)}.${enc(payload)}`;
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(signInput);
  const sig = signer.sign({ key: PRIVATE_KEY, padding: crypto.constants.RSA_PKCS1_PADDING });
  return `${signInput}.${base64url(sig)}`;
}

async function test(label, jwtClaims, bodyExtra) {
  try {
    const assertion = signJWT(jwtClaims);
    const body = new URLSearchParams({
      grant_type: 'client_credentials',
      client_assertion_type: 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',
      client_assertion: assertion,
      ...bodyExtra
    });
    const res = await axios.post(`${BASE_URL}/oauth2/token`, body.toString(), {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json', 'ClientID': CLIENT_ID }
    });
    console.log(`✅ [${label}]`, JSON.stringify(res.data).substring(0, 200));
  } catch (err) {
    console.log(`❌ [${label}] ${err.response?.status}:`, JSON.stringify(err.response?.data));
  }
}

async function main() {
  console.log('Testing SafeHaven auth combos...\n');
  const now = Math.floor(Date.now() / 1000);

  await test('iss=url,aud=base',
    { iss: 'https://gatekipa.com', sub: CLIENT_ID, aud: BASE_URL, jti: crypto.randomUUID(), iat: now, exp: now+300 },
    {});

  await test('iss=clientId,aud=base',
    { iss: CLIENT_ID, sub: CLIENT_ID, aud: BASE_URL, jti: crypto.randomUUID(), iat: now, exp: now+300 },
    {});

  await test('iss=clientId,aud=tokenEndpoint',
    { iss: CLIENT_ID, sub: CLIENT_ID, aud: `${BASE_URL}/oauth2/token`, jti: crypto.randomUUID(), iat: now, exp: now+300 },
    {});

  await test('iss=url,aud=base,+client_id',
    { iss: 'https://gatekipa.com', sub: CLIENT_ID, aud: BASE_URL, jti: crypto.randomUUID(), iat: now, exp: now+300 },
    { client_id: CLIENT_ID });

  await test('iss=clientId,aud=base,+client_id',
    { iss: CLIENT_ID, sub: CLIENT_ID, aud: BASE_URL, jti: crypto.randomUUID(), iat: now, exp: now+300 },
    { client_id: CLIENT_ID });
}

main().catch(console.error);
