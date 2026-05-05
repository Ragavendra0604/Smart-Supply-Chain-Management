import { db } from '../config/firebase.js';
import mapsService from '../services/mapsService.js';
import routeService from '../services/routeService.js';
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
const performAnalysis = async (shipment_id, traceId = null) => {
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

  const [routes, weather, news] = await Promise.all([
    routeService.getRoute(shipment.origin, shipment.destination, mode).catch(err => {
      console.error('[ROUTE ERROR]', err.message);
      return [];
    }),
    weatherService.getWeather(shipment.destination).catch(() => weatherService.getWeatherFallback()),
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

  const rawAiResponse = await aiService.getPrediction(aiPayload, traceId);
  const aiResponse = sanitizeAiResponse(rawAiResponse);

  // 4. DATA ENRICHMENT & MAPPING (Alignment with Senior Architect Requirements)
  const bestRoute = aiResponse.all_routes?.find(r => r.is_recommended) || aiResponse.all_routes?.[0] || routes[0] || {};

  const enriched_data = {
    traffic: {
      duration_with_traffic: bestRoute.travel_time_min ? `${Math.round(bestRoute.travel_time_min)} mins` : 'N/A',
      traffic_duration: bestRoute.travel_time_min ? `${Math.round(bestRoute.travel_time_min)} mins` : 'N/A',
      congestion_level: aiResponse.risk_level === 'HIGH' ? 'HEAVY' : aiResponse.risk_level === 'MEDIUM' ? 'MODERATE' : 'LOW'
    },
    fuel_cost: bestRoute.total_fuel || 0,
    estimated_time: bestRoute.travel_time_min || 0,
    estimated_cost: bestRoute.total_cost || 0,
    traffic_duration: bestRoute.travel_time_min ? `${Math.round(bestRoute.travel_time_min)} mins` : 'N/A',
    risk_score: aiResponse.ai_insights?.delay_probability > 1 
      ? (aiResponse.ai_insights.delay_probability / 100) 
      : (aiResponse.ai_insights?.delay_probability || aiResponse.risk_score || 0),
    risk_level: aiResponse.risk_level || 'UNKNOWN',
    ai_insights: {
      delay_probability: aiResponse.ai_insights?.delay_probability || 0,
      bottlenecks: aiResponse.ai_insights?.bottlenecks || [],
      recommendation: aiResponse.insight || aiResponse.suggestion
    }
  };

  // 5. ATOMIC PERSISTENCE
  // Sync the AI's predicted traffic duration into the primary route for UI consistency
  if (routes && routes.length > 0) {
    routes[0].traffic_duration = bestRoute.travel_time_min ? `${bestRoute.travel_time_min} mins` : 'N/A';
    routes[0].duration = bestRoute.raw_duration_min ? `${bestRoute.raw_duration_min} mins` : routes[0].duration;
  }

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
  }).catch(() => { });

  eventManager.logToBigQuery(shipment_id, 'SHIPMENT_INITIALIZED', {
    risk: aiResponse.risk_level,
    cost: enriched_data.estimated_cost,
    mode
  }).catch(() => { });

  return enriched_data;
};

const runAsyncAnalysis = async (shipment_id, traceId = null) => {
  try {
    await performAnalysis(shipment_id, traceId);
  } catch (err) {
    console.error('[PIPELINE ERROR] %s:', shipment_id, err.message);
  }
};

const analyzeShipment = async (req, res) => {
  try {
    const { shipment_id } = req.body;
    const result = await performAnalysis(shipment_id, req.traceId);
    res.json({ success: true, analysis: result });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};


const simulateShipment = async (req, res) => {
  try {
    const { shipment_id, weatherCondition, trafficLevel, speedModifier, model_name } = req.body;

    const doc = await db().collection('shipments').doc(shipment_id).get();
    if (!doc.exists) throw new Error('Shipment not found');

    const shipment = doc.data();
    const mode = shipment.vehicle_type || 'ROAD';

    let routeData = shipment.routeData || [];
    if (routeData.length === 0) {
      routeData = await mapsService.getRoute(shipment.origin, shipment.destination).catch(() => []);
    }

    const weatherData = {
      condition: weatherCondition || (shipment.weatherData?.condition || 'Clear'),
      temperature: shipment.weatherData?.temperature || 25
    };

    // 3. AI Inference with Simulation Context
    const aiResponse = await aiService.getPrediction({
      shipment_id,
      routeData,
      weatherData,
      traffic_level: trafficLevel || 1.0,
      speed_modifier: speedModifier || 1.0,
      mode,
    });

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

const applyRoute = async (req, res) => {
  try {
    const { shipment_id } = req.body;
    if (!shipment_id) throw new Error('shipment_id is required');

    const shipmentRef = db().collection('shipments').doc(shipment_id);
    const doc = await shipmentRef.get();
    if (!doc.exists) throw new Error('Shipment not found');
    const shipment = doc.data();

    // Find the recommended route to promote it to primary
    const aiResponse = shipment.aiResponse || {};
    const allRoutes = aiResponse.all_routes || [];
    const recommendedRoute = allRoutes.find(r => r.is_recommended);

    let updateData = {
      status: 'ROUTE_APPLIED',
      route_applied_at: new Date(),
      updated_at: new Date()
    };

    if (recommendedRoute) {
      // If we have a recommended route object, we should ideally have its path data too.
      // But all_routes in AI response might not have full path. 
      // The mapsService.getRoute returns full path.
      // For now, let's just mark it. In a real system, we'd swap the actual path data.
      console.log(`[APPLY] Promoting recommended route: ${recommendedRoute.summary}`);
      
      // If routeData exists, we should try to match it
      const currentRoutes = shipment.routeData || [];
      const matchIndex = currentRoutes.findIndex(r => r.summary === recommendedRoute.summary);
      if (matchIndex > 0) {
        const newRoutes = [...currentRoutes];
        const [moved] = newRoutes.splice(matchIndex, 1);
        newRoutes.unshift(moved);
        updateData.routeData = newRoutes;
      }
    }

    await shipmentRef.update(updateData);

    eventManager.publishEvent('shipment.route_applied', { shipment_id }).catch(() => { });

    res.json({
      success: true,
      message: `Optimized route applied for ${shipment_id}`,
      status: 'ROUTE_APPLIED'
    });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
};

const injectSimulation = async (req, res) => {
  try {
    const { shipment_id, weatherCondition, trafficLevel, speedModifier } = req.body;
    if (!shipment_id) throw new Error('shipment_id is required');

    const updateData = {
      "weatherData.condition": weatherCondition,
      "weatherData.traffic_level": trafficLevel,
      "simulation_speed_modifier": speedModifier,
      "updated_at": new Date()
    };

    await db().collection('shipments').doc(shipment_id).update(updateData);

    // AI TRIGGER: Force re-analysis to refresh reasoning and metrics based on injected state
    const analysisResult = await performAnalysis(shipment_id, req.traceId).catch(err => {
      console.error('[INJECT-AI] Analysis trigger failed:', err.message);
      return null;
    });

    eventManager.logToBigQuery(shipment_id, 'SCENARIO_INJECTED', {
      weather: weatherCondition,
      traffic: trafficLevel,
      speed_mod: speedModifier,
      has_ai_feedback: !!analysisResult
    }).catch(() => { });

    res.json({
      success: true,
      message: 'Scenario injected and AI reasoning refreshed',
      analysis: analysisResult
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

export default {
  analyzeShipment,
  runAsyncAnalysis,
  simulateShipment,
  performAnalysis,
  applyRoute,
  injectSimulation
};
