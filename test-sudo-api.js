require("dotenv").config();
const axios = require("axios");

async function test() {
  try {
    const res = await axios.post("https://api.sandbox.sudo.cards/cards", {
      customerId: "6a039e08585c2812e5916464",
      type: "virtual",
      currency: "USD",
      brand: "Mastercard",
      issuer: "Sudo",
      status: "active",
      spendingControls: {
        spendLimit: [{ amount: 50, interval: "allTime" }]
      },
      cardProgramId: "SUDO-WSL-WD-1780053923757"
    }, {
      headers: { Authorization: `Bearer ${process.env.SUDO_API_KEY}` }
    });
    console.log(res.data);
  } catch(e) {
    console.error(e.response ? JSON.stringify(e.response.data, null, 2) : e.message);
  }
}
test();
