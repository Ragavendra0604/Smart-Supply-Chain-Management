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
  console.log('🔑 Creating Firebase credential...');
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    try {
      let saContent = process.env.FIREBASE_SERVICE_ACCOUNT;
      // Try to detect if it's base64 encoded
      if (saContent.trim().startsWith('eyJ') || !saContent.trim().startsWith('{')) {
        try {
          saContent = Buffer.from(saContent, 'base64').toString('utf8');
        } catch (e) {
          // If decoding fails, stick with original and let JSON.parse fail
        }
      }
      const serviceAccount = JSON.parse(saContent);
      console.log('✅ Firebase credential loaded from FIREBASE_SERVICE_ACCOUNT');
      return admin.credential.cert(serviceAccount);
    } catch (error) {
      console.error('❌ Failed to parse FIREBASE_SERVICE_ACCOUNT JSON:', error.message);
      throw error;
    }
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

  console.log('🔥 Initializing Firebase...');
  try {
    const credential = createFirebaseCredential();
    console.log('✅ Firebase credential created');
    
    const projectId = process.env.GOOGLE_CLOUD_PROJECT || 'ssm-sb';
    console.log(`🎯 Initializing Firebase for project: ${projectId}`);
    
    firebaseApp = admin.initializeApp({ 
      credential,
      projectId: projectId
    });
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
