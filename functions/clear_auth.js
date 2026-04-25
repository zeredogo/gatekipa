const admin = require("firebase-admin");
const serviceAccount = require("./gatekipa.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function deleteAllUsers() {
  let nextPageToken;
  let totalDeleted = 0;

  try {
    do {
      const listUsersResult = await admin.auth().listUsers(1000, nextPageToken);
      const uids = listUsersResult.users.map((userRecord) => userRecord.uid);
      
      if (uids.length > 0) {
        await admin.auth().deleteUsers(uids);
        totalDeleted += uids.length;
        console.log(`Deleted ${uids.length} users...`);
      }
      
      nextPageToken = listUsersResult.pageToken;
    } while (nextPageToken);

    console.log(`Successfully deleted ${totalDeleted} users.`);
  } catch (error) {
    console.error("Error deleting users:", error);
  }
}

deleteAllUsers();
