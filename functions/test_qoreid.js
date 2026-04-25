require("dotenv").config();
const axios = require("axios");

async function run() {
  try {
    const tokenCmd = require('child_process').execSync('npx -y firebase-tools functions:secrets:access QOREID_API_KEY --project gatekipa-bbd1c').toString().trim();
    const token = tokenCmd.split('\n').pop();
    
    console.log("Testing QoreID with BVN...");
    
    // Try POST to BVN match endpoint
    const response = await axios.post(
       "https://api.qoreid.com/v1/ng/identities/bvn-match",
       { bvn: "22279167460", firstname: "Test", lastname: "Test" },
       { headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" } }
    );
    console.log("POST /bvn-match SUCCESS:", JSON.stringify(response.data, null, 2));
  } catch (err) {
    console.error("POST /bvn-match Error:", err.response?.status, err.response?.data || err.message);
  }

  try {
    const tokenCmd = require('child_process').execSync('npx -y firebase-tools functions:secrets:access QOREID_API_KEY --project gatekipa-bbd1c').toString().trim();
    const token = tokenCmd.split('\n').pop();

    // Try GET basic BVN endpoint
    const response = await axios.get(
       "https://api.qoreid.com/v1/ng/identities/bvn/22279167460",
       { headers: { Authorization: `Bearer ${token}` } }
    );
    console.log("GET /bvn SUCCESS:", JSON.stringify(response.data, null, 2));
  } catch (err) {
    console.error("GET /bvn Error:", err.response?.status, err.response?.data || err.message);
  }
}
run();
