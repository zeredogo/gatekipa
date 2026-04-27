const https = require("https");

const words = [
  "send", "messages", "message", "whatsapp", "wa", "v1", "api", "broadcasts", "campaigns", "conversations", "outbound", "chat", "chats", "trigger"
];

const paths = [];
for (let i=0; i<words.length; i++) {
  paths.push(`/api/v1/${words[i]}`);
  for (let j=0; j<words.length; j++) {
    paths.push(`/api/v1/${words[i]}/${words[j]}`);
    paths.push(`/api/v1/${words[i]}/${words[j]}/send`);
  }
}

async function check() {
  for (let i=0; i<paths.length; i++) {
    const p = paths[i];
    await new Promise(resolve => {
      const req = https.request({
        hostname: "api.tabi.africa",
        port: 443,
        path: p,
        method: "POST", 
        headers: { 
          "Authorization": "Bearer tk_46b84cc8f648d0fd1bbe84f2f283ea2287d75bb55c7565971307cbb52580452f",
          "Content-Type": "application/json"
        }
      }, res => {
        if (res.statusCode !== 404 && res.statusCode !== 405) {
          console.log(`FOUND POST ${p} -> ${res.statusCode}`);
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
