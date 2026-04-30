import admin from 'firebase-admin';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

dotenv.config();

const __dirname = path.dirname(fileURLToPath(import.meta.url));

if (!admin.apps.length) {
  try {
    let credential;

    // First, try to use the service account from environment (Secret Manager)
    if (process.env.FIREBASE_SERVICE_ACCOUNT) {
      const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
      credential = admin.credential.cert(serviceAccount);
      console.log('✅ Firebase initialized with Service Account from Secret Manager');
    } else {
      // Fallback: Local development with serviceAccountKey.json
      const keyPath = path.resolve(__dirname, '../serviceAccountKey.json');
      if (fs.existsSync(keyPath)) {
        const serviceAccount = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
        credential = admin.credential.cert(serviceAccount);
        console.log('✅ Firebase initialized with Service Account Key');
      } else {
        // Last resort: Application Default Credentials
        credential = admin.credential.applicationDefault();
        console.log('✅ Firebase initialized with Application Default Credentials');
      }
    }

    admin.initializeApp({ credential });
  } catch (error) {
    console.error('❌ Firebase init error:', error.message);
    // Don't exit process, let it try to continue or fail gracefully later
  }
}

export const db = admin.firestore();
export const auth = admin.auth();
