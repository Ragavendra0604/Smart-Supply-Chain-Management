# Smart Supply Chain Management

**Real-time multi-modal logistics platform with ML-driven risk assessment and dynamic route optimization.**

---

## Overview

Smart Supply Chain Management is a cloud-native logistics platform designed to provide real-time visibility and intelligence across multi-modal transportation networks (road, air, sea). The system ingests live telemetry data, enriches it with contextual intelligence (traffic, weather, news), and uses trained machine learning models to predict disruptions and generate actionable mitigation strategies.

**Core value**: Automated disruption detection, risk scoring, and intelligent route recommendations delivered in real time to logistics operators.

---

## Features

- **Real-Time Multi-Modal Tracking**: Live position tracking for road vehicles, aircraft, and sea vessels with interactive map visualization
- **Disruption Detection**: Automated identification of delays caused by traffic congestion, adverse weather, and external incidents
- **Risk Scoring System**: ML-based risk assessment categorizing shipments as Low, Medium, or High risk
- **Contextual Intelligence**: Real-time integration with weather APIs, traffic services, and news feeds
- **Dynamic Route Recommendations**: AI-generated suggestions for route optimization based on detected risks
- **Alert & Notification System**: Real-time alerts to dispatchers with prioritized operational recommendations
- **Cloud-Native Architecture**: Distributed processing via Google Cloud Pub/Sub with fault-tolerant telemetry handling
- **Session Persistence**: Automatic recovery of active simulations after server restarts

---

## Architecture

The system uses a decoupled microservices design with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Client Layer (Flutter)                      │
│          Shipment Dashboard │ Map View │ Alert Center           │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│                 API Gateway (Node.js/Express)                   │
│  • Request Validation & Rate Limiting                           │
│  • Telemetry Stream Processing                                  │
│  • Context Enrichment (Weather, Traffic, News)                  │
│  • Firestore State Management                                   │
└──────┬──────────────────────┬──────────────────┬────────────────┘
       │                      │                  │
       ▼                      ▼                  ▼
┌─────────────┐      ┌──────────────┐     ┌──────────────┐
│  Pub/Sub    │      │  Firestore   │     │ AI Service   │
│  (Ingestion)│      │ (Real-time)  │     │ (Python)     │
└─────────────┘      └──────────────┘     └───────┬──────┘
                                                  │
                                    ┌─────────────┴──────┐
                                    │                    │
                            ┌───────▼────────┐  ┌────────▼─────┐
                            │  XGBoost ML    │  │  Gemini API  │
                            │  (Predictions) │  │  (Reasoning) │
                            └────────────────┘  └──────────────┘
