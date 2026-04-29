import axios from 'axios';
import polyline from '@mapbox/polyline';
import dotenv from 'dotenv';
dotenv.config();

const GOOGLE_MAPS_API_KEY = process.env.GOOGLE_MAPS_API_KEY;

// Shipment config
const shipment_id = "SHP001";
const origin = "Chennai";
const destination = "Bangalore";

let path = [];
let index = 0;

/* ---------------- GET ROUTE PATH ---------------- */
const getRoutePath = async () => {
  try {
    const response = await axios.get(
      "https://maps.googleapis.com/maps/api/directions/json",
      {
        params: {
          origin,
          destination,
          key: GOOGLE_MAPS_API_KEY,
          departure_time: 'now'
        }
      }
    );

    console.log("Google API status:", response.data.status);

    if (response.data.status !== "OK") {
      console.error("Google API Error:", response.data);
      throw new Error("No route found");
    }

    const route = response.data.routes[0];

    if (!route) {
      throw new Error("No route found");
    }

    // Decode polyline → list of [lat, lng]
    path = polyline.decode(route.overview_polyline.points);

    console.log(`✅ Route loaded with ${path.length} points`);

  } catch (err) {
    console.error("Route Error:", err.message);
  }
};

/* ---------------- VEHICLE MOVEMENT ---------------- */
const startMovement = () => {
  setInterval(async () => {
    if (path.length === 0) return;

    if (index < path.length) {
      const [lat, lng] = path[index];

      try {
        await axios.post(`${process.env.API_BASE_URL || 'https://api-gateway-835572562592.us-central1.run.app'}/update-location`, {
          shipment_id,
          lat,
          lng
        });

        console.log(`🚚 Moving: ${lat}, ${lng}`);

        index++;

      } catch (err) {
        console.error("Movement Error:", err.message);
      }
    } else {
      console.log("🏁 Reached destination");
    }

  }, 5000); // every 5 sec
};

/* ---------------- CREATE SHIPMENT ---------------- */
const createShipment = async () => {
  try {
    console.log("📦 Creating shipment...");
    await axios.post(`${process.env.API_BASE_URL || 'https://api-gateway-835572562592.us-central1.run.app'}/create-shipment`, {
      shipment_id,
      origin,
      destination
    });
    console.log("✅ Shipment created or already exists");
  } catch (err) {
    console.error("Creation Error:", err.response?.data || err.message);
  }
};

/* ---------------- AI ANALYSIS ---------------- */
const startAI = () => {
  setInterval(async () => {
    try {
      console.log("🤖 Running AI analysis...");
      await axios.post(`${process.env.API_BASE_URL || 'https://api-gateway-835572562592.us-central1.run.app'}/api/shipments/analyze`, {
        shipment_id
      });
      console.log("AI analysis completed");
    } catch (err) {
      console.error("AI Error:", err.message);
    }
  }, 25000);
};

/* ---------------- INIT ---------------- */
const startSimulator = async () => {
  await createShipment();
  await getRoutePath();
  startMovement();
  startAI();
};

startSimulator();