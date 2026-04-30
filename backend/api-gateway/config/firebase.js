import admin from 'firebase-admin';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

dotenv.config();

const __dirname = path.dirname(fileURLToPath(import.meta.url));

if (!admin.apps.length) {
  try {
    // Production (Cloud Run): Uses Application Default Credentials (ADC)
    // Local: Uses serviceAccountKey.json if present
    const keyPath = path.resolve(__dirname, '../serviceAccountKey.json');

    if (fs.existsSync(keyPath)) {
      const serviceAccount = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
      console.log('✅ Firebase initialized with Service Account Key');
    } else {
      admin.initializeApp();
      console.log('✅ Firebase initialized with Application Default Credentials');
    }
  } catch (error) {
    console.error('❌ Firebase init error:', error.message);
    // Don't exit process, let it try to continue or fail gracefully later
  }
}

export const db = admin.firestore();
export const auth = admin.auth();