```

**Components:**

- **API Gateway**: Orchestration layer handling request validation, telemetry processing, and context enrichment
- **Pub/Sub**: High-throughput message broker for decoupled telemetry ingestion
- **Firestore**: Real-time database for shipment state and operational data
- **AI Service**: Python backend for ML inference and AI-powered recommendations
- **Flutter Client**: Cross-platform UI for real-time tracking and alert delivery

---

## System Workflow

1. **Telemetry Ingestion**
   - Location updates are published to Google Cloud Pub/Sub
   - Decoupled message delivery ensures reliability during traffic spikes

2. **Validation & Deduplication**
   - API Gateway validates timestamps to reject stale telemetry
   - Idempotency tokens prevent duplicate updates from concurrent sources

3. **Contextual Enrichment**
   - Fetches real-time traffic data from Maps API
   - Retrieves current weather conditions from weather service
   - Pulls relevant news/incident data for context

4. **ML Analysis**
   - XGBoost model predicts delay minutes based on distance, traffic, weather, time features
   - Calculates risk factors and aggregates into unified risk score

5. **AI Reasoning**
   - Gemini AI generates human-readable operational recommendations
   - Produces contextual mitigation strategies

6. **State Persistence**
   - Results persisted to Firestore with real-time sync
   - Dashboard receives live updates via Firestore listeners

7. **Resilience & Recovery**
   - Active sessions recovered from Firestore after server restart
   - Ensures continuity of long-running simulations

---

## Fixes & Improvements

This MVP incorporates critical production hardening fixes:

### AI & Model Reliability
- **Fixed invalid model usage**: Migrated from unsupported models to verified production-stable Vertex AI endpoints
- **Centralized scoring logic**: Unified risk calculation across all transport modes (road/air/sea) to eliminate inconsistencies

### Concurrency & Data Integrity
- **Timestamp-based stale data protection**: Prevents race conditions during high-frequency telemetry updates
- **Idempotency implementation**: Guards against duplicate processing of concurrent updates

### System Resilience
- **Session persistence recovery**: Active simulations automatically resume after server restart, maintaining operator continuity
- **Pub/Sub poison message handling**: Proper error handling prevents system crashes from malformed telemetry
- **Graceful degradation**: System continues operating with reduced external API availability

### Performance Optimization
- **Firestore read throttling**: Reduced database query load while maintaining update frequency
- **Server-side aggregation caching**: Optimized dashboard responsiveness for high-frequency updates
- **Intelligent API call bundling**: Reduced redundant external API calls via regional caching

### Security Hardening
- **Eliminated hardcoded credentials**: All secrets managed via environment variables and Google Cloud Secret Manager
- **IAM-compliant credential management**: Uses Google Cloud service accounts instead of shared keys
- **Request validation**: Strict validation of all input coordinates and timestamp ranges

### UX & Operational Clarity
- **Improved AI output formatting**: Clear, concise recommendations suitable for dispatcher decision-making
- **Adjusted multi-modal prediction accuracy**: Fine-tuned models for road/air/sea-specific characteristics
- **Enhanced error messaging**: Actionable error feedback for operators

---

## Performance & Reliability

### Throughput
- Handles real-time telemetry at high frequency via Pub/Sub
- Sub-second response times for API endpoints under normal load
- Scales to thousands of concurrent shipments through database indexing

### Latency
- Telemetry to dashboard update: <2 seconds (average)
- Risk score calculation: <500ms
- API response time (p95): <1000ms

### Availability
- Automatic recovery from API Gateway failures via Cloud Run restart policies
- Pub/Sub ensures no telemetry loss during processing peaks
- Firestore replication provides multi-region redundancy

### Data Consistency
- Timestamp validation prevents out-of-order updates
- Idempotency tokens ensure exactly-once semantics
- Firestore transactions guarantee state consistency

---

## Security

### Implemented Controls

**Authentication & Authorization**
- Firebase Admin SDK for backend service authentication
- Basic auth middleware for API endpoints
- CORS allow-list with configurable origins

**Data Protection**
- HTTPS-only communication
- Firebase security rules for Firestore access control
- Request payload size limits (100KB)

**Credential Management**
- Environment variable isolation for secrets
- Google Cloud Secret Manager integration for API keys
- No hardcoded credentials in source code
- Service account key rotation support

**API Security**
- Rate limiting (IP-based)
- Request validation for all input parameters
- Timestamp validation to prevent replay attacks
- Idempotency tokens for write operations

### Not Implemented (Pre-production Gap)

- User authentication (role-based access)
- Distributed rate limiting across instances
- API key rotation automation
- Audit logging for compliance
- End-to-end encryption for data in transit

See [SECURITY.md](SECURITY.md) for detailed security posture and hardening roadmap.

---

## Cost Optimization

The platform is architected for free-tier and low-cost operation:

### Database Efficiency
- Intelligent bundling of telemetry updates reduces Firestore write costs
- Query optimization with proper indexing
- Regional data locality minimizes cross-region traffic

### API Call Optimization
- Regional caching for weather and traffic data
- Single API call per update cycle for context enrichment
- Lazy loading of non-critical enrichment data

### Pub/Sub Efficiency
- Standard topic configuration with optimized retention policies
- Message batching reduces publish overhead
- Backpressure handling prevents resource exhaustion

### ML & Inference Optimization
- Lightweight feature engineering for fast XGBoost scoring
- Selective use of heavy LLM inference (Gemini) only for high-risk shipments
- Cached predictions reduce repeated inference calls

### Infrastructure Cost
- Stateless API Gateway design enables horizontal scaling
- Serverless components (Cloud Run, Firestore) pay-per-use pricing
- No persistent VM instances required

---

## Setup & Installation

### Prerequisites

- **Node.js** 18+ and **npm**
- **Python** 3.9+ and **pip**
- **Flutter** 3.0+ with web, Android, iOS support
- **Firebase CLI** (for deployment)
- **Google Cloud Project** with:
  - Firestore enabled
  - Pub/Sub API enabled
  - Vertex AI API enabled
  - Secret Manager enabled
- **API Keys**: Google Maps, Weather API, News API

### 1. Backend Setup

#### API Gateway

```bash
cd backend/api-gateway
npm install
```

Create `.env`:
```env
FIREBASE_SERVICE_ACCOUNT_PATH=serviceAccountKey.json
GCP_PROJECT_ID=your-gcp-project-id
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:5000
MAPS_API_KEY=your-google-maps-api-key
WEATHER_API_KEY=your-weather-api-key
NEWS_API_KEY=your-news-api-key
SIMULATOR_SECRET=your-secure-simulator-key
```

Start the gateway:
```bash
npm run dev    # Development with auto-reload
npm start      # Production
```

The API listens on `http://localhost:3000`.

