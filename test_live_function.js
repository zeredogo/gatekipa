const admin = require("firebase-admin");
const serviceAccount = require("./gatekipa.json");
const axios = require("axios");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

async function run() {
  const customToken = await admin.auth().createCustomToken("UnxIBOSKFqgChOWXsjz2WHTcVV93");
  
  // Exchange custom token for ID token
  const res = await axios.post(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${serviceAccount.api_key || 'AIzaSyA_Fc8xFCutxNN0elWvGSqjozMuzKzNJBo'}`, {
    token: customToken,
    returnSecureToken: true
  });
  
  const idToken = res.data.idToken;
  
  try {
    const fnRes = await axios.post(
      "https://us-central1-gatekipa-bbd1c.cloudfunctions.net/revealCardDetails",
      { data: { card_id: "Jy160APohMYHBXFlvWOL" } },
      { headers: { Authorization: `Bearer ${idToken}` } }
    );
    console.log("Success:", fnRes.data);
  } catch (err) {
    console.error("Function Error:", err.response?.data || err.message);
  }
}

run().catch(console.error);
