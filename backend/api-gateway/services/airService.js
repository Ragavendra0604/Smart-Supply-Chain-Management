import axios from 'axios';

/**
 * OpenSky Network / FlightAware integration
 */
const getFlightStatus = async (flightNumber) => {
  try {
    if (!process.env.FLIGHT_API_KEY) {
      return {
        mode: 'AIR',
        id: flightNumber,
        status: 'IN_AIR',
        altitude_ft: 35000,
        speed_kts: 450,
        est_arrival: new Date(Date.now() + 3600000).toISOString(),
        origin: 'SFO',
        destination: 'LHR'
      };
    }

    const response = await axios.get(`https://opensky-network.org/api/states/all?callsign=${flightNumber}`);
    const state = response.data.states?.[0];

    return {
      mode: 'AIR',
      id: flightNumber,
      status: state ? 'IN_AIR' : 'LANDED',
      lat: state?.[6],
      lng: state?.[5],
      altitude_ft: state?.[7] * 3.28,
      speed_kts: state?.[9] * 1.94,
      updated_at: new Date().toISOString()
    };
  } catch (err) {
    console.error('Air Service Error:', err.message);
    return null;
  }
};

/**
 * MOCK: Strategic Air Route Logic
 * Provides multi-modal flight paths for demo purposes.
 */
const getRoute = async (origin, destination, groundTruth = null) => {
  console.log(`[AIR_SERVICE] Generating dynamic flight path: ${origin} -> ${destination}`);
  
  const start = groundTruth?.origin || { lat: 37.7749, lng: -122.4194 };
  const end = groundTruth?.destination || { lat: 40.7128, lng: -74.0060 };
  const dist_m = groundTruth?.distance_meters || 5420000;
  
  // High-altitude flight path (linear interpolation for demo)
  const midLat = (start.lat + end.lat) / 2 + 2.0; // Curve slightly for "realism"
  const midLng = (start.lng + end.lng) / 2;

  return [{
    summary: `Flight via ${origin} Air Corridor`,
    distance: `${(dist_m / 1000).toFixed(0)} km`,
    duration: `${Math.floor(dist_m / 1000 / 800)}h ${Math.round((dist_m / 1000 / 800 % 1) * 60)}m`,
    distance_meters: dist_m,
    duration_seconds: Math.round(dist_m / 1000 / 800 * 3600),
    total_cost: (dist_m / 1000) * 0.25, // Air cost per km
    total_fuel: (dist_m / 1000) * 0.8,
    path: [
      start,
      { lat: midLat, lng: midLng },
      end
    ]
  }];
};

export default { getFlightStatus, getRoute };
