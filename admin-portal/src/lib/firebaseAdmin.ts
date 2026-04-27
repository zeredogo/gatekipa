import * as admin from 'firebase-admin';
import path from 'path';

if (!admin.apps.length) {
  try {
    // 1. Try Vercel Environment Variables first
    if (process.env.FIREBASE_PROJECT_ID && process.env.FIREBASE_PRIVATE_KEY && process.env.FIREBASE_CLIENT_EMAIL) {
      // Absolute Bulletproof PEM Reconstruction
      let rawKey = process.env.FIREBASE_PRIVATE_KEY || '';
      
      // Strip everything except the base64 payload
      rawKey = rawKey.replace(/"/g, '');
      rawKey = rawKey.replace(/-----BEGIN PRIVATE KEY-----/g, '');
      rawKey = rawKey.replace(/-----END PRIVATE KEY-----/g, '');
      rawKey = rawKey.replace(/\\n/g, '');
      rawKey = rawKey.replace(/\n/g, '');
      rawKey = rawKey.replace(/\s+/g, '');
      
      // Reconstruct the PEM perfectly (64 chars per line)
      const matched = rawKey.match(/.{1,64}/g);
      const privateKey = matched 
        ? `-----BEGIN PRIVATE KEY-----\n${matched.join('\n')}\n-----END PRIVATE KEY-----\n`
        : process.env.FIREBASE_PRIVATE_KEY; // Fallback if regex fails
      
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: process.env.FIREBASE_PROJECT_ID,
          clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
          privateKey: privateKey,
        }),
      });
    } 
    // 2. Local fallback if credentials are provided via Vercel env var or a local json file, but Vercel env vars failed
    // NOTE: For local development, ensure Gatekipa.json exists.
    else {
      // In a strict production environment, we should never reach here unless Vercel vars are missing
      // We will try loading local config. If it fails, the catch block will run.
      const localKeyPath = path.join(process.cwd(), 'gatekipa.json');
      admin.initializeApp({
        credential: admin.credential.cert(localKeyPath),
      });
    }
  } catch (error) {
    console.error('Firebase Admin initialization error:', error);
    // 3. Fallback for Next.js Build Step (Prevents crashes when env vars are missing during CI)
    console.warn("Firebase Admin: Initializing with mock config to prevent build crash.");
    admin.initializeApp({
      projectId: "gatekipa-build-mock",
    });
  }
}

export const db = admin.firestore();
export const auth = admin.auth();
