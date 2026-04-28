import admin from 'firebase-admin';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

dotenv.config();

const __dirname = path.dirname(fileURLToPath(import.meta.url));

if (!admin.apps.length) {
  try {
    const configuredKeyPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
    const keyPath = configuredKeyPath
      ? path.resolve(configuredKeyPath)
      : path.resolve(__dirname, '../serviceAccountKey.json');

    if (fs.existsSync(keyPath)) {
      const serviceAccount = JSON.parse(fs.readFileSync(keyPath, 'utf8'));

      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });

      console.log('Firebase initialized with service account');
    } else {
      console.log('Using default credentials');
      admin.initializeApp();
    }
  } catch (error) {
    console.error('Firebase init error:', error.message);
    process.exit(1);
  }
}

export const db = admin.firestore();
export const auth = admin.auth();
