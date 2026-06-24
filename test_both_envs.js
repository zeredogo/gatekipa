const fs = require('fs');
const crypto = require('crypto');
const axios = require('./functions/node_modules/axios');
const CLIENT_ID = 'c980914d76a837912af88f41254f7825';
const PRIVATE_KEY = fs.readFileSync('./functions/safehaven_keys_new/privatekey.pem', 'utf8');

function b64u(buf){return buf.toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'')}

async function testEnv(baseURL) {
  const now = Math.floor(Date.now()/1000);
  const hdr={alg:'RS256',typ:'JWT'};
  const pay={iss:'https://gatekipa.com',sub:CLIENT_ID,aud:baseURL,jti:crypto.randomUUID(),iat:now,exp:now+300};
  const si=b64u(Buffer.from(JSON.stringify(hdr)))+'.'+b64u(Buffer.from(JSON.stringify(pay)));
  const s=crypto.createSign('RSA-SHA256');s.update(si);
  const sig=s.sign({key:PRIVATE_KEY,padding:crypto.constants.RSA_PKCS1_PADDING});
  const assertion=si+'.'+b64u(sig);
  
  const body=new URLSearchParams({grant_type:'client_credentials',client_assertion_type:'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',client_assertion:assertion,client_id:CLIENT_ID});
  
  try {
    const tr=await axios.post(baseURL+'/oauth2/token',body.toString(),{headers:{'Content-Type':'application/x-www-form-urlencoded','Accept':'application/json','ClientID':CLIENT_ID}});
    console.log(`[SUCCESS] ${baseURL}:`, tr.data.error || 'Token generated successfully!');
  } catch(e) {
    console.log(`[FAILED] ${baseURL}:`, e.response?.data || e.message);
  }
}

async function run() {
  await testEnv('https://api.safehavenmfb.com');
  await testEnv('https://api.sandbox.safehavenmfb.com');
}
run().catch(console.log);
