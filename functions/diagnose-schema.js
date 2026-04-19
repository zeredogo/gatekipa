const admin = require("firebase-admin");

// Initialize with default credentials, expecting GOOGLE_APPLICATION_CREDENTIALS or Firebase CLI auth
try {
    admin.initializeApp();
} catch (e) {
    console.error("Failed to initialize Firebase Admin. Please ensure you are authenticated or have set GOOGLE_APPLICATION_CREDENTIALS.");
    process.exit(1);
}

const db = admin.firestore();

// Known Gatekeeper collections
const COLLECTIONS_TO_CHECK = [
    "users",
    "cards",
    "wallets",
    "transactions",
    "accounts",
    "rules",
    "notifications"
];

// Complex queries typical for Gatekeeper that would require composite indexes
const COMPLEX_QUERIES = {
    cards: [
        { field: "userId", op: "==", value: "test-user", order: "createdAt", dir: "desc" },
        { field: "status", op: "==", value: "active", order: "cardType", dir: "asc" }
    ],
    transactions: [
        { field: "userId", op: "==", value: "test-user", order: "timestamp", dir: "desc" },
        { field: "status", op: "==", value: "pending", order: "createdAt", dir: "desc" }
    ],
    notifications: [
        { field: "userId", op: "==", value: "test-user", order: "createdAt", dir: "desc" },
        { field: "read", op: "==", value: false, order: "createdAt", dir: "desc" }
    ],
    rules: [
        { field: "cardId", op: "==", value: "test-card", order: "createdAt", dir: "desc" }
    ]
};

async function checkMissingIndexes() {
    console.log("\n🔍 ================== CHECKING MISSING COMPOSITE INDEXES ==================");
    let missingIndexes = [];

    for (const [collection, queries] of Object.entries(COMPLEX_QUERIES)) {
        for (const q of queries) {
            try {
                await db.collection(collection)
                    .where(q.field, q.op, q.value)
                    .orderBy(q.order, q.dir)
                    .limit(1)
                    .get();
                console.log(`  ✅ Index exists/not strictly required: ${collection} -> [${q.field} ${q.op} ${q.value}, orderBy ${q.order} ${q.dir}]`);
            } catch (error) {
                if (error.message && error.message.includes("FAILED_PRECONDITION")) {
                    console.log(`  ❌ MISSING INDEX: ${collection} -> [${q.field} ${q.op} ${q.value}, orderBy ${q.order} ${q.dir}]`);
                    
                    const urlMatch = error.message.match(/https:\/\/console\.firebase\.google\.com[^\s]+/);
                    if (urlMatch) {
                        missingIndexes.push(`Collection: ${collection}\nQuery: where(${q.field} ${q.op} ${q.value}).orderBy(${q.order} ${q.dir})\nCreate URL -> ${urlMatch[0]}`);
                    }
                } else if (error.message && error.message.includes("undefined")) {
                     console.log(`  ⚠️ Schema Warning in query ${collection}: OrderBy field is undefined in some documents (${error.message})`);
                } else {
                     console.log(`  ⚠️ Issue querying ${collection}:`, error.message);
                }
            }
        }
    }

    if (missingIndexes.length > 0) {
        console.log("\n🚨 ACTION REQUIRED: Click the following links to create the composite indexes:");
        missingIndexes.forEach(mi => console.log(`\n${mi}`));
    } else {
        console.log("\n✅ Gatekeeper currently passes index checks for tested queries.");
    }
}

async function checkSchemaProperties() {
    console.log("\n🔍 ================== CHECKING SCHEMA PROPERTIES (UNDEFINED FIELDS) ==================");
    
    for (const collectionName of COLLECTIONS_TO_CHECK) {
        try {
            const snapshot = await db.collection(collectionName).limit(30).get();
            if (snapshot.empty) {
                console.log(`  ➖ ${collectionName}: Collection is currently empty or doesn't exist yet.`);
                continue;
            }

            let missingCreatedAt = 0;
            let missingUpdatedAt = 0;
            let explicitlyUndefined = 0;

            snapshot.forEach(doc => {
                const data = doc.data();
                if (data.createdAt === undefined) missingCreatedAt++;
                if (data.updatedAt === undefined) missingUpdatedAt++;
                
                for (const [key, value] of Object.entries(data)) {
                     if (value === undefined) {
                         explicitlyUndefined++;
                     }
                }
            });

            console.log(`  📊 ${collectionName} (Checked ${snapshot.size} docs):`);
            if (missingCreatedAt > 0 || missingUpdatedAt > 0) {
                console.log(`     ❌ Missing 'createdAt': ${missingCreatedAt} | Missing 'updatedAt': ${missingUpdatedAt}`);
            } else {
                console.log(`     ✅ All docs have timestamp fields safely populated.`);
            }

            if (explicitlyUndefined > 0) {
                console.log(`     ⚠️ Found ${explicitlyUndefined} fields explicitly stored as 'undefined' (can cause cursor crashes).`);
            }
        } catch (e) {
            console.log(`  ⚠️ Error reading ${collectionName}: ${e.message}`);
        }
    }
}

async function main() {
    console.log("Starting Gatekeeper Schema & Index Diagnostic...");
    await checkSchemaProperties();
    await checkMissingIndexes();
    process.exit(0);
}

main();
