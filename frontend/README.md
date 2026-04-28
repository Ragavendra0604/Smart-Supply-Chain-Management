# Logistics Risk Monitor Flutter Frontend

One-screen Flutter dashboard for the Smart Supply Chain MVP.

## What It Shows

- Google Map full screen
- Live moving vehicle marker
- Route polyline
- Current location pin
- Shipment ID and current corridor
- Color-coded risk level
- Delay prediction
- AI explanation and suggestion
- Live tracking indicator with last update time
- Before vs After ETA card

## Data Flow

```text
Backend -> Firebase Firestore -> Flutter dashboard
```

The app prefers a direct Firestore stream for `shipments/SHP001`. If Firebase client config is not filled yet, it falls back to polling the backend endpoint:

```text
GET http://localhost:5000/api/shipments/SHP001
```

## Required Configuration

### Firebase

Edit:

```text
lib/firebase_options.dart
```

Firebase streaming is disabled by default for safe local demos. Enable it at runtime:

```bash
flutter run -d chrome --dart-define=ENABLE_FIREBASE=true --dart-define=API_BASE_URL=http://localhost:5000
```

### Google Maps

Android:

Replace `REPLACE_WITH_GOOGLE_MAPS_API_KEY` in:

```text
android/gradle.properties
```

Web:

Replace `REPLACE_WITH_GOOGLE_MAPS_API_KEY` in:

```text
web/index.html
```

## Run

Start backend services first:

```bash
cd ../backend/ai-service
venv\Scripts\python -m uvicorn main:app --host 127.0.0.1 --port 8000
```

```bash
cd ../api-gateway
npm start
```

Run Flutter:

```bash
cd ../../frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5000
```

For Android emulator:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```
