const https = require("https");

const words = [
  "messages", "message", "whatsapp", "send", "chat", "broadcast", "campaign", "trigger", "outbound", "conversations"
];

const paths = [];

for (const w of words) {
  paths.push(`/api/v1/${w}`);
  paths.push(`/api/v1/workspaces/123/${w}`);
  paths.push(`/api/v1/workspaces/123/${w}/send`);
  paths.push(`/api/v1/channels/123/${w}`);
  paths.push(`/api/v1/channels/123/${w}/send`);
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
