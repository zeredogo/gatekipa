const https = require('https');
const data = JSON.stringify({
  cardholder_id: "test",
  card_type: "virtual",
  card_brand: "Mastercard",
  card_currency: "USD",
  pin: "U2FsdGVkX1+26FnAwmz/dVcjYdTgglBwhK8CAhH1q8g=",
  card_pin: "U2FsdGVkX1+26FnAwmz/dVcjYdTgglBwhK8CAhH1q8g="
});

const req = https.request({
  hostname: 'issuecards.api.bridgecard.co',
  path: '/v1/issuing/cards/create_card',
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Content-Length': data.length
  }
}, (res) => {
  let body = '';
  res.on('data', d => body += d);
  res.on('end', () => console.log(res.statusCode, body));
});

req.write(data);
req.end();
