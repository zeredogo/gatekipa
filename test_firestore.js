const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');

const app = initializeApp({
  projectId: 'gatekipa-bbd1c'
});

const db = getFirestore();
const auth = getAuth();

async function run() {
  try {
    // We can't use admin SDK because Admin SDK bypasses rules!
    // We have to use the REST API to test rules, or just trust the rule evaluator.
    console.log("Admin SDK bypasses rules. Can't test easily here.");
  } catch(e) {
    console.error(e);
  }
}
run();
