require("dotenv").config();
const axios = require("axios");

async function run() {
  try {
    const bridgecardBaseUrl = process.env.BRIDGECARD_BASE_URL || "https://issuecards.api.bridgecard.co/v1/issuing/live";
    const tokenCmd = require('child_process').execSync('npx -y firebase-tools functions:secrets:access BRIDGECARD_ACCESS_TOKEN --project gatekipa-bbd1c').toString().trim();
    const token = tokenCmd.split('\n').pop();
    
    console.log("Testing BVN with Bridgecard...");
    const payload = {
       cardholder_type: "individual",
       first_name: "John",
       last_name: "Doe",
       email_address: "john.doe.test@gatekipa.com",
       identity: {
           id_type: "NIGERIAN_BVN_VERIFICATION",
           id_no: "22279167460",
           id_image: "https://via.placeholder.com/150",
           selfie_image: "https://via.placeholder.com/150"
       },
       phone_number: "08012345678",
       address: {
           address: "123 Test St",
           city: "Lagos",
           state: "Lagos",
           postal_code: "100001",
           house_no: "123"
       }
    };
    
    const response = await axios.post(
       `${bridgecardBaseUrl}/cardholder/register_cardholder_synchronously`,
       payload,
       { headers: { token: `Bearer ${token}` } }
    );
    console.log(JSON.stringify(response.data, null, 2));
  } catch (err) {
    console.error("Bridgecard error:", err.response?.data || err.message);
  }
}
run();
