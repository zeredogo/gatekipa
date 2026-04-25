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
    
    const wRes = await fetch(
      "https://api.qoreid.com/v1/workflows",
      {
        method: "POST",
        headers: {
          Authorization: "Bearer " + token,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
           workflowCode: "IDENTITY_VERIFICATION",
           clientId: "test_uid",
           applicantData: {
              country: "Nigeria",
              state: "Lagos",
              documentUrl: null,
              selfieUrl: "https://via.placeholder.com/150",
              idNumber: "22279167460"
           }
        })
      }
    );
    const data = await wRes.json();
    console.log("Workflows Status:", wRes.status, "Data:", JSON.stringify(data, null, 2));

  } catch (err) {
    console.log("Error:", err.message);
  }
}
run();
