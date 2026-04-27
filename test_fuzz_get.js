const https = require("https");

const words = ["send", "message", "messages", "whatsapp", "wa", "v1", "api", "broadcast", "campaign", "conversations", "outbound"];

const paths = [];
for (let i=0; i<words.length; i++) {
  paths.push(`/api/v1/${words[i]}`);
  for (let j=0; j<words.length; j++) {
    paths.push(`/api/v1/${words[i]}/${words[j]}`);
    for (let k=0; k<words.length; k++) {
      paths.push(`/api/v1/${words[i]}/${words[j]}/${words[k]}`);
    }
  }
}

paths.push("/api/v1/webhook");
paths.push("/api/v1/workspaces");
paths.push("/api/v1/channels");
paths.push("/api/v1/campaigns");

async function check() {
  for (let i=0; i<paths.length; i++) {
    const p = paths[i];
    await new Promise(resolve => {
      const req = https.request({
        hostname: "api.tabi.africa",
        port: 443,
        path: p,
        method: "GET", // Use GET this time to find routes
        headers: { "Authorization": "Bearer tk_46b84cc8f648d0fd1bbe84f2f283ea2287d75bb55c7565971307cbb52580452f" }
      }, res => {
        if (res.statusCode !== 404 && res.statusCode !== 405) {
          console.log(`FOUND GET ${p} -> ${res.statusCode}`);
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
