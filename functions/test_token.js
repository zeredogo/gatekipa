const axios = require("axios");

async function run() {
  const clientId = "5FOUNWX9NPVKSFBV5V76";
  const secret = "4664d0782d264463ab78deffd6f7970c";
  
  try {
    const res = await axios.post("https://api.qoreid.com/token", {
      clientId: clientId,
      secret: secret
    }, { headers: { "Content-Type": "application/json" } });
    console.log("Token response:", res.data);
    
    const token = res.data.accessToken;
    
    // Now let's try the BVN match endpoint with the token
    const bvnRes = await axios.post(
       "https://api.qoreid.com/v1/ng/identities/bvn-match",
       { bvn: "22279167460", firstname: "Test", lastname: "Test" },
       { headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" } }
    );
    console.log("BVN Match:", bvnRes.data);
  } catch (err) {
    console.log("Error:", err.response?.data || err.message);
  }
}
run();
