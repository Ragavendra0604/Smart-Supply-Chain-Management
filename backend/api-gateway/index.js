import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import path from 'path';
import { fileURLToPath } from 'url';

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

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
app.use(securityHeaders);
app.use(rateLimiter);
app.use(cors(corsOptions));
app.use(express.json({ limit: '100kb' }));
app.use(express.static(path.join(__dirname, 'public')));


/* -----------------------------------------------------------------------
   NOTE: shipmentRoutes (POST /analyze) is mounted BELOW all inline routes
   to prevent the router from shadowing GET /api/shipments.
   See bottom of file for mount.
----------------------------------------------------------------------- */

/* ---------------- HEALTH ---------------- */
app.get('/health', (req, res) => {
  res.json({
    success: true,
    service: 'smart-supply-chain-api',
    timestamp: new Date().toISOString()
  });
});

/* ---------------- LIST SHIPMENTS (PROTECTED) ---------------- */
app.get('/api/shipments', authMiddleware, async (req, res) => {
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
app.get('/api/stats', authMiddleware, async (req, res) => {
  try {
    const snapshot = await db().collection('shipments').get();

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

    res.json({
      success: true,
      stats: {
        totalShipments: total,
        atRisk: highRiskCount,
        riskDistribution: {
          high: highRiskCount,
          medium: mediumRiskCount,
          low: lowRiskCount
        },
        avgDelay: analyzedCount > 0 ? Math.round(totalDelay / analyzedCount) : 0,
        efficiencyRate: analyzedCount > 0 ? Math.round(((total - highRiskCount) / total) * 100) : 100
      }
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

    await db().collection('shipments').doc(shipment_id).set({
      shipment_id,
      origin,
      destination,
      vehicle_type: 'TRUCK',
      current_location: null,
      risk: null,
      status: 'CREATED',
      created_at: new Date()
    });

    res.json({ success: true });

  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/* ---------------- UPDATE LOCATION (PROTECTED) ---------------- */
app.post('/update-location', authMiddleware, async (req, res) => {
  try {
    const validation = validateLocationUpdate(req.body);

    if (!validation.valid) {
      return res.status(400).json({ success: false, errors: validation.errors });
    }

    const { shipment_id, lat, lng } = validation.value;
    const shipmentRef = db().collection('shipments').doc(shipment_id);
    const doc = await shipmentRef.get();

    if (!doc.exists) {
      return res.status(404).json({ success: false, error: 'Shipment not found' });
    }

    await shipmentRef.update({
      current_location: { lat, lng },
      status: 'IN_TRANSIT',
      updated_at: new Date()
    });

    // Fire-and-forget: Trigger AI analysis asynchronously via Event Pipeline
    eventManager.emitLocationUpdate(shipment_id, { lat, lng });

    res.json({ success: true });

  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/* ---------------- TEST FIRESTORE ---------------- */
app.get('/test-db', async (req, res) => {
  try {
    await db().collection('test').doc('demo').set({ working: true });
    res.send('Firestore working');
  } catch (err) {
    res.status(500).send(err.message);
  }
});

/* ---------------- SIMULATOR CONTROLS ---------------- */
app.post('/api/simulator/start', simulatorController.startSimulator);
app.post('/api/simulator/stop', simulatorController.stopSimulator);

const PORT = process.env.PORT || 5000;

// Bootstrap Application: Load Secrets then Start Server
const bootstrap = async () => {
  try {
    // In production, these names match GCP Secret Manager keys
    await loadSecrets(['FIREBASE_SERVICE_ACCOUNT', 'MAPS_API_KEY', 'OPENWEATHER_API_KEY']);
    initializeFirebase();

    app.listen(PORT, '0.0.0.0', () => {
      console.log(`🚀 Production Gateway running on port ${PORT}`);
    });
  } catch (err) {
    console.error('CRITICAL: Failed to bootstrap application:', err);
    process.exit(1);
  }
};

bootstrap();

/* Mounted LAST: POST /api/shipments/analyze - keeps inline GET routes unblocked */
app.use('/api/shipments', shipmentRoutes);
