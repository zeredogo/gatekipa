const https = require("https");

const words = ["send", "message", "messages", "whatsapp", "wa", "v1", "api", "broadcast", "sms", "chat", "outbound", "webhook"];

const paths = [];
for (let i=0; i<words.length; i++) {
  paths.push(`/${words[i]}`);
  for (let j=0; j<words.length; j++) {
    paths.push(`/${words[i]}/${words[j]}`);
    for (let k=0; k<words.length; k++) {
      paths.push(`/${words[i]}/${words[j]}/${words[k]}`);
    }
  }
}

// Add known variations explicitly to be safe
paths.push("/api/v1/messages/send");
paths.push("/v1/messages/send");
paths.push("/api/messages/send");
paths.push("/api/whatsapp/send");
paths.push("/api/v1/whatsapp/send");
paths.push("/whatsapp/v1/send");

async function check() {
  for (let i=0; i<paths.length; i++) {
    const p = paths[i];
    await new Promise(resolve => {
      const req = https.request({
        hostname: "api.tabi.africa",
        port: 443,
        path: p,
        method: "POST",
        headers: { "Authorization": "Bearer tk_46b84cc8f648d0fd1bbe84f2f283ea2287d75bb55c7565971307cbb52580452f" }
      }, res => {
        if (res.statusCode !== 404) {
          console.log(`FOUND: ${p} -> ${res.statusCode}`);
        }
        resolve();
      });
      req.on("error", () => resolve());
      req.end();
    });
  }
  console.log("Done");
}

check();
