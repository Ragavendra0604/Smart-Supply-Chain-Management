# Security Notes For Prototype Submission

This project is an MVP/prototype. It includes basic security controls suitable for a demo, but it is not production-hardened yet.

## Implemented

- `.env` and `serviceAccountKey.json` are ignored by Git.
- Backend request payload size is limited.
- Backend has CORS allow-list support through `ALLOWED_ORIGINS`.
- Backend includes basic security headers.
- Backend includes simple IP-based rate limiting.
- Shipment IDs and coordinates are validated before writes.
- Firebase Admin SDK key path can be configured with `FIREBASE_SERVICE_ACCOUNT_PATH`.
- Secret Manager integration for critical API keys and credentials.
- Idempotency support for telemetry updates.
- Flutter Firebase client config is disabled by default and can be enabled with `--dart-define=ENABLE_FIREBASE=true`.

## Before Public Submission

- Do not upload `backend/api-gateway/.env`.
- Do not upload `backend/api-gateway/serviceAccountKey.json`.
- If zipping manually, check the zip contents before sharing.
- Restrict Google Maps API keys in Google Cloud Console by app/package/domain.
- Restrict Firebase API keys in Google Cloud Console by app/package/domain.
- Use Firestore rules that allow only the minimum reads needed for the demo.

## Suggested Demo Firestore Rules

For a public prototype demo, prefer read-only dashboard access:

```js
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    match /shipments/{shipmentId} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

The backend should remain the only writer because it uses Firebase Admin SDK.

## Production Gaps

- No user authentication yet.
- No role-based authorization yet.
- No persistent distributed rate limiter yet.
- No audit logging yet.
- Secret manager integration implemented.
- No HTTPS deployment config yet.
