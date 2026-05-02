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
 * INTELLIGENT INITIALIZATION PIPELINE
 * Orchestrates multi-service data fetching and AI inference in parallel.
 * Target Latency: < 2s | Performance: Parallel Async | Cost: Caching + Cooldown.
 */
const performAnalysis = async (shipment_id) => {
  // 1. DATA ACCESS & COOLDOWN LAYER
  const doc = await db().collection('shipments').doc(shipment_id).get();
  if (!doc.exists) throw new Error('Shipment not found');

  const shipment = doc.data();
  const mode = shipment.vehicle_type || 'ROAD';

  // IDEMPOTENCY & COST PROTECTION: Use a 5-minute cooldown for repeated analysis
  const lastAnalyzed = shipment.aiResponse?.last_analyzed?.toDate();
  const now = new Date();
  if (lastAnalyzed && (now - lastAnalyzed < 5 * 60 * 1000) && shipment.status === 'ANALYZED') {
    console.log(`[PIPELINE] Using cached analysis for ${shipment_id} (Cooldown active)`);
    return shipment.aiResponse;
  }

  // 2. PARALLEL ENRICHMENT ENGINE
  // Simultaneously fetch Routes (with alternatives), Weather, and News
  const [routes, weather, news] = await Promise.all([
    mapsService.getRoute(shipment.origin, shipment.destination).catch(err => {
      console.error('[MAPS ERROR]', err.message);
      return [];
    }),
    weatherService.getWeather(shipment.destination).catch(() => ({ condition: 'Clear', temperature: 25 })),
    newsService.getNews(shipment.origin, shipment.destination).catch(() => [])
  ]);

  // 3. AI INFERENCE (Strategy Pattern)
  const aiPayload = {
    shipment_id,
    routeData: routes,
    weatherData: weather,
    newsData: news,
    mode,
    origin: shipment.origin,
    destination: shipment.destination,
    currentLocation: shipment.current_location || null,
    cargo_type: shipment.cargo_type || 'General',
    priority: shipment.priority || 'NORMAL',
    fuel_level: shipment.fuel_level || 100,
    vehicle_health: shipment.vehicle_health || 'GOOD'
  };

  const rawAiResponse = await aiService.getPrediction(aiPayload);
  const aiResponse = sanitizeAiResponse(rawAiResponse);

  // 4. DATA ENRICHMENT & MAPPING (Alignment with Senior Architect Requirements)
  const bestRoute = aiResponse.all_routes?.find(r => r.is_recommended) || aiResponse.all_routes?.[0] || routes[0] || {};
  
  const enriched_data = {
    route: routes[0] || {},
    alternatives: routes.slice(1),
    traffic: {
      duration_with_traffic: bestRoute.travel_time_min ? `${bestRoute.travel_time_min} mins` : 'N/A',
      congestion_level: aiResponse.risk_level === 'HIGH' ? 'HEAVY' : aiResponse.risk_level === 'MEDIUM' ? 'MODERATE' : 'LOW'
    },
    weather: weather,
    news: news,
    fuel_cost: bestRoute.total_fuel || 0,
    estimated_time: bestRoute.travel_time_min || 0,
    estimated_cost: bestRoute.total_cost || 0,
    risk_score: aiResponse.risk_level, // "LOW | MEDIUM | HIGH"
    ai_insights: {
      delay_probability: aiResponse.ai_insights?.delay_probability || 0,
      bottlenecks: aiResponse.ai_insights?.bottlenecks || [],
      recommendation: aiResponse.insight || aiResponse.suggestion
    }
  };

  // 5. ATOMIC PERSISTENCE
  const shipmentRef = db().collection('shipments').doc(shipment_id);
  await shipmentRef.update({
    ...enriched_data,
    aiResponse: {
      ...aiResponse,
      last_analyzed: new Date()
    },
    routeData: routes,
    weatherData: weather,
    newsData: news,
    status: 'ANALYZED',
    updated_at: new Date()
  });

  // 6. PRODUCTION FEEDBACK & ANALYTICS
  eventManager.publishEvent('shipment.analysis_completed', {
    shipment_id,
    risk_level: aiResponse.risk_level,
    mode
  }).catch(() => {});

  eventManager.logToBigQuery(shipment_id, 'SHIPMENT_INITIALIZED', {
    risk: aiResponse.risk_level,
    cost: enriched_data.estimated_cost,
    mode
  }).catch(() => {});

  return enriched_data;
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
    res.json({ success: true, analysis: result });
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

export default { analyzeShipment, runAsyncAnalysis, simulateShipment, performAnalysis };
