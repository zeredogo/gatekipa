const axios = require("axios");
const crypto = require("crypto");

(async () => {
  try {
    const token = "at_live_d09dc71e7d180753b794a64c5c294befd0a1af065d12b82824b747cbc4156adf3afac84d012ca68e3d5bf171528197ce200e7a415f7bc2c1505f65b8d571b466d1bb4a629a7e84aa78b2ea804d7b834ab81627836474885ed3ba0724349b4690eb12d9ddfd91b40afe6208c0ef09bddd03aaf2a8879520d31a0d83609718f22ba1d2e5a58c9d8825bf6a4c4a2a5343b4f986305ad099024535e96364471614b500feec1cc82b7c01e3bb456db3493c23b63313bd56422ad1ebc8ceac6a85fd1ee83a17a9ee62407330426017e89393311b75c172e72f49f83a0cb16f73d30cddfdfa0a5317c943956b8c26b330b055a1fcb39e469e2d54b05f0ce2db573c6ff2";
    
    const client = axios.create({
      baseURL: "https://issuecards.api.bridgecard.co/v1/issuing",
      headers: {
        "Content-Type": "application/json",
        "token": `Bearer ${token}`
      }
    });

    const uniqueExt = crypto.randomBytes(4).toString("hex");
    const payload = {
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
        id_type: "BVN",
        bvn: "22222222222",
        id_no: "22222222222"
      },
      phone_code: "234",
      phone: "800000" + uniqueExt,
      email_address: `testuser${uniqueExt}@example.com`
    };

    const res = await client.post("/cardholder/register_cardholder_synchronously", payload);
    console.log("Registered Cardholder:", res.data);
  } catch (err) {
    console.error("Error Registering:", err.response?.data || err.message);
  }
})();
