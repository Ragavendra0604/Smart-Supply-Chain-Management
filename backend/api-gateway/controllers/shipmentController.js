import { db } from '../config/firebase.js';
import mapsService from '../services/mapsService.js';
import weatherService from '../services/weatherService.js';
import newsService from '../services/newsService.js';
import aiService from '../services/aiService.js';
import airService from '../services/airService.js';
import seaService from '../services/seaService.js';
import { eventManager } from '../services/eventService.js';
import { sanitizeAiResponse } from '../utils/validation.js';

/**
 * PRODUCTION LOGISTICS ENGINE: Multi-Modal & Distributed
 */
const performAnalysis = async (shipment_id) => {
  const doc = await db().collection('shipments').doc(shipment_id).get();
  if (!doc.exists) throw new Error('Shipment not found');

  const shipment = doc.data();
  const mode = shipment.vehicle_type || 'ROAD';

  let logisticsData = { routes: [], mode };

  // 1. DYNAMIC MULTI-MODAL DATA FETCHING
  if (mode === 'AIR') {
    const flight = await airService.getFlightStatus(shipment.carrier_id || 'AI101');
    logisticsData.routes = [{ summary: 'Flight Path', duration_seconds: 3600 * 4, distance_meters: 2000000, mode: 'AIR' }];
  } else if (mode === 'SEA') {
    const vessel = await seaService.getVesselStatus(shipment.carrier_id || 'SE101');
    logisticsData.routes = [{ summary: 'Ocean Lane', duration_seconds: 86400 * 5, distance_meters: 5000000, mode: 'SEA' }];
  } else {
    // Default ROAD: Reuse existing route data if already present to save API costs
    if (shipment.routeData && shipment.routeData.length > 0) {
      logisticsData.routes = shipment.routeData;
    } else {
      logisticsData.routes = await mapsService.getRoute(shipment.origin, shipment.destination).catch(() => []);
    }
  }

  // 2. FETCH ENVIRONMENTAL CONTEXT
  const [weatherData, newsData] = await Promise.all([
    weatherService.getWeather(shipment.destination).catch(() => ({})),
    newsService.getNews(shipment.origin, shipment.destination).catch(() => []),
  ]);

  // 3. AI INFERENCE (v3 XGBoost)
  const payload = {
    routeData: logisticsData.routes,
    weatherData,
    newsData,
    mode,
    origin: shipment.origin,
    destination: shipment.destination,
    currentLocation: shipment.current_location || null
  };

  const rawAiResponse = await aiService.getPrediction(payload);
  const aiResponse = sanitizeAiResponse(rawAiResponse);

  // 4. ATOMIC PERSISTENCE with Stale Update Guard
  const shipmentRef = db().collection('shipments').doc(shipment_id);
  await db().runTransaction(async (transaction) => {
    const freshDoc = await transaction.get(shipmentRef);
    if (freshDoc.exists) {
      const freshData = freshDoc.data();
      const freshAnalyzed = freshData.aiResponse?.last_analyzed?.toDate?.() || new Date(0);
      if (freshAnalyzed > new Date()) {
        // This is a rare case where a background analysis finished with a future SERVER_TIMESTAMP
        // or just after we started.
        console.log(`[SHIPMENT] Skipping sync update for ${shipment_id} - Fresher background data exists.`);
        return;
      }
    }

    transaction.update(shipmentRef, {
      aiResponse: {
        ...aiResponse,
        last_analyzed: new Date() // Consistency with SERVER_TIMESTAMP type
      },
      routeData: logisticsData.routes,
      weatherData,
      newsData,
      status: 'ANALYZED',
      updated_at: new Date()
    });
  });

  // 5. PRODUCTION FEEDBACK LOOP (Distributed Event & Analytics)
  await eventManager.publishEvent('shipment.analysis_completed', {
    shipment_id,
    prediction: aiResponse.delay_prediction,
    actual_status: shipment.status,
    mode
  });

  await eventManager.logToBigQuery(shipment_id, 'AI_ANALYSIS_COMPLETE', {
    risk_level: aiResponse.risk_level,
    delay: aiResponse.delay_prediction
  });

  return aiResponse;
};

const runAsyncAnalysis = async (shipment_id) => {
  try {
    await performAnalysis(shipment_id);
  } catch (err) {
    console.error('[PIPELINE ERROR] %s:', shipment_id, err.message);
  }
};

const analyzeShipment = async (req, res) => {
  try {
    const { shipment_id } = req.body;
    const result = await performAnalysis(shipment_id);
    res.json({ success: true, aiResponse: result });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

const simulateShipment = async (req, res) => {
  try {
    const { shipment_id, weatherCondition, trafficLevel, speedModifier } = req.body;

    const doc = await db().collection('shipments').doc(shipment_id).get();
    if (!doc.exists) throw new Error('Shipment not found');

    const shipment = doc.data();
    const mode = shipment.vehicle_type || 'ROAD';

    // 1. Prepare simulation context
    let routeData = shipment.routeData || [];
    if (routeData.length === 0) {
      routeData = await mapsService.getRoute(shipment.origin, shipment.destination).catch(() => []);
    }

    // 2. Apply Simulation Overrides
    const weatherData = {
      condition: weatherCondition || (shipment.weatherData?.condition || 'Clear'),
      temperature: shipment.weatherData?.temperature || 25,
      humidity: shipment.weatherData?.humidity || 50
    };

    // 3. Call AI Service for High-Fidelity Simulation
    const payload = {
      shipment_id,
      routeData,
      weatherData,
      newsData: shipment.newsData || [],
      mode,
      origin: shipment.origin,
      destination: shipment.destination,
      currentLocation: shipment.current_location || null,
      // Pass simulation flags if AI service supports them (heuristics applied in logistics_service.py)
      traffic_index_override: trafficLevel, 
      speed_modifier: speedModifier
    };

    const rawAiResponse = await aiService.getPrediction(payload);
    const aiResponse = sanitizeAiResponse(rawAiResponse);

    // 4. Return results WITHOUT persisting to Firestore
    res.json({ 
      success: true, 
      simulation: aiResponse,
      is_simulated: true
    });

  } catch (error) {
    console.error('[SIMULATION ERROR] %s:', req.body.shipment_id, error.message);
    res.status(500).json({ success: false, error: error.message });
  }
};

export default { analyzeShipment, runAsyncAnalysis, simulateShipment };
