const axios = require("axios");

async function run() {
  try {
    const tokenCmd = require('child_process').execSync('npx -y firebase-tools functions:secrets:access PAYSTACK_SECRET_KEY --project gatekipa-bbd1c').toString().trim();
    const key = tokenCmd.split('\n').pop();
    
    console.log("Testing BVN against Paystack...");
    
    // Using Paystack BVN match endpoint
    const response = await axios.post(
       "https://api.paystack.co/bvn/match",
       {
          bvn: "22279167460",
          account_number: "0000000000",
          bank_code: "058"
       },
       { headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" } }
    );
    console.log("Paystack Match SUCCESS:", JSON.stringify(response.data, null, 2));
  } catch (err) {
    console.error("Paystack Error:", err.response?.status, JSON.stringify(err.response?.data || err.message, null, 2));
  }
}
run();
