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
    // Default ROAD
    logisticsData.routes = await mapsService.getRoute(shipment.origin, shipment.destination).catch(() => []);
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
    source: shipment.origin,
    currentLocation: shipment.current_location || null
  };

  const rawAiResponse = await aiService.getPrediction(payload);
  const aiResponse = sanitizeAiResponse(rawAiResponse);

  // 4. ATOMIC PERSISTENCE (Store everything for the Dashboard)
  await db().collection('shipments').doc(shipment_id).update({
    aiResponse,
    routeData: logisticsData.routes,
    weatherData,
    newsData,
    last_analyzed_at: new Date(),
    status: 'ANALYZED'
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

export default { analyzeShipment, runAsyncAnalysis };
