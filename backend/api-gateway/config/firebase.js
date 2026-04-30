import admin from 'firebase-admin';
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

dotenv.config();

const __dirname = path.dirname(fileURLToPath(import.meta.url));

let firebaseInitialized = false;
let firebaseApp = null;

const createFirebaseCredential = () => {
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    console.log('✅ Firebase credential loaded from FIREBASE_SERVICE_ACCOUNT');
    return admin.credential.cert(serviceAccount);
  }

  const keyPath = path.resolve(__dirname, '../serviceAccountKey.json');
  if (fs.existsSync(keyPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(keyPath, 'utf8'));
    console.log('✅ Firebase credential loaded from local serviceAccountKey.json');
    return admin.credential.cert(serviceAccount);
  }

  console.log('✅ No local service account found, using Application Default Credentials');
  return admin.credential.applicationDefault();
};

export const initializeFirebase = () => {
  if (firebaseInitialized) {
    return firebaseApp;
  }

  try {
    const credential = createFirebaseCredential();
    firebaseApp = admin.initializeApp({ credential });
    firebaseInitialized = true;
    console.log('✅ Firebase initialized successfully');
  } catch (error) {
    console.error('❌ Firebase init error:', error.message);
    throw error;
  }

  return firebaseApp;
};

export const db = () => {
  if (!firebaseInitialized) {
    initializeFirebase();
  }
  return admin.firestore();
};

export const auth = () => {
  if (!firebaseInitialized) {
    initializeFirebase();
  }
  return admin.auth();
};
