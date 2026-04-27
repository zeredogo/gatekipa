const API_KEY = "tk_46b84cc8f648d0fd1bbe84f2f283ea2287d75bb55c7565971307cbb52580452f";

async function testWhatsApp() {
  const recipient = process.argv[2];
  
  if (!recipient) {
    console.error("Please provide a test phone number as an argument (e.g., node test_whatsapp.js +2348012345678)");
    process.exit(1);
  }

  const message = "Hello from Gatekipa! This is a test WhatsApp message to verify the Tabi integration.";
  
  const endpoints = [
    "https://api.tabi.africa/v1/messages/send",
    "https://api.tabi.africa/api/v1/messages/send",
    "https://api.tabi.africa/v1/messages",
    "https://api.tabi.africa/api/v1/messages",
    "https://api.tabi.africa/v1/send",
    "https://api.tabi.africa/api/v1/send",
  const url = `https://api.tabi.africa/api/v1/channels/${CHANNEL_ID}/send`;

  console.log(`\nTesting POST ${url}...`);
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { 
        "Authorization": `Bearer ${API_KEY}`, 
        "Content-Type": "application/json" 
      },
      body: JSON.stringify({ 
        recipient: recipient, 
        type: "text",
        message: { text: message } 
      })
    });
    
    let data;
    const text = await response.text();
    try {
      data = text ? JSON.parse(text) : {};
    } catch (e) {
      console.error("Error:", e.message);
    }
  }
}

testWhatsApp();
