import crypto from 'crypto';
import axios from 'axios';
import { db } from '../config/firebase.js';
import mapsService from '../services/mapsService.js';

// --- PRODUCTION SIMULATOR ENGINE (V4) ---
// Multi-tenant Map: shipmentId -> State Object
const activeSimulations = new Map();

const getSimHeaders = (idempotencyKey = null) => {
  const headers = {
    'x-simulator-secret': process.env.SIMULATOR_SECRET || 'hackathon-2026-secret',
    'Content-Type': 'application/json'
  };
  if (idempotencyKey) headers['x-idempotency-key'] = idempotencyKey;
  return headers;
};

/**
 * Entry point: Starts a dynamic, event-driven simulation for a specific shipment.
 */
const startSimulator = async (req, res) => {
  const { shipment_id } = req.body || {};

  if (!shipment_id) {
    return res.status(400).json({ success: false, message: 'shipment_id is required' });
  }

  if (activeSimulations.has(shipment_id)) {
    return res.status(400).json({ success: false, message: 'Simulation already active' });
  }

  try {
    // 1. DYNAMIC FETCH: Pull the truth from Firestore (No hardcoding)
    const shipmentDoc = await db().collection('shipments').doc(shipment_id).get();
    if (!shipmentDoc.exists) {
      return res.status(404).json({ success: false, message: 'Shipment record not found' });
    }

    const { origin, destination } = shipmentDoc.data();
    console.log(`📦 [SIMULATOR] Launching Engine: ${shipment_id} (${origin} -> ${destination})`);

    // 2. FETCH REAL ROUTE DATA
    const routes = await mapsService.getRoute(origin, destination);
    const route = routes[0];

    // 3. INITIALIZE STATE
    const state = {
      path: route.path,
      landmarks: route.landmarks || [],
      index: 0,
      shipment_id,
      checkpointStep: Math.max(1, Math.floor(route.path.length / 4)),
      isActive: true,
      timeoutId: null
    };

    activeSimulations.set(shipment_id, state);

    // 4. TRIGGER RECURSIVE LOOP
    runSimulationStep(shipment_id);

    res.json({
      success: true,
      message: `Dynamic simulation active for ${shipment_id}`,
      points: route.path.length
    });

  } catch (err) {
    console.error(`[SIMULATOR FATAL] ${err.message}`);
    res.status(500).json({ success: false, error: err.message });
  }
};

/**
 * Core Logic: Processes one 'move' and schedules the next.
 */
const runSimulationStep = async (shipmentId) => {
  const state = activeSimulations.get(shipmentId);

  // Guard: Stop immediately if killed or missing
  if (!state || !state.isActive) return;

  // Destination reached
  if (state.index >= state.path.length) {
    console.log(`🏁 [SIMULATOR] ${shipmentId} arrived.`);
    stopSimulationLogic(shipmentId);
    return;
  }

  const baseUrl = process.env.API_BASE_URL || `http://localhost:${process.env.PORT || 5000}`;
  const point = state.path[state.index];
  const lat = point.lat || point[0];
  const lng = point.lng || point[1];

  try {
    const idempotencyKey = `sim-${shipmentId}-${state.index}`;

    // Sync with Firestore for Dynamic Path Switching / Risk Alerts
    const doc = await db().collection('shipments').doc(shipmentId).get();
    const currentData = doc.data() || {};

    // A. RISK-AWARE TRIGGERING (Overwrites cost-saving if high risk)
    const isHighRisk = currentData.aiResponse?.risk_level === 'HIGH';
    const isCheckpoint = (state.index % state.checkpointStep === 0) || (state.index === state.path.length - 1) || isHighRisk;

    // B. DYNAMIC LANDMARK DETECTION
    let currentPlace = "En route";
    if (state.landmarks.length > 0) {
      let minDist = Infinity;
      state.landmarks.forEach(lm => {
        const d = Math.abs(lm.lat - lat) + Math.abs(lm.lng - lng);
        if (d < minDist) { minDist = d; currentPlace = lm.name; }
      });
    }

    // C. DYNAMIC PATH SWITCHING (If user applied optimization mid-trip)
    if (state.index % 3 === 0 && currentData.status === 'ROUTE_APPLIED') {
      const bestRoute = currentData.aiResponse?.all_routes?.find(r => r.is_recommended);
      if (bestRoute && bestRoute.summary !== currentData.summary) {
        console.log(`🚀 [SIMULATOR] ${shipmentId} switching to optimized route: ${bestRoute.summary}`);
        state.path = bestRoute.path || state.path;
      }
    }

    // D. PUSH TELEMETRY
    await axios.post(`${baseUrl}/update-location`, {
      shipment_id: shipmentId,
      lat, lng,
      current_place: currentPlace,
      trigger_ai: isCheckpoint
    }, {
      headers: getSimHeaders(idempotencyKey),
      timeout: 4000
    });

    state.index++;

  } catch (err) {
    console.error(`[SIMULATOR STEP ERROR] ${shipmentId}:`, err.message);
  }

  // SCHEDULE NEXT STEP (Recursive Timeout prevents overlapping intervals)
  if (state.isActive) {
    state.timeoutId = setTimeout(() => runSimulationStep(shipmentId), 5000);
  }
};

const stopSimulator = (req, res) => {
  const { shipment_id } = req.body;
  if (!shipment_id) {
    const count = activeSimulations.size;
    activeSimulations.forEach((_, id) => stopSimulationLogic(id));
    return res.json({ success: true, message: `Stopped all (${count}) simulations` });
  }

  if (stopSimulationLogic(shipment_id)) {
    res.json({ success: true, message: `Stopped simulation for ${shipment_id}` });
  } else {
    res.status(404).json({ success: false, message: "No active simulation found" });
  }
};

const stopSimulationLogic = (shipmentId) => {
  const state = activeSimulations.get(shipmentId);
  if (state) {
    state.isActive = false;
    if (state.timeoutId) clearTimeout(state.timeoutId);
    activeSimulations.delete(shipmentId);
    console.log(`🛑 [SIMULATOR] Terminated: ${shipmentId}`);
    return true;
  }
  return false;
};

export default { startSimulator, stopSimulator };
