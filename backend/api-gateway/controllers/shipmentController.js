import { db } from '../config/firebase.js';
import mapsService from '../services/mapsService.js';
import weatherService from '../services/weatherService.js';
import newsService from '../services/newsService.js';
import aiService from '../services/aiService.js';

import aiService from '../services/aiService.js';

/**
 * Core Logic for AI Analysis - Can be run synchronously via API or asynchronously via Events
 */
const performAnalysis = async (shipment_id) => {
    const doc = await db.collection('shipments').doc(shipment_id).get();
    if (!doc.exists) throw new Error('Shipment not found');

    const shipment = doc.data();
    const { origin, destination } = shipment;

    // 1. Fetch data from external APIs
    const [rawRoute, rawWeather, rawNews] = await Promise.all([
      mapsService.getRoute(origin, destination).catch(() => []),
      weatherService.getWeather(destination).catch(() => ({})),
      newsService.getNews(origin, destination).catch(() => []),
    ]);

    const routeData = Array.isArray(rawRoute) ? rawRoute : [];
    const weatherData = (rawWeather && typeof rawWeather === 'object') ? rawWeather : {};
    const newsData = Array.isArray(rawNews) ? rawNews : [];

    // 2. Prepare AI Payload
    const payload = {
      routeData: routeData.map(route => ({
        route_id: route.route_id || 'default',
        summary: route.summary || 'Standard Route',
        distance_meters: route.distance_meters || 0,
        duration_seconds: route.duration_seconds || 0,
        traffic_duration_seconds: route.traffic_duration_seconds || route.duration_seconds || 0
      })),
      weatherData,
      newsData,
      source: shipment.origin,
      currentLocation: shipment.current_location || null
    };

    // 3. Inference
    const aiResponse = await aiService.getPrediction(payload);

    // 4. Persistence (Correct Firestore Usage: Atomic Update)
    await db.collection('shipments').doc(shipment_id).update({
      aiResponse,
      last_analyzed_at: new Date(),
      status: 'ANALYZED'
    });

    // 5. Data Pipeline (The "Learning System" Foundation)
    // Log the interaction for future model training/fine-tuning
    await db.collection('analytics_logs').add({
      shipment_id,
      payload_hash: Buffer.from(JSON.stringify(payload)).toString('base64').substring(0, 32),
      prediction: aiResponse.delay_prediction,
      risk_score: aiResponse.risk_score,
      timestamp: new Date()
    });

    return aiResponse;
};

const runAsyncAnalysis = async (shipment_id) => {
  try {
    await performAnalysis(shipment_id);
  } catch (err) {
    console.error(`[ASYNC ANALYZER] Failed for ${shipment_id}:`, err.message);
  }
};

const analyzeShipment = async (req, res) => {
  try {
    const { shipment_id } = req.body;
    if (!shipment_id) return res.status(400).json({ error: 'shipment_id is required' });

    const result = await performAnalysis(shipment_id);
    res.json({ success: true, aiResponse: result });

  } catch (error) {
    console.error('SYSTEM ERROR in analyzeShipment:', error);
    res.status(500).json({ success: false, error: error.message });
  }
};

export default { analyzeShipment, runAsyncAnalysis };
