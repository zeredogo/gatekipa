const axios = require('axios');
const SUDO_API_KEY = process.env.SUDO_API_KEY || "test";
const VAULT_BASE_URL = "https://vault.sudo.africa";

const client = axios.create({
  baseURL: VAULT_BASE_URL,
  headers: {
    Authorization: `Bearer ${SUDO_API_KEY}`,
    "Content-Type": "application/json",
    Accept: "application/json",
  },
});

async function test() {
  try {
     const res = await client.get('/cards/123/token').catch(e => e.response ? e.response.status + ' ' + JSON.stringify(e.response.data) : e.message);
     console.log(res);
  } catch (e) { console.error(e); }
}
test();
