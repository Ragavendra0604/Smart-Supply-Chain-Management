import { db } from '../config/firebase.js';
import mapsService from '../services/mapsService.js';
import weatherService from '../services/weatherService.js';
import newsService from '../services/newsService.js';
import aiService from '../services/aiService.js';

const analyzeShipment = async (req, res) => {
  try {
    const { shipment_id } = req.body;
    if (!shipment_id) return res.status(400).json({ error: 'shipment_id is required' });

    const doc = await db.collection('shipments').doc(shipment_id).get();
    if (!doc.exists) return res.status(404).json({ error: 'Shipment not found' });

    const shipment = doc.data();
    const { origin, destination } = shipment;

    // 1. Fetch data with absolute fallbacks
    const [rawRoute, rawWeather, rawNews] = await Promise.all([
      mapsService.getRoute(origin, destination).catch(() => []),
      weatherService.getWeather(destination).catch(() => ({})),
      newsService.getNews(origin, destination).catch(() => []),
    ]);

    // 2. Data Sanitization (Defensive Programming)
    const routeData = Array.isArray(rawRoute) ? rawRoute : [];
    const weatherData = (rawWeather && typeof rawWeather === 'object') ? rawWeather : {};
    const newsData = Array.isArray(rawNews) ? rawNews : [];

    // 3. Create Lightweight Payload (Strip unnecessary heavy map points for AI)
    const lightRouteData = routeData.map(route => ({
      route_id: route.route_id || 'default',
      summary: route.summary || 'Standard Route',
      distance_meters: route.distance_meters || 0,
      duration_seconds: route.duration_seconds || 0,
      traffic_duration: route.traffic_duration || route.duration || '--',
      traffic_duration_seconds: route.traffic_duration_seconds || route.duration_seconds || 0
    }));

    const payload = {
      routeData: lightRouteData,
      weatherData,
      newsData,
      source: shipment.origin,
      currentLocation: shipment.current_location || null
    };

    // 4. Critical Runtime Debugging
    console.log('--- [OUTGOING AI PAYLOAD] ---');
    console.log('Shipment ID:', shipment_id);
    console.log('Route Count:', payload.routeData.length, '| Type:', typeof payload.routeData);
    console.log('Weather Status:', !!payload.weatherData.condition, '| Type:', typeof payload.weatherData);
    console.log('News Articles:', payload.newsData.length, '| Type:', typeof payload.newsData);

    // 5. Send to AI
    const aiResponse = await aiService.getPrediction(payload);

    // 6. Persist results
    await db.collection('shipments').doc(shipment_id).update({
      routeData, // Store full data (with path) in DB
      weatherData,
      newsData,
      aiResponse,
      status: 'ANALYZED',
      updated_at: new Date()
    });

    res.json({ success: true, aiResponse });

  } catch (error) {
    console.error('SYSTEM ERROR in analyzeShipment:', error);
    res.status(500).json({ success: false, error: error.message });
  }
};

export default { analyzeShipment };
