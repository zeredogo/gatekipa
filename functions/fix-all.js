const admin = require("firebase-admin");

// Ensure you export GOOGLE_APPLICATION_CREDENTIALS before running this
try {
    admin.initializeApp();
} catch (e) {
    console.error("Failed to initialize Firebase Admin. Set GOOGLE_APPLICATION_CREDENTIALS.");
    process.exit(1);
}

const db = admin.firestore();

// Known Gatekeeper collections
const COLLECTIONS_TO_FIX = [
    "users",
    "cards",
    "wallets",
    "transactions",
    "accounts",
    "rules",
    "notifications"
];

async function fixSchemaHazards() {
    console.log("\n🛠️  ================== REPAIRING SCHEMA PROPERTIES (UNDEFINED FIELDS) ==================");
    
    let totalFixed = 0;

    for (const collectionName of COLLECTIONS_TO_FIX) {
        try {
            const snapshot = await db.collection(collectionName).get();
            if (snapshot.empty) {
                console.log(`  ➖ ${collectionName}: Collection is currently empty. Safe.`);
                continue;
            }

            const batch = db.batch();
            let updatesInCollection = 0;

            snapshot.forEach(doc => {
                const data = doc.data();
                const updates = {};
                
                // Backfill timestamps if missing entirely (checking both camelCase and snake_case patterns used in Flutter)
                const hasCreatedAt = (data.createdAt !== undefined || data.created_at !== undefined);
                if (!hasCreatedAt) {
                     updates.createdAt = admin.firestore.FieldValue.serverTimestamp();
                     updates.created_at = admin.firestore.FieldValue.serverTimestamp(); 
                }

                const hasUpdatedAt = (data.updatedAt !== undefined || data.updated_at !== undefined);
                if (!hasUpdatedAt) {
                     updates.updatedAt = admin.firestore.FieldValue.serverTimestamp();
                     updates.updated_at = admin.firestore.FieldValue.serverTimestamp();
                }

                // Delete any explicitly undefined fields as they trigger "Unsupported field value: undefined" errors 
                // in Firebase backends when trying to cursor map
                for (const [key, value] of Object.entries(data)) {
                     if (value === undefined) {
                         updates[key] = admin.firestore.FieldValue.delete();
                     }
                }

                if (Object.keys(updates).length > 0) {
                     batch.update(doc.ref, updates);
                     updatesInCollection++;
                     totalFixed++;
                }
            });

            if (updatesInCollection > 0) {
                 await batch.commit();
                 console.log(`  ✅ ${collectionName}: Backfilled missing timestamps and purged undefined fields on ${updatesInCollection} documents.`);
            } else {
                 console.log(`  ✅ ${collectionName}: All ${snapshot.size} documents are cleanly structured. No repairs needed.`);
            }

        } catch (e) {
            console.log(`  ⚠️ Error fixing ${collectionName}: ${e.message}`);
        }
    }
    
    console.log(`\n🎉 Total Repairs Processed: ${totalFixed} documents fixed globally.`);
    console.log("Pagination cursors will no longer crash going forward.");
}

async function main() {
    console.log("Starting Gatekeeper Universal Fix Script...");
    await fixSchemaHazards();
    process.exit(0);
}

main();
