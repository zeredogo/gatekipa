const https = require("https");

const words = ["send", "message", "messages", "whatsapp", "wa", "v1", "api", "broadcast", "campaign", "conversations"];

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

// Known base path
paths.push("/api/v1/webhook");
paths.push("/api/v1/workspaces");

// also just try `/messages` etc without `/api/v1`
paths.push("/v1/messages");
paths.push("/messages");

async function check() {
  for (let i=0; i<paths.length; i++) {
    const p = paths[i];
    await new Promise(resolve => {
      const req = https.request({
        hostname: "api.tabi.africa",
        port: 443,
        path: p,
        method: "POST",
        headers: { "Content-Type": "application/json" }
      }, res => {
        if (res.statusCode !== 404) {
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
