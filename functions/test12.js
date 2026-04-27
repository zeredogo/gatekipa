const axios = require("axios");
const AES256 = require("aes-everywhere");

(async () => {
  try {
    const token = "at_live_d09dc71e7d180753b794a64c5c294befd0a1af065d12b82824b747cbc4156adf3afac84d012ca68e3d5bf171528197ce200e7a415f7bc2c1505f65b8d571b466d1bb4a629a7e84aa78b2ea804d7b834ab81627836474885ed3ba0724349b4690eb12d9ddfd91b40afe6208c0ef09bddd03aaf2a8879520d31a0d83609718f22ba1d2e5a58c9d8825bf6a4c4a2a5343b4f986305ad099024535e96364471614b500feec1cc82b7c01e3bb456db3493c23b63313bd56422ad1ebc8ceac6a85fd1ee83a17a9ee62407330426017e89393311b75c172e72f49f83a0cb16f73d30cddfdfa0a5317c943956b8c26b330b055a1fcb39e469e2d54b05f0ce2db573c6ff2";
    const secret = "sk_live_VTJGc2RHVmtYMThvbU9VVkhxMVRCaktiS0RPK2dTSE12MTBZQUN1ZTdZdzM1QTZWQWRseTlPeUt4Uzk4dWhLNkIwNkloL0Q0ZE5iNktVM0kyTzUxZmpkeSt4TEMzV3FxQmVPWjBkT29sUS9VUk1KK0FTbUhWZmNFbnRMUzJQVUJ4aWpZejhTbTBqd1JlRUlKZzBLWlZaanBTKzg5bUV3QXk3dWdPSERaempMRENxaTBMRXlZbWhmcFM2SmxWMXlPZjd5dit2S1V6eWFuY3ZLM0t4ZUJZcnhYclBLNmRsdWVqL3NEZG9MSms1bDdOcEFCd0pCOHhCWEFLelNYL01LZW9Hc1VJWTJwVmg2UkNjTEkyVnpGQzZ4S016U3NWbDBzdGM3VG9vSklWTm5HQ1VIRDZTL1cxRXZXbjVXQkQzeERoM21nQkNTOEUzc1Z5cC9XU1lReVNIUWVqTU1LbStoNHJhUmxTdGtWajNZN3prelNrc0VKTDQzZUZIM2Y1SkNEWDV3UXdscGdWVXI1TlMxelloU3o5N2h6S2hmaTA2UFMrcWwvRnNpbGVrNE5kTDk0Sk1tL3NiTzJvYWlPRWMwdERIRFVOckdFcmd2SjFvejdMbmxGbzZnVlMrWDA0aFVWYlFSYTlLVGFmMjQ9";

    const client = axios.create({
      baseURL: "https://issuecards.api.bridgecard.co/v1/issuing",
      headers: {
        "Content-Type": "application/json",
        "token": `Bearer ${secret}` // Using secret key as bearer token!
      }
    });

    const encryptedPin = AES256.encrypt("1234", secret);

    const payload = {
      cardholder_id: "5d83c6278c43414b99c48fe266aa744f",
      card_type: "virtual",
      card_currency: "NGN",
      card_brand: "Mastercard",
      pin: encryptedPin
    };

    console.log("Sending payload using Secret as Token:", payload);
    const res = await client.post("/cards/create_card", payload);
    console.log("Success:", JSON.stringify(res.data, null, 2));
  } catch (err) {
    console.error("Error Status:", err.response?.status);
    console.error("Error Data:", JSON.stringify(err.response?.data, null, 2));
  }
})();
