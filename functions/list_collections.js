const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");

process.env.GOOGLE_APPLICATION_CREDENTIALS = "gatekipa.json";

try {
  initializeApp();
} catch (e) {}

const db = getFirestore();

async function listCollections() {
  const collections = await db.listCollections();
  for (let collection of collections) {
    console.log(`- ${collection.id}`);
  }
}

listCollections();
