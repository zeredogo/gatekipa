const admin = require("firebase-admin");

admin.initializeApp();

const setAdmin = async (email) => {
  try {
    const user = await admin.auth().getUserByEmail(email);
    await admin.auth().setCustomUserClaims(user.uid, { admin: true });
    console.log(`Successfully granted admin privileges to: ${email}`);
    process.exit(0);
  } catch (error) {
    console.error("Error configuring admin claim:", error);
    process.exit(1);
  }
};

const targetEmail = process.argv[2];
if (!targetEmail) {
  console.log("Usage: node setAdmin.js <email>");
  process.exit(1);
}

setAdmin(targetEmail);