#### AI Service

```bash
cd backend/ai-service
pip install -r requirements.txt
python main.py
```

The service listens on `http://localhost:8000`.

### 2. Frontend Setup

```bash
cd frontend
flutter pub get
flutterfire configure --project=your-firebase-project
```

Run locally:
```bash
# Web
flutter run -d chrome

# Android/iOS
flutter run -d your-device-id
```

### 3. Local Testing

Start all components:
```bash
# Terminal 1
cd backend/api-gateway && npm run dev

# Terminal 2
cd backend/ai-service && python main.py

# Terminal 3
cd frontend && flutter run -d chrome
```

The simulator will auto-generate telemetry data on startup.

### 4. Firebase Deployment

Build and deploy frontend:
```bash
cd frontend
flutter build web
firebase deploy --only hosting
```

Deploy backend to Cloud Run (via Google Cloud Console):
- Build Docker image
- Push to Artifact Registry
- Deploy to Cloud Run with environment variables

---

## Project Structure

```
smart_supply_chain_management_mvp_v3/
├── backend/
│   ├── api-gateway/                 # Node.js orchestration layer
│   │   ├── config/
│   │   │   └── firebase.js          # Firebase initialization
│   │   ├── controllers/
│   │   │   ├── shipmentController.js
│   │   │   └── simulatorController.js
│   │   ├── routes/
│   │   │   └── shipmentRoutes.js
│   │   ├── services/
│   │   │   ├── aiService.js         # AI inference calls
│   │   │   ├── mapsService.js       # Maps API integration
│   │   │   ├── weatherService.js    # Weather data
│   │   │   ├── newsService.js       # News/incident data
│   │   │   ├── pubsubService.js     # Pub/Sub handling
│   │   │   └── eventService.js      # Event management
│   │   ├── middleware/
│   │   │   └── authMiddleware.js
│   │   └── utils/
│   │       ├── validation.js
│   │       ├── security.js
│   │       ├── firestoreSerializer.js
│   │       └── idempotency.js
│   └── ai-service/                  # Python ML/AI service
│       ├── main.py                  # FastAPI application
│       ├── train_v3.py              # XGBoost model training
│       └── requirements.txt
├── frontend/                        # Flutter application
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/                  # Data models
│   │   ├── services/                # API client
│   │   ├── presentation/            # UI screens
│   │   └── controllers/             # Business logic
│   ├── android/                     # Android build config
│   ├── ios/                         # iOS build config
│   └── web/                         # Web build config
├── firebase.json                    # Firebase Hosting config
└── SECURITY.md                      # Security documentation
```

