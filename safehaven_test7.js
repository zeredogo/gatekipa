const fs = require('fs');
const crypto = require('crypto');
const axios = require('./functions/node_modules/axios');
const CLIENT_ID = 'f026f8e8f8065807ddce916e6f3cee47';
const PRIVATE_KEY = fs.readFileSync('./functions/safehaven_keys/privatekey.pem', 'utf8');
const BASE_URL = 'https://api.safehavenmfb.com';

function b64u(buf){return buf.toString('base64').replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'')}

async function run() {
  const now = Math.floor(Date.now()/1000);
  const hdr={alg:'RS256',typ:'JWT'};
  const pay={iss:'https://gatekipa.com',sub:CLIENT_ID,aud:BASE_URL,jti:crypto.randomUUID(),iat:now,exp:now+300};
  const si=b64u(Buffer.from(JSON.stringify(hdr)))+'.'+b64u(Buffer.from(JSON.stringify(pay)));
  const s=crypto.createSign('RSA-SHA256');s.update(si);
  const sig=s.sign({key:PRIVATE_KEY,padding:crypto.constants.RSA_PKCS1_PADDING});
  const assertion=si+'.'+b64u(sig);
  
  const body=new URLSearchParams({grant_type:'client_credentials',client_assertion_type:'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',client_assertion:assertion,client_id:CLIENT_ID});
  
  const tr=await axios.post(BASE_URL+'/oauth2/token',body.toString(),{headers:{'Content-Type':'application/x-www-form-urlencoded','Accept':'application/json','ClientID':CLIENT_ID}});
  const token=tr.data.access_token;
  const ibs_client_id=tr.data.ibs_client_id;
  
  // 1. Initiate Verification
  console.log('Initiating verification...');
  let identityId = null;
  try {
    const initRes = await axios.post(BASE_URL+'/identity/v2', {
      type: 'NIN',
      number: '81750253571',
      debitAccountNumber: '0115459874',
      async: false
    }, {headers:{'Authorization':'Bearer '+token,'ClientID':CLIENT_ID,'Accept':'application/json','Content-Type':'application/json'}});
    identityId = initRes.data.data._id;
    console.log('Initiated! identityId:', identityId);
  } catch(e) {
    console.log('Init Failed:', e.response?.data);
    return;
  }
  
  // 3. Create Sub-Account
  const payload = {
    phoneNumber: '+23407036171049',
    emailAddress: 'steviekusu@gmail.com',
    externalReference: 'gatekipa_test_'+Date.now(),
    identityType: 'NIN',
    identityNumber: '81750253571',
    identityId: identityId,
    otp: '123456',
    autoSweep: false,
    firstName: "Test",
    lastName: "User",
    client_id: ibs_client_id
  };
  
  try {
    console.log('Attempting SubAccount with otp and client_id...', payload);
    const res=await axios.post(BASE_URL+'/accounts/v2/subaccount',payload,{headers:{'Authorization':'Bearer '+token,'ClientID':CLIENT_ID,'Accept':'application/json','Content-Type':'application/json'}});
    console.log('SUCCESS:', res.data);
  } catch(e) {
    console.log('FAILED SubAccount:', e.response?.status, JSON.stringify(e.response?.data));
  }
}
run().catch(console.log);
