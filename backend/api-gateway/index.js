import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';
import { createWriteStream } from 'fs';

import { db, initializeFirebase } from './config/firebase.js';
import shipmentRoutes from './routes/shipmentRoutes.js';
import simulatorController from './controllers/simulatorController.js';
import { corsOptions, rateLimiter, securityHeaders } from './utils/security.js';
import { serializeFirestoreData } from './utils/firestoreSerializer.js';
import {
  validateCreateShipment,
  validateLocationUpdate,
  validateShipmentLookup
} from './utils/validation.js';
import { authMiddleware } from './middleware/authMiddleware.js';
import { eventManager } from './services/eventService.js';
import { loadSecrets } from './services/secretService.js';
import mapsService from './services/mapsService.js';
import { processIdempotentRequest } from './utils/idempotency.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();

// --- CENTRALIZED LOGGING UTILITY ---
const logDir = path.join(__dirname, '../../logs');
let gatewayLogStream = null;

try {
  if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });
  gatewayLogStream = createWriteStream(path.join(logDir, 'gateway.log'), { flags: 'a' });
} catch (err) {
  console.log('⚠️ Local log file creation failed (expected in Cloud Run). Streaming to stdout only.');
}

const sysLog = (service, level, message, data = {}) => {
  const timestamp = new Date().toISOString();
  const entry = JSON.stringify({ timestamp, service, level, message, ...data });

  if (gatewayLogStream) {
    gatewayLogStream.write(entry + '\n');
  }

  // Standard output is automatically captured by GCP Cloud Logging
  console.log(entry);
};

// Request Logging Middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    sysLog('GATEWAY', 'INFO', `${req.method} ${req.originalUrl}`, {
      status: res.statusCode,
      duration: `${duration}ms`,
      ip: req.ip
    });
  });
  next();
});

app.use(securityHeaders);
app.use(cors(corsOptions));
app.use(rateLimiter);
app.use(express.json({ limit: '100kb' }));
app.use(express.static(path.join(__dirname, 'public')));

/* --- FRONTEND LOGGING BRIDGE (PROTECTED) --- */
app.post('/api/logs', authMiddleware, (req, res) => {
  const { level, message, data } = req.body;
  sysLog('FRONTEND', level || 'INFO', message, data);
  res.status(204).send();
});


/* -----------------------------------------------------------------------
   NOTE: shipmentRoutes (POST /analyze) is mounted BELOW all inline routes
   to prevent the router from shadowing GET /api/shipments.
   See bottom of file for mount.
----------------------------------------------------------------------- */

/* ---------------- HEALTH ---------------- */
app.get('/health', async (req, res) => {
  try {
    initializeFirebase();

    // Basic Firestore check without writing data.
    await db().collection('test').doc('health-check').get();

    res.json({
      success: true,
      service: 'smart-supply-chain-api',
      timestamp: new Date().toISOString(),
      firebase: 'ok',
      firestore: 'ok'
    });
  } catch (error) {
    console.error('[HEALTH CHECK ERROR]', error.message);
    res.status(500).json({
      success: false,
      service: 'smart-supply-chain-api',
      timestamp: new Date().toISOString(),
      error: error.message
    });
  }
});

