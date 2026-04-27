const admin = require("firebase-admin");
const axios = require("axios");
const AES256 = require("aes-everywhere");

// In this script we use the TEST token and TEST secret so we can create a cardholder and a card without actually incurring live charges.
const token = "at_test_f7a8b4e72332ef4f1a21e428c9f041d40a02b1f868dc3b91316b2cf72528148b11c97a8e2cc950c4bc758368ce442c676770f443555513d8d641c8f1e94b83fb8b04a9d7008ee1cb5a0cbbf4ee9108a4f00bcf48d42d3856e40d04c4b574decc5eecde9d17d52671d1efd1e9e2b19f4d1e2e77cc82d3ca66970bc8ebbf2f5bde6b14620f4c3de48e10c7ef03b90558b3f46f39d2ec05b38f8cfd98d287bb2e33f388901eb20c85c2c77f0a6d4ee2679dc6eab08c5c369528f89ab57c2bb20d6ab60cf200d740cb2539611bdce6da3db551c6b12a64c4832c3f87570de4772152";
const secret = "sk_test_VTJGc2RHVmtYMThvbU9VVkhxMVRCaktiS0RPK2dTSE12MTBZQUN1ZTdZdzM1QTZWQWRseTlPeUt4Uzk4dWhLNkIwNkloL0Q0ZE5iNktVM0kyTzUxZmpkeSt4TEMzV3FxQmVPWjBkT29sUS9VUk1KK0FTbUhWZmNFbnRMUzJQVUJ4aWpZejhTbTBqd1JlRUlKZzBLWlZaanBTKzg5bUV3QXk3dWdPSERaempMRENxaTBMRXlZbWhmcFM2SmxWMXlPZjd5dit2S1V6eWFuY3ZLM0t4ZUJZcnhYclBLNmRsdWVqL3NEZG9MSms1bDdOcEFCd0pCOHhCWEFLelNYL01LZW9Hc1VJWTJwVmg2UkNjTEkyVnpGQzZ4S016U3NWbDBzdGM3VG9vSklWTm5HQ1VIRDZTL1cxRXZXbjVXQkQzeERoM21nQkNTOEUzc1Z5cC9XU1lReVNIUWVqTU1LbStoNHJhUmxTdGtWajNZN3prelNrc0VKTDQzZUZIM2Y1SkNEWDV3UXdscGdWVXI1TlMxelloU3o5N2h6S2hmaTA2UFMrcWwvRnNpbGVrNE5kTDk0Sk1tL3NiTzJvYWlPRWMwdERIRFVOckdFcmd2SjFvejdMbmxGbzZnVlMrWDA0aFVWYlFSYTlLVGFmMjQ9";

const client = axios.create({
  baseURL: "https://issuecards.api.bridgecard.co/v1/issuing",
  headers: {
    "Content-Type": "application/json",
    "token": `Bearer ${token}`
  }
});

(async () => {
  try {
    const crypto = require("crypto");
    const uniqueExt = crypto.randomBytes(4).toString("hex");

    console.log("Registering test cardholder...");
    const regPayload = {
      first_name: "Test",
      last_name: "User",
      address: {
        address: "123 Test Street",
        city: "Lagos",
        state: "Lagos",
        country: "Nigeria",
        zip_code: "100001"
      },
      identity: {
        id_type: "NIN",
        id_image: "https://example.com/id.jpg",
        bvn: "22222222222",
        id_no: "22222222222"
      },
      phone_code: "234",
      phone: "800000" + uniqueExt,
      email_address: `testuser${uniqueExt}@example.com`
    };

    const regRes = await client.post("/cardholder/register_cardholder_synchronously", regPayload);
    const cardholder_id = regRes.data.data.cardholder_id;
    console.log("Cardholder created:", cardholder_id);

    console.log("Creating card...");
    const encryptedPin = AES256.encrypt("1234", secret);
    console.log("Encrypted pin:", encryptedPin);

    const payload = {
      cardholder_id: cardholder_id,
      card_type: "virtual",
      card_brand: "Mastercard",
      card_currency: "NGN",
      pin: encryptedPin,
      meta_data: { test: "gatekipa" }
    };
    
    const res = await client.post("/cards/create_card", payload);
    console.log("Success NGN:", res.data);
  } catch (err) {
    if (err.response) {
       console.error("Error Response Status:", err.response.status);
       console.error("Error Response Data:", JSON.stringify(err.response.data, null, 2));
    } else {
       console.error("Error:", err.message);
    }
  }
})();
