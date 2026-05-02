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
const getRoute = async (origin, destination) => {
  console.log(`[AIR_SERVICE] Mocking flight path: ${origin} -> ${destination}`);
  
  return [{
    summary: "Transcontinental Flight Corridor",
    distance: "5,420 km",
    duration: "6h 45m",
    distance_meters: 5420000,
    duration_seconds: 24300,
    total_cost: 1250.00,
    total_fuel: 4200.0,
    path: [
      { lat: 37.7749, lng: -122.4194 }, // Start
      { lat: 40.7128, lng: -74.0060 }  // End
    ]
  }];
};

export default { getFlightStatus, getRoute };
