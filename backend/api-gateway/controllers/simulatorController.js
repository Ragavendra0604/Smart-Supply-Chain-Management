import crypto from 'crypto';
import axios from 'axios';
import { db } from '../config/firebase.js';
import mapsService from '../services/mapsService.js';

// --- PRODUCTION SIMULATOR ENGINE ---
// Maps shipmentId -> { interval, path, index }
// This allows multiple concurrent simulations for different shipments.
const activeSimulations = new Map();

// Internal Headers for Simulator to talk to API Gateway
const getSimHeaders = (idempotencyKey = null) => {
  const headers = {
    'x-simulator-secret': process.env.SIMULATOR_SECRET || 'hackathon-2026-secret',
    'Content-Type': 'application/json'
  };
  if (idempotencyKey) headers['x-idempotency-key'] = idempotencyKey;
  return headers;
};

const startSimulator = async (req, res) => {
  const { shipment_id } = req.body || {};

  if (!shipment_id) {
    return res.status(400).json({ success: false, message: 'shipment_id is required to start simulation' });
  }

  if (activeSimulations.has(shipment_id)) {
    return res.status(400).json({ success: false, message: `Simulation already running for ${shipment_id}` });
  }

  try {
    // --- DYNAMIC DATA FETCHING ---
    // Instead of hardcoding defaults, we pull the truth from Firestore
    const shipmentDoc = await db().collection('shipments').doc(shipment_id).get();
    if (!shipmentDoc.exists) {
      return res.status(404).json({ success: false, message: `Shipment ${shipment_id} not found. Create it first.` });
    }

    const { origin, destination } = shipmentDoc.data();
    console.log(`📦 [SIMULATOR] Starting Dynamic Engine for ${shipment_id} (${origin} -> ${destination})`);
    
    const baseUrl = process.env.API_BASE_URL || `http://localhost:${process.env.PORT || 5000}`;
    
    // 1. Fetch Route Data (Centralized)
    const routes = await mapsService.getRoute(origin, destination);
    const route = routes[0];
    
    // 2. Start Vehicle Movement (Every 5 seconds)
    // We target 5 AI analysis points per trip (Start, 25%, 50%, 75%, Destination)
    const checkpointStep = Math.max(1, Math.floor(route.path.length / 4));
    
    const state = {
      path: route.path,
      index: 0,
      shipment_id,
      checkpointStep,
      interval: null
    };

    state.interval = setInterval(async () => {
      if (state.index >= state.path.length) {
        console.log(`🏁 [SIMULATOR] Shipment ${shipment_id} reached destination.`);
        stopSimulationLogic(shipment_id);
        return;
      }
      
      const point = state.path[state.index];
      const lat = point.lat || point[0];
      const lng = point.lng || point[1];

      try {
        const idempotencyKey = `sim-${shipment_id}-${state.index}`;
        
        // --- CHECKPOINT LOGIC: Reduce Gemini Cost ---
        const doc = await db().collection('shipments').doc(shipment_id).get();
        const currentData = doc.data() || {};
        
        // --- LOGIC UPGRADE: Risk-Aware Override ---
        // If the last analysis showed HIGH risk, we enter 'Observation Mode'
        // and trigger AI on EVERY move until the risk is resolved.
        const isHighRisk = currentData.aiResponse?.risk_level === 'HIGH';
        const isCheckpoint = (state.index % state.checkpointStep === 0) || (state.index === state.path.length - 1) || isHighRisk;
        
        if (isHighRisk) {
          console.log(`⚠️ [SIMULATOR] ${shipment_id} in HIGH RISK zone. Entering Full Observation Mode.`);
        }

        // --- LOGIC UPGRADE: Dynamic Path Switching ---
        // Every 3 moves (15s), check if the user applied a new route
        if (state.index % 3 === 0) {
          if (currentData.status === 'ROUTE_APPLIED' && currentData.aiResponse?.all_routes) {
            const bestRoute = currentData.aiResponse.all_routes.find(r => r.is_recommended);
            if (bestRoute && bestRoute.summary !== route.summary) {
              console.log(`🚀 [SIMULATOR] ${shipment_id} switching to OPTIMIZED path: ${bestRoute.summary}`);
              state.path = bestRoute.path || state.path;
            }
          }
        }
        
        const updateUrl = `${baseUrl}/update-location`;
        const payload = { 
          shipment_id, 
          lat, 
          lng,
          trigger_ai: isCheckpoint 
        };
        
        // Call the Gateway's own endpoint so the logic remains centralized (PubSub, AI, etc.)
        await axios.post(updateUrl, payload, { 
          headers: getSimHeaders(idempotencyKey),
          timeout: 3000 
        });

        state.index++;
      } catch (err) {
        console.error(`[SIMULATOR ERROR] ${shipment_id} move failed:`, err.message);
      }
    }, 5000);

    activeSimulations.set(shipment_id, state);

    res.json({ 
      success: true, 
      message: `Simulation engine active for ${shipment_id}`,
      total_points: route.path.length,
      origin,
      destination
    });

  } catch (err) {
    console.error(`[SIMULATOR START ERROR] ${err.message}`);
    res.status(500).json({ success: false, error: err.message });
  }
};

const stopSimulator = (req, res) => {
  const { shipment_id } = req.body;
  if (!shipment_id) {
    // If no ID provided, stop ALL (panic button)
    const count = activeSimulations.size;
    activeSimulations.forEach((_, id) => stopSimulationLogic(id));
    return res.json({ success: true, message: `Stopped all ${count} active simulations` });
  }

  if (stopSimulationLogic(shipment_id)) {
    res.json({ success: true, message: `Simulation stopped for ${shipment_id}` });
  } else {
    res.status(404).json({ success: false, message: "No active simulation found for this shipment ID" });
  }
};

const stopSimulationLogic = (shipmentId) => {
  const state = activeSimulations.get(shipmentId);
  if (state) {
    if (state.interval) clearInterval(state.interval);
    activeSimulations.delete(shipmentId);
    console.log(`🛑 [SIMULATOR] Cleaned up state for ${shipmentId}`);
    return true;
  }
  return false;
};

export default { startSimulator, stopSimulator };
