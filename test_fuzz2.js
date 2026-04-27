const https = require("https");
const paths = [
  "/api/v1/messages",
  "/v1/messages",
  "/api/v1/send",
  "/v1/send",
  "/api/v1/whatsapp/send",
  "/whatsapp/send",
  "/api/messages"
];
const methods = ["GET", "POST", "OPTIONS"];

async function check() {
  for (const m of methods) {
    for (const p of paths) {
      await new Promise(resolve => {
        const req = https.request({
          hostname: "api.tabi.africa",
          port: 443,
          path: p,
          method: m,
          headers: { "Authorization": "Bearer tk_46b84cc8f648d0fd1bbe84f2f283ea2287d75bb55c7565971307cbb52580452f" }
        }, res => {
          if (res.statusCode !== 404 && res.statusCode !== 405) {
            console.log(`FOUND: ${m} ${p} -> ${res.statusCode}`);
          }
          resolve();
        });
        req.on("error", () => resolve());
        req.end();
      });
    }
  }
  console.log("Done");
}
check();
