import axios from 'axios';
import polyline from '@mapbox/polyline';

// We manage a single instance of a simulator here for MVP purposes
let simulationInterval;
let aiInterval;
let currentPath = [];
let currentIndex = 0;
let isRunning = false;

const startSimulator = async (req, res) => {
  if (isRunning) {
    return res.status(400).json({ success: false, message: 'Simulation already running' });
  }

  const { shipment_id = "SHP001", origin = "Chennai", destination = "Bangalore" } = req.body || {};

  try {
    console.log("📦 [Simulator API] Creating shipment...");
    const baseUrl = process.env.API_BASE_URL || `http://localhost:${process.env.PORT || 5000}`;
    
    // 1. Create Shipment
    await axios.post(`${baseUrl}/create-shipment`, {
      shipment_id,
      origin,
      destination
    });

    // 2. Fetch Google Maps Path
    const response = await axios.get(
      "https://maps.googleapis.com/maps/api/directions/json",
      {
        params: {
          origin,
          destination,
          key: process.env.GOOGLE_MAPS_API_KEY,
          departure_time: 'now'
        }
      }
    );

    if (response.data.status !== "OK") throw new Error("No route found from Maps API");

    const route = response.data.routes[0];
    currentPath = polyline.decode(route.overview_polyline.points);
    currentIndex = 0;
    isRunning = true;
    
    // Trigger initial AI analysis immediately
    await axios.post(`${baseUrl}/api/shipments/analyze`, { shipment_id });

    // 3. Start Vehicle Movement (Every 5 seconds)
    simulationInterval = setInterval(async () => {
      if (currentIndex >= currentPath.length) {
        stopSimulationLogic();
        return;
      }
      const [lat, lng] = currentPath[currentIndex];
      try {
        await axios.post(`${baseUrl}/update-location`, { shipment_id, lat, lng });
        currentIndex++;
      } catch (err) {
        console.error("[Simulator] Move error:", err.message);
      }
    }, 5000);

    // 4. Start AI Polling (Every 25 seconds)
    aiInterval = setInterval(async () => {
      try {
        await axios.post(`${baseUrl}/api/shipments/analyze`, { shipment_id });
      } catch (err) {
        console.error("[Simulator] AI error:", err.message);
      }
    }, 25000);

    res.json({ success: true, message: `Simulation started for ${shipment_id} with ${currentPath.length} points` });

  } catch (err) {
    isRunning = false;
    res.status(500).json({ success: false, error: err.message });
  }
};

const stopSimulator = (req, res) => {
  stopSimulationLogic();
  res.json({ success: true, message: "Simulation stopped" });
};

const stopSimulationLogic = () => {
  if (simulationInterval) clearInterval(simulationInterval);
  if (aiInterval) clearInterval(aiInterval);
  isRunning = false;
  currentPath = [];
  currentIndex = 0;
};

export default { startSimulator, stopSimulator };
