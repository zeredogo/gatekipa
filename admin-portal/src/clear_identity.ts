import { db } from "./lib/firebaseAdmin";
import * as admin from "firebase-admin";

async function run() {
  const snapshot = await db.collection('users').where('safehaven_identity_id', '!=', null).get();
  let count = 0;
  for (const doc of snapshot.docs) {
    if (!doc.data().safehaven_dva_account_number) {
      await doc.ref.update({
        safehaven_identity_id: admin.firestore.FieldValue.delete(),
        kycStatus: admin.firestore.FieldValue.delete()
      });
      console.log('Cleared stuck identity for:', doc.id);
      count++;
    }
  }
  console.log('Cleared', count, 'users.');
}
run().catch(console.error);
