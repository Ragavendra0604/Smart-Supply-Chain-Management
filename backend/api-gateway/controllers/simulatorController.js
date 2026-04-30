import axios from 'axios';
import polyline from '@mapbox/polyline';

// We manage a single instance of a simulator here for MVP purposes
let simulationInterval;
let currentPath = [];
let currentIndex = 0;
let isRunning = false;

// Internal Headers for Simulator to talk to API Gateway
const SIM_HEADERS = {
  'x-simulator-secret': process.env.SIMULATOR_SECRET || 'hackathon-2026-secret'
};

const startSimulator = async (req, res) => {
  if (isRunning) {
    return res.status(400).json({ success: false, message: 'Simulation already running' });
  }

  const { shipment_id = "SHP001", origin = "Chennai", destination = "Bangalore" } = req.body || {};

  try {
    console.log(`📦 [SIMULATOR] Starting Real-time Telemetry for ${shipment_id}`);
    const baseUrl = process.env.API_BASE_URL || `http://localhost:${process.env.PORT || 5000}`;
    
    // 1. Create Shipment (Authenticated)
    await axios.post(`${baseUrl}/create-shipment`, {
      shipment_id,
      origin,
      destination
    }, { headers: SIM_HEADERS });

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
    
    // Trigger initial AI analysis immediately (Authenticated)
    // Note: In the new architecture, this could also be triggered by a shipment.created event
    await axios.post(`${baseUrl}/api/shipments/analyze`, { shipment_id }, { headers: SIM_HEADERS });

    // 3. Start Vehicle Movement (Every 5 seconds)
    // The analysis is now triggered AUTOMATICALLY via Events when update-location is called
    simulationInterval = setInterval(async () => {
      if (currentIndex >= currentPath.length) {
        console.log(`🏁 [SIMULATOR] Shipment ${shipment_id} reached destination.`);
        stopSimulationLogic();
        return;
      }
      
      const [lat, lng] = currentPath[currentIndex];
      try {
        // Authenticated Location Update
        await axios.post(`${baseUrl}/update-location`, { shipment_id, lat, lng }, { headers: SIM_HEADERS });
        currentIndex++;
      } catch (err) {
        console.error("[Simulator] Move error:", err.message);
      }
    }, 5000);

    res.json({ 
      success: true, 
      message: `Event-driven simulation started for ${shipment_id}`,
      points: currentPath.length 
    });

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
  isRunning = false;
  currentPath = [];
  currentIndex = 0;
};

export default { startSimulator, stopSimulator };
