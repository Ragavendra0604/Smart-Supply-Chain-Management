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
import shipmentController from './controllers/shipmentController.js';
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
import { cacheManager } from './utils/cache.js';
import { calculateDistance } from './utils/location.js';

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

// Request Logging Middleware with Trace ID
app.use((req, res, next) => {
  const traceId = req.headers['x-trace-id'] || `tr-${Date.now()}-${Math.random().toString(36).substr(2, 5)}`;
  req.traceId = traceId;
  res.setHeader('x-trace-id', traceId);

  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    sysLog('GATEWAY', 'INFO', `${req.method} ${req.originalUrl}`, {
      status: res.statusCode,
      duration: `${duration}ms`,
      ip: req.ip,
      traceId
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

    const { shipment_id, origin, destination, mode, priority } = validation.value;

    // 1. PERSISTENCE LAYER: Initialize skeleton record with mode and priority
    await db().collection('shipments').doc(shipment_id).set({
      shipment_id,
      origin,
      destination,
      vehicle_type: mode,
      current_location: null,
      status: 'CREATED',
      priority: priority,
      cargo_type: 'General',
      fuel_level: 100,
      vehicle_health: 'GOOD',
      created_at: new Date(),
      updated_at: new Date()
    });

    // 2. INTELLIGENT INITIALIZATION PIPELINE (Synchronous for UX, parallel for speed)
    let analysisResult = null;
    try {
      analysisResult = await shipmentController.performAnalysis(shipment_id, req.traceId);
      
      // If the sync call returned a fallback (success: false), trigger async repair
      if (analysisResult && !analysisResult.success) {
        console.warn(`[PIPELINE] Sync analysis for ${shipment_id} returned fallback. Triggering async repair...`);
        shipmentController.runAsyncAnalysis(shipment_id, req.traceId);
      }
    } catch (analysisErr) {
      console.error(`⚠️ Synchronous analysis failed for ${shipment_id}: ${analysisErr.message}`);
      // Emergency fallback: trigger async analysis if sync throws
      shipmentController.runAsyncAnalysis(shipment_id, req.traceId);
    }

    res.json({ 
      success: true, 
      shipment_id,
      analysis: analysisResult 
    });

  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});



// --- TELEMETRY THROTTLING CONFIG ---
// --- MVP COST-SLAYER CONFIG (₹0 Target) ---
const TELEMETRY_MIN_DIST = 5000; // 5km (Was 1km)
const TELEMETRY_MAX_TIME = 900000; // 15 mins (Was 2 mins)

app.post('/update-location', authMiddleware, async (req, res) => {
  try {
    const idempotencyKey = req.headers['x-idempotency-key'];
    if (!idempotencyKey) {
      return res.status(400).json({ error: 'x-idempotency-key header required' });
    }

    const { shipment_id, lat, lng, speed_kmh = 0, current_step_index = 0, trigger_ai = false, current_place = "" } = req.body;

    // --- 1. GLOBAL STOP CIRCUIT BREAKER ---
    let isGlobalStopped = cacheManager.get('sys:global_stop');
    if (isGlobalStopped === null) {
      const sysDoc = await db().collection('system').doc('config').get();
      isGlobalStopped = sysDoc.exists ? sysDoc.data().isGlobalStopped : false;
      cacheManager.set('sys:global_stop', isGlobalStopped, 60000);
    }

    if (isGlobalStopped) {
      return res.status(403).json({ success: false, error: 'System Global Stop active.' });
    }

    // --- 2. INDIVIDUAL SHIPMENT STOP GUARD ---
    const shipmentStopKey = `stop:${shipment_id}`;
    let isShipmentStopped = cacheManager.get(shipmentStopKey);
    
    if (isShipmentStopped === null) {
      // Cold cache safety: Verify against Firestore
      const doc = await db().collection('shipments').doc(shipment_id).get();
      isShipmentStopped = doc.exists && doc.data().status === 'STOPPED';
      if (isShipmentStopped) {
        cacheManager.set(shipmentStopKey, true, 3600000);
      }
    }

    if (isShipmentStopped) {
      // Gracefully handle late-arriving telemetry after a stop command to avoid UI errors
      return res.status(200).json({ 
        success: true, 
        message: `Shipment ${shipment_id} is already STOPPED. Update ignored.`,
        is_stopped: true 
      });
    }

    // --- 3. SMART THROTTLING & SHARDING LOGIC ---
    const cacheKey = `last_telemetry:${shipment_id}`;
    const lastTelemetry = cacheManager.get(cacheKey);
    const now = Date.now();

    // SRE Best Practice: Stream ALL raw telemetry to BigQuery (Low cost, high scalability)
    // We do this BEFORE the Firestore throttle to ensure we never lose data.
    eventManager.logToBigQuery(shipment_id, 'TELEMETRY_RAW', { 
      lat, lng, speed_kmh, traceId: req.traceId 
    }).catch(() => {});

    let shouldUpdateFirestore = true;
    if (lastTelemetry) {
      const dist = calculateDistance(lat, lng, lastTelemetry.lat, lastTelemetry.lng);
      const timeElapsed = now - lastTelemetry.timestamp;
      
      // PRODUCTION THROTTLE: Only update Firestore if > 2km moved OR > 5 mins elapsed OR AI trigger requested
      if (dist < 2000 && timeElapsed < 300000 && !trigger_ai) {
        shouldUpdateFirestore = false;
      }
    }

    const result = await processIdempotentRequest(idempotencyKey, async () => {
      if (shouldUpdateFirestore) {
        // SHARDING: Partition shipments across sub-collections if volume is extreme
        const shardId = shipment_id.split('').reduce((acc, char) => acc + char.charCodeAt(0), 0) % 10;
        
        const shipmentRef = db().collection('shipments').doc(shipment_id);
        await shipmentRef.update({
          current_location: { lat, lng },
          speed_kmh,
          current_step_index,
          current_place: current_place || "En route",
          status: 'IN_TRANSIT',
          shard_id: shardId,
          updated_at: new Date()
        });
        
        cacheManager.set(cacheKey, { lat, lng, timestamp: now }, 600000);
      }

      if (trigger_ai) {
        await eventManager.publishEvent('shipment.location_updated', { 
          shipment_id, lat, lng, traceId: req.traceId 
        });
      }

      return { 
        success: true, 
        message: shouldUpdateFirestore ? 'State Persisted.' : 'Logged to Analytics (Buffered in Firestore).'
      };
    });

    res.status(202).json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/* NOTE: /test-db removed — unauthenticated Firestore writes are a security risk.
   Use GET /health for connectivity checks instead. */

/* ---------------- SHIPMENT & SIMULATION ---------------- */
// Aliases for legacy/external tools
app.post('/apply-route', authMiddleware, shipmentController.applyRoute);
app.post('/simulate-scenario', authMiddleware, shipmentController.simulateShipment);

// Standard Frontend Routes (ApiService.dart)
app.post('/api/shipments/simulate', authMiddleware, shipmentController.simulateShipment);
app.post('/inject-simulation', authMiddleware, shipmentController.injectSimulation);
app.patch('/api/shipments/:shipment_id/apply-route', authMiddleware, shipmentController.applyRoute);

/* ---------------- SIMULATOR CONTROLS ---------------- */
app.post('/api/simulator/start', simulatorController.startSimulator);
app.post('/api/simulator/stop', simulatorController.stopSimulator);

/* ---------------- SYSTEM CONTROLS ---------------- */
import systemController from './controllers/systemController.js';
app.get('/api/system/status', systemController.getSystemStatus);
app.post('/api/system/toggle-stop', authMiddleware, systemController.toggleGlobalStop);

const PORT = process.env.PORT || 5000;

// --- BOOTSTRAP: Persistence Guard (Stateless - No resume needed) ---
const bootstrap = async () => {
  console.log('🔄 [BOOTSTRAP] System ready. Background loops disabled for cost optimization.');
};


// Bootstrap Application: Load Secrets then Start Server
const startApp = async () => {
  try {
    // In production, these names match GCP Secret Manager keys
    await loadSecrets(['FIREBASE_SERVICE_ACCOUNT', 'GOOGLE_MAPS_API_KEY', 'WEATHER_API_KEY', 'NEWS_API_KEY', 'SIMULATOR_SECRET']);

    // Initialize Firebase after secrets are loaded
    try {
      initializeFirebase();
      console.log('✅ Firebase initialized successfully in bootstrap');
    } catch (firebaseError) {
      console.error('❌ Firebase initialization failed:', firebaseError.message);
      throw firebaseError;
    }

    /* Mounted here (before listen): POST /api/shipments/analyze
       Must be registered before server starts to avoid missing routes on cold start.
       Inline GET /api/shipments route above takes priority because it's defined first. */
    app.use('/api/shipments', shipmentRoutes);

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
