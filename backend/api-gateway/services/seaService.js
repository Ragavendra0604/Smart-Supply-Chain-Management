import axios from 'axios';

/**
 * MarineTraffic / Spire AIS integration
 */
const getVesselStatus = async (mmsi) => {
  try {
    if (!process.env.MARINE_API_KEY) {
      return {
        mode: 'SEA',
        id: mmsi,
        vessel_name: 'EVER_GIVEN_V2',
        status: 'MOORED',
        port: 'Singapore',
        congestion_level: 'HIGH',
        est_departure: new Date(Date.now() + 86400000).toISOString(),
        risk_factor: 0.85
      };
    }

    const response = await axios.get(`https://api.marinetraffic.com/v1/vesselmasterdata/${process.env.MARINE_API_KEY}/mmsi:${mmsi}`);
    
    return {
      mode: 'SEA',
      id: mmsi,
      ...response.data
    };
  } catch (err) {
    console.error('Sea Service Error:', err.message);
    return null;
  }
};

/**
 * MOCK: Strategic Maritime Route Logic
 * Provides multi-modal sea paths for demo purposes.
 */
const getRoute = async (origin, destination) => {
  console.log(`[SEA_SERVICE] Mocking maritime path: ${origin} -> ${destination}`);
  
  return [{
    summary: "Standard Maritime Shipping Lane",
    distance: "12,800 km",
    duration: "14 days",
    distance_meters: 12800000,
    duration_seconds: 1209600,
    total_cost: 3500.00,
    total_fuel: 18000.0,
    path: [
      { lat: 1.3521, lng: 103.8198 }, // Singapore
      { lat: 33.7739, lng: -118.2437 } // Long Beach
    ]
  }];
};

export default { getVesselStatus, getRoute };
