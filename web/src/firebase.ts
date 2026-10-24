// Firebase setup. Real projects pass their web config through VITE_FIREBASE_*
// variables (see web/.env.example); without them the site talks to the local
// emulators under the demo project "demo-sohail".
import { initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth } from 'firebase/auth';
import { connectFirestoreEmulator, getFirestore } from 'firebase/firestore';

const env = import.meta.env;

export const usingEmulators = !env.VITE_FIREBASE_PROJECT_ID || env.VITE_USE_EMULATORS === 'true';

const app = initializeApp(
  usingEmulators
    ? { apiKey: 'demo-key', authDomain: 'demo-sohail.firebaseapp.com', projectId: 'demo-sohail' }
    : {
        apiKey: env.VITE_FIREBASE_API_KEY,
        authDomain: env.VITE_FIREBASE_AUTH_DOMAIN,
        projectId: env.VITE_FIREBASE_PROJECT_ID,
        appId: env.VITE_FIREBASE_APP_ID,
      },
);

export const auth = getAuth(app);
export const db = getFirestore(app);

if (usingEmulators) {
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
}