/* ---------------- LIST SHIPMENTS (PROTECTED) ---------------- */
app.get('/api/shipments', rateLimiter, authMiddleware, async (req, res) => {
  try {
    const snapshot = await db()
      .collection('shipments')
      .orderBy('created_at', 'desc')
      .limit(20)
      .get();

    const shipments = snapshot.docs.map((doc) => ({
      id: doc.id,
      ...serializeFirestoreData(doc.data())
    }));

    res.json({ success: true, shipments });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/* ---------------- GET LOGISTICS STATS (PROTECTED) ---------------- */
const STATS_SCAN_LIMIT = 500;
let statsCache = null;
let lastStatsFetch = 0;
const STATS_CACHE_TTL = 60 * 1000; // 1 minute

app.get('/api/stats', authMiddleware, async (req, res) => {
  try {
    const now = Date.now();
    if (statsCache && (now - lastStatsFetch < STATS_CACHE_TTL)) {
      return res.json({ success: true, stats: statsCache, source: 'cache' });
    }

    const snapshot = await db()
      .collection('shipments')
      .orderBy('created_at', 'desc')
      .limit(STATS_SCAN_LIMIT)
      .get();

    let total = snapshot.size;
    let highRiskCount = 0;
    let mediumRiskCount = 0;
    let lowRiskCount = 0;
    let totalDelay = 0;
    let analyzedCount = 0;

    snapshot.docs.forEach(doc => {
      const data = doc.data();
      const ai = data.aiResponse || {};

      if (ai.risk_level === 'HIGH') highRiskCount++;
      else if (ai.risk_level === 'MEDIUM') mediumRiskCount++;
      else if (ai.risk_level === 'LOW') lowRiskCount++;

      if (ai.delay_prediction) {
        const mins = parseInt(ai.delay_prediction);
        if (!isNaN(mins)) {
          totalDelay += mins;
          analyzedCount++;
        }
      }
    });

    statsCache = {
      totalShipments: total,
      atRisk: highRiskCount,
      riskDistribution: {
        high: highRiskCount,
        medium: mediumRiskCount,
        low: lowRiskCount
      },
      avgDelay: analyzedCount > 0 ? Math.round(totalDelay / analyzedCount) : 0,
      efficiencyRate: total > 0 ? Math.round(((total - highRiskCount) / total) * 100) : 100,
      scannedCount: total,
      cappedAt: STATS_SCAN_LIMIT,
      note: total >= STATS_SCAN_LIMIT ? "Stats are partial (scan limit reached). Use BigQuery for full analytics." : ""
    };
    lastStatsFetch = now;

    res.json({
      success: true,
      stats: statsCache,
      source: 'live'
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/* ---------------- GET SHIPMENT (PROTECTED) ---------------- */
app.get('/api/shipments/:shipment_id', authMiddleware, async (req, res) => {
  try {
    const validation = validateShipmentLookup(req.params.shipment_id);

    if (!validation.valid) {
      return res.status(400).json({ success: false, errors: validation.errors });
    }

    const { shipment_id } = validation.value;
    const doc = await db().collection('shipments').doc(shipment_id).get();

    if (!doc.exists) {
      return res.status(404).json({ success: false, error: 'Shipment not found' });
    }

    res.json({
      success: true,
      shipment: {
        id: doc.id,
        ...serializeFirestoreData(doc.data())
      }
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

/* ---------------- CREATE SHIPMENT (PROTECTED) ---------------- */
app.post('/create-shipment', authMiddleware, async (req, res) => {
  try {
    const validation = validateCreateShipment(req.body);

    if (!validation.valid) {
      return res.status(400).json({ success: false, errors: validation.errors });
    }

    const { shipment_id, origin, destination } = validation.value;

    // Fetch route data immediately
    let routeData = [];
    try {
      routeData = await mapsService.getRoute(origin, destination);
    } catch (err) {
      console.error(`⚠️ Failed to fetch initial route: ${err.message}`);
      // Continue with empty routeData
    }

    await db().collection('shipments').doc(shipment_id).set({
      shipment_id,
      origin,
      destination,
      vehicle_type: 'TRUCK',
      current_location: null,
      risk: null,
      status: 'CREATED',
      routeData: routeData, // Store route data immediately
      created_at: new Date()
    });

    res.json({ success: true });

  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});


app.post('/update-location', authMiddleware, async (req, res) => {
  try {
    const idempotencyKey = req.headers['x-idempotency-key'];
    if (!idempotencyKey) {
      return res.status(400).json({ error: 'x-idempotency-key header required' });
    }
    const { shipment_id, lat, lng, trigger_ai = true, current_place = "" } = req.body;
    const result = await processIdempotentRequest(idempotencyKey, async () => {
      // 1. Fast path: update location in Firestore instantly
      const shipmentRef = db().collection('shipments').doc(shipment_id);
      await shipmentRef.update({
        current_location: { lat, lng },
        current_place: current_place || "En route",
        status: 'IN_TRANSIT',
        updated_at: new Date()
      });

      // 2. Conditional AI Trigger (Checkpoint Logic)
      // Only trigger heavy AI processing if requested (saves cost)
      if (trigger_ai) {
        await eventManager.publishEvent('shipment.location_updated', { shipment_id, lat, lng });
      } else {
        console.log(`[TELEMETRY] Skipping AI for ${shipment_id} (Intermediate Point)`);
      }

      // 3. Log telemetry to BigQuery
      await eventManager.logToBigQuery(shipment_id, 'LOCATION_UPDATE', { lat, lng });
      return { success: true, message: 'Location updated, AI analysis queued.' };
    });
    // 202 Accepted: The request has been accepted for processing
    res.status(202).json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/* NOTE: /test-db removed — unauthenticated Firestore writes are a security risk.
   Use GET /health for connectivity checks instead. */

/* ---------------- APPLY OPTIMIZED ROUTE (PROTECTED) ---------------- */
// Called by the Flutter "Apply Optimized Route" button.
// Writes status = ROUTE_APPLIED and timestamps the action in Firestore.
app.patch('/api/shipments/:shipment_id/apply-route', authMiddleware, async (req, res) => {
  try {
    const validation = validateShipmentLookup(req.params.shipment_id);
    if (!validation.valid) {
      return res.status(400).json({ success: false, errors: validation.errors });
    }

    const { shipment_id } = validation.value;
    const shipmentRef = db().collection('shipments').doc(shipment_id);
    const doc = await shipmentRef.get();

    if (!doc.exists) {
      return res.status(404).json({ success: false, error: 'Shipment not found' });
    }

    await shipmentRef.update({
      status: 'ROUTE_APPLIED',
      route_applied_at: new Date(),
      updated_at: new Date()
    });

    // Publish event for downstream consumers (e.g. vehicle notification service)
    await eventManager.publishEvent('shipment.route_applied', { shipment_id }).catch((err) => {
      // Don't fail the request if event publish fails — just log it
      console.error('[APPLY-ROUTE] Event publish failed (non-fatal):', err.message);
    });

    sysLog('GATEWAY', 'INFO', `Route applied for ${shipment_id}`);

    res.json({
      success: true,
      message: `Optimized route applied for ${shipment_id}`,
      shipment_id,
      status: 'ROUTE_APPLIED'
    });
  } catch (err) {
    sysLog('GATEWAY', 'ERROR', 'Apply route failed', { error: err.message });
    res.status(500).json({ success: false, error: err.message });
  }
});

/* ---------------- SIMULATOR CONTROLS ---------------- */
app.post('/api/simulator/start', simulatorController.startSimulator);
app.post('/api/simulator/stop', simulatorController.stopSimulator);

const PORT = process.env.PORT || 5000;

// --- BOOTSTRAP: Persistence Guard (Resume active simulations) ---
const bootstrap = async () => {
  try {
    console.log('🔄 [BOOTSTRAP] Checking for interrupted simulations...');
    const snapshot = await db().collection('shipments')
      .where('status', '==', 'IN_TRANSIT')
      .limit(10) // Limit to avoid burst on start
      .get();

    for (const doc of snapshot.docs) {
      const data = doc.data();
      // Only resume if it hasn't been analyzed recently (likely interrupted)
      const lastUpdate = data.last_analyzed_at?.toDate() || new Date(0);
      const diff = Date.now() - lastUpdate.getTime();

      if (diff > 300000) { // 5 minutes of silence
        console.log(`📡 [BOOTSTRAP] Resuming simulation for: ${doc.id}`);
        // We don't have the full original request body, so we use a minimal re-trigger
        // This is a "Best Effort" resume.
        import('./controllers/simulatorController.js').then(m => {
          m.default.startSimulator({ body: { shipment_id: doc.id, steps: 50, interval_ms: 3000 } }, { json: () => { } });
        });
      }
    }
  } catch (err) {
    console.error('❌ [BOOTSTRAP ERROR]:', err.message);
  }
};

// Bootstrap Application: Load Secrets then Start Server
const startApp = async () => {
  try {
    // In production, these names match GCP Secret Manager keys
    await loadSecrets(['FIREBASE_SERVICE_ACCOUNT', 'GOOGLE_MAPS_API_KEY', 'WEATHER_API_KEY', 'NEWS_API_KEY']);

    // Initialize Firebase after secrets are loaded
    try {
      initializeFirebase();
      console.log('✅ Firebase initialized successfully in bootstrap');
    } catch (firebaseError) {
      console.error('❌ Firebase initialization failed:', firebaseError.message);
      throw firebaseError;
    }

    app.listen(PORT, async () => {
      console.log(`🚀 API Gateway running on port ${PORT}`);
      await bootstrap();
    });
  } catch (err) {
    console.error('CRITICAL: Failed to bootstrap application:', err);
    process.exit(1);
  }
};

startApp();

/* Mounted LAST: POST /api/shipments/analyze - keeps inline GET routes unblocked */
app.use('/api/shipments', shipmentRoutes);
