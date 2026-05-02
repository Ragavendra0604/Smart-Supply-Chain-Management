# Smart Supply Chain: AI-Powered Resilient Logistics System

> **Real-time disruption detection meets intelligent route optimization. Transform your supply chain from reactive to proactive.**

[![Google Solution Challenge 2026](https://img.shields.io/badge/Google%20Solution%20Challenge-2026%20India-4285F4?style=for-the-badge)](https://buildwithgoogle.com/intl/en_in/buildwithgoogle)
[![GitHub](https://img.shields.io/badge/GitHub-Repository-181717?style=for-the-badge&logo=github)](https://github.com/Ragavendra0604/Smart-Supply-Chain-Management)
[![Live Demo](https://img.shields.io/badge/Demo-Live%20MVP-00C853?style=for-the-badge&logo=firebase)](https://ssm-sb.firebaseapp.com/)
[![Team](https://img.shields.io/badge/Team-The%20Trinamites-FF6F00?style=for-the-badge)](#team)

![Status](https://img.shields.io/badge/Status-MVP-FF9800?style=for-the-badge)
![AI](https://img.shields.io/badge/AI-Powered-4CAF50?style=for-the-badge)
![Cloud](https://img.shields.io/badge/Cloud-GCP-4285F4?style=for-the-badge&logo=googlecloud)
![Architecture](https://img.shields.io/badge/Architecture-Microservices-607D8B?style=for-the-badge)
![System](https://img.shields.io/badge/System-Real--Time-D32F2F?style=for-the-badge)

---

## 🚀 Google Solution Challenge 2026 India

**Submission Category**: Smart Supply Chains — Resilient Logistics and Dynamic Supply Chain Optimization

This project is designed and built for the **Google Solution Challenge 2026 India** — an initiative to empower developers to use Google technologies to solve real-world problems.

**Our Vision**: Smart Supply Chain leverages Google's ecosystem — Firebase (auth, database, hosting), Google Cloud Platform (AI/ML, real-time streaming), Google Maps Platform, and Gemini AI — to transform logistics from reactive crisis management to proactive intelligence. By detecting disruptions before they cascade, we create measurable impact: reducing delays by 40-60%, cutting costs, and enabling sustainable logistics operations.

---

## 🌍 Problem Statement

Modern global supply chains operate across complex, multi-modal transportation networks (road, air, sea) with increasingly volatile conditions:

- **Current Reality**: Supply chains are reactive—they respond to disruptions *after* they occur
- **The Cost**: A single transportation disruption leads to:
  - Cascading delays across the supply chain
  - Increased operational costs (fuel surcharges, expedited shipping)
  - Lost customer trust and SLA violations
  - Inefficient resource allocation

**Existing systems lack:**
- Real-time visibility across multiple transport modes
- Predictive capability to anticipate disruptions
- Automated decision-making for route optimization
- Integrated intelligence from multiple data sources

---

## 💡 Solution Overview

**Smart Supply Chain** is an AI-powered platform that transforms logistics from reactive firefighting to proactive intelligence:

### Core Capabilities:

- ✅ **Real-Time Data Fusion**: Continuously ingests traffic, weather, and transport status across multiple modes
- ✅ **Disruption Prediction**: AI models detect congestion, delays, and adverse conditions *before* they impact shipments
- ✅ **Dynamic Route Optimization**: Generates alternate routes automatically based on real-time risk scores
- ✅ **Tactical "What-if" Simulator**: High-fidelity simulation engine allowing operators to test scenarios (weather, traffic, speed) using the v3 XGBoost AI model.
- ✅ **Multi-Modal Integration**: Single platform handles road, air, and sea logistics seamlessly
- ✅ **Cloud-Native Architecture**: Scalable, serverless deployment on Google Cloud

**Impact**: Reduce logistics delays by 40-60%, optimize fuel consumption, improve on-time delivery rates, and enable data-driven decision-making.

---

## 🚀 Key Differentiators (USP)

| Aspect | Competitors | Smart Supply Chain |
|--------|------------|-------------------|
| **Detection Model** | Reactive (after disruption) | Proactive (predictive) |
| **Transport Modes** | Single-mode silos | Integrated multi-modal |
| **Decision Making** | Manual routing | AI-driven automation |
| **Real-Time Processing** | Batch/delayed | Streaming analytics |
| **Scalability** | On-premise infrastructure | Cloud-native serverless |
| **Integration** | Rigid APIs | Modular, composable services |

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    USER LAYER (Frontend)                    │
│  Flutter Mobile App | Web Dashboard | Alert UI              │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│              API GATEWAY (Node.js Express)                  │
│  ┌─ Auth Middleware  ┌─ Rate Limiting  ┌─ Request Routing   │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│         MICROSERVICES LAYER (Backend)                       │
│  ┌─────────────────┐  ┌─────────────────────┐  ┌───────────┐│
│  │ Shipment        │  │ Route               │  │ Analytics ││
│  │ Management      │  │ Optimization AI     │  │ Service   ││
│  │ Service         │  │ (Python, TensorFlow)│  │           ││
│  └─────────────────┘  └─────────────────────┘  └───────────┘│
│  ┌─────────────────┐  ┌───────────────────┐                 │
│  │ Alert Engine    │  │ Data Processing   │                 │
│  │ (Real-time)     │  │ (Stream Analysis) │                 │
│  └─────────────────┘  └───────────────────┘                 │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│         EXTERNAL DATA SOURCES                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Google Maps  │  │ Weather API  │  │ Traffic Data │       │
│  │ API          │  │ (OpenWeather)│  │ (HERE Maps)  │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
│  ┌──────────────┐  ┌──────────────┐                         │
│  │ News API     │  │ Port/Airport │                         │
│  │ (Disruptions)│  │ Data         │                         │
│  └──────────────┘  └──────────────┘                         │
└─────────────────────────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│         DATA & STORAGE LAYER                                │
│  ┌─────────────────────┐  ┌──────────────────────┐          │
│  │ Firestore (NoSQL DB)│  │ Cloud Pub/Sub        │          │
│  │ - Shipments         │  │ (Real-time streaming)│          │
│  │ - Routes            │  │                      │          │
│  │ - History           │  │                      │          │
│  │ └───────────────────┘  └──────────────────────┘          │
│  ┌─────────────────────┐  ┌──────────────────────┐          │
│  │ Cloud Storage       │  │ Firebase Functions   │          │
│  │ (Logs, Reports)     │  │ (Serverless compute) │          │
│  │ └───────────────────┘  └──────────────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow Pipeline:

```
External APIs → Ingestion Service → Cloud Pub/Sub → Stream Processor
                                                            ↓
                                        AI Prediction Engine (Python)
                                                            ↓
                                        Risk Scoring & Decision Engine
                                                            ↓
                                    Firestore (Real-time DB Updates)
                                                            ↓
                                Frontend (Live Dashboard) + Push Alerts
```

---

## ⚙️ Tech Stack

### Frontend Layer
- **Mobile & Web**: Flutter (Dart)
  - Cross-platform: Android, Web
  - Real-time map integration (Google Maps)
  - Responsive dashboard UI
- **State Management**: Provider
- **Authentication**: Firebase Auth

### Backend & API Gateway
- **API Server**: Node.js (Express.js)
- **Language**: JavaScript
- **Core Services**:
  - Shipment Management Controller
  - Route Optimization Service
  - Tactical Simulation Engine
  - Alert & Notification Engine

### AI & Machine Learning
- **Language**: Python 3.9+
- **Framework**: XGBoost / Scikit-learn / TensorFlow
- **Models**:
  - Route optimization
  - Disruption prediction
- **Natural Language**: Google Gemini AI (Insight generation)

### Cloud & DevOps
- **Platform**: Google Cloud Platform (GCP)
  - Cloud Run (serverless containers)
  - Firestore (NoSQL database)
  - Cloud Pub/Sub (real-time messaging)
  - Cloud Storage (logs, historical data)
- **Containerization**: Docker
- **CI/CD**: GitHub Actions

---

## 🔧 Google Technologies Integration

- **Firestore**: Real-time NoSQL database
- **Cloud Run**: Serverless container deployment
- **Cloud Pub/Sub**: Event-driven architecture
- **Firebase Authentication**: Secure user identity
- **Google Maps Platform**: Interactive route visualization
- **Gemini AI**: Logistics insight generation and disruption analysis

---

## 🧠 Key Features

1. **Real-Time Route Tracking**: Live GPS tracking with map-based visualization.
2. **Disruption Detection**: Real-time traffic, weather, and news monitoring.
3. **Tactical "What-if" Simulator**: Real-time scenario testing with AI predictions.
4. **Smart Route Optimization**: Dynamic rerouting based on risk and cost.
5. **Multi-Modal Support**: Road, Air, and Sea logistics integration.
6. **Global Stop Mechanism**: System-wide emergency shutdown for cost management.

---

## 🚀 Getting Started

### Prerequisites
- **Node.js** 16+
- **Python** 3.9+
- **Flutter** 3.0+
- **Google Cloud SDK**

### Installation
1. Clone the repository.
2. Setup Backend: `cd backend/api-gateway && npm install`.
3. Setup AI Service: `cd backend/ai-service && pip install -r requirements.txt`.
4. Setup Frontend: `cd frontend && flutter pub get`.

---

## 📡 API Endpoints

### Base URL
- **Production**: `https://api-gateway-1026695506439.us-central1.run.app/api`

### Core Endpoints
- `GET /api/shipments`: Fetch all active shipments.
- `POST /api/shipments/analyze`: Trigger AI analysis.
- `POST /api/shipments/simulate`: Run a "What-if" tactical simulation.
- `POST /api/simulator/start`: Start a movement simulation.
- `POST /api/system/toggle-stop`: Toggle global emergency stop.

---
