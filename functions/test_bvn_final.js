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
    
    // We send an empty firstname/lastname to see what QoreID returns by default, or just any name
    // since we don't know the exact name of the BVN holder
    const bvnRes = await axios.post(
       "https://api.qoreid.com/v1/ng/identities/bvn-basic/22279167460",
       { firstname: "Test", lastname: "User" },
       { headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" } }
    );
    console.log(JSON.stringify(bvnRes.data, null, 2));
  } catch (err) {
    console.log("Error:", JSON.stringify(err.response?.data || err.message, null, 2));
  }
}
run();
