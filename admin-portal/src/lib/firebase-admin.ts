import * as admin from 'firebase-admin';
import path from 'path';

export function getAdminDb() {
  if (!admin.apps.length) {
    try {
      // Try to load from environment variable first (Vercel)
      if (process.env.FIREBASE_SERVICE_ACCOUNT_KEY) {
        // Handle escaped newlines properly (Vercel formatting issue fix)
        const rawKey = process.env.FIREBASE_SERVICE_ACCOUNT_KEY.replace(/\\n/g, '\n');
        let serviceAccount;
        try {
          serviceAccount = JSON.parse(rawKey);
        } catch (e) {
          throw new Error('Failed to parse FIREBASE_SERVICE_ACCOUNT_KEY JSON string.');
        }
        
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount)
        });
      } else {
        // Fallback to local file for dev
        const fs = require('fs');
        const keyPath = path.join(process.cwd(), 'gatekipa.json');
        const serviceAccount = JSON.parse(fs.readFileSync(keyPath, 'utf-8'));
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount)
        });
      }
    } catch (error) {
      console.error('Firebase admin initialization error', error);
    }
  }
  return admin.firestore();
}
