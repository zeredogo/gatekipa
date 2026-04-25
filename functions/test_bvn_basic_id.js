const axios = require("axios");

async function run() {
  const clientId = "5FOUNWX9NPVKSFBV5V76";
  const secret = "4664d0782d264463ab78deffd6f7970c";
  
  try {
    const res = await axios.post("https://api.qoreid.com/token", {
      clientId: clientId,
      secret: secret
    }, { headers: { "Content-Type": "application/json" } });
    
    const token = res.data.accessToken;
    
    // Try POST /bvn-basic/{idNumber}
    try {
      const bvnRes = await axios.post(
         "https://api.qoreid.com/v1/ng/identities/bvn-basic/22279167460",
         { firstname: "Test", lastname: "Test" },
         { headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" } }
      );
      console.log("POST /bvn-basic/:id Match:", JSON.stringify(bvnRes.data, null, 2));
    } catch (e) {
      console.log("POST /bvn-basic/:id Error:", JSON.stringify(e.response?.data || e.message, null, 2));
    }

  } catch (err) {
    console.log("Error:", err.response?.data || err.message);
  }
}
run();