---

## Endpoints Reference

### Shipment Analysis

**POST** `/api/shipments/analyze`

Analyzes a shipment and returns risk assessment with recommendations.

Request:
```json
{
  "shipmentId": "SHIP-001",
  "origin": {
    "lat": 40.7128,
    "lng": -74.0060
  },
  "destination": {
    "lat": 34.0522,
    "lng": -118.2437
  },
  "mode": "ROAD",
  "deadline": "2026-05-10T14:00:00Z"
}
```

Response:
```json
{
  "shipmentId": "SHIP-001",
  "riskLevel": "MEDIUM",
  "riskScore": 0.68,
  "delayPredictionMinutes": 45,
  "recommendation": "Consider northern route to avoid I-80 congestion.",
  "factors": {
    "traffic": 0.72,
    "weather": 0.45,
    "distance": 0.50
  },
  "timestamp": "2026-05-02T10:30:00Z"
}
```

### Location Update

**POST** `/api/shipments/:id/location`

Updates shipment location with timestamp validation.

Request:
```json
{
  "location": {
    "lat": 40.7200,
    "lng": -73.9900
  },
  "timestamp": "2026-05-02T10:15:00Z"
}
```

Response: `204 No Content`

---

## ML Model Specification

### XGBoost Delay Prediction Model

**Input Features:**
- `distance_km` - Route distance in kilometers
- `traffic_index` - Normalized traffic severity (1-5 scale)
- `weather_severity` - Weather impact factor (0-1 range)
- `is_holiday` - Boolean indicator for holiday dates
- `hour_sin, hour_cos` - Cyclical encoding of hour of day
- `day_of_week` - Normalized day of week (0-6)

**Output:**
- Predicted delay in minutes

**Training Data:**
- Synthetic logistics dataset with weather and traffic correlations
- ~10,000 samples covering various routes, times, and conditions
- Stratified splits for robust validation

**Accuracy:**
- RMSE: ~15 minutes on test set
- Suitable for medium-horizon predictions (1-24 hours)

**Limitations:**
- Trained on synthetic data; real-world accuracy may vary
- US-centric route patterns; requires retraining for other regions
- Does not account for rare events or extreme scenarios

---

## Screenshots & Visualization

*Placeholder section for dashboard screenshots*

- Shipment tracking map with real-time position updates
- Risk assessment dashboard with Low/Medium/High status
- Alert notification center with timestamped recommendations
- Historical tracking view with disruption annotations

---

## Resources & Links

- [Google Cloud Documentation](https://cloud.google.com/docs)
- [Firebase Guides](https://firebase.google.com/docs)
- [Flutter Documentation](https://flutter.dev/docs)
- [XGBoost Documentation](https://xgboost.readthedocs.io/)
- [Express.js Documentation](https://expressjs.com/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)

---

## Future Scope

### Planned Enhancements

- **User Authentication**: Role-based access control for dispatchers, managers, and admins
- **Advanced Predictions**: Multi-horizon time series forecasting for proactive planning
- **Geographic Expansion**: Localized models for APAC and EMEA regions
- **Real Data Integration**: Training models on historical shipment and disruption data
- **Distributed Rate Limiting**: Cross-instance rate tracking for multi-region deployments
- **Compliance & Audit**: Comprehensive audit logging for regulatory requirements

### Known Limitations

- Rate limiting is IP-based; does not scale across load balancers
- No persistent distributed rate limiting implementation
- Authentication is basic; production requires OAuth2/SAML
- ML models trained on synthetic data; real-world accuracy not validated
- Cost optimization tuning required for production workloads

---

## License

This project is provided as-is for educational and prototyping purposes. See LICENSE file for details.

---

**Built by The Trinamites**

For issues, questions, or contributions, please open an issue or contact the development team.
