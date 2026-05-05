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

    const response = await axios.get(`https://services.marinetraffic.com/api/exportvesseltrack/${process.env.MARINE_API_KEY}/mmsi:${mmsi}`);

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
const getRoute = async (origin, destination, groundTruth = null) => {
  console.log(`[SEA_SERVICE] Generating dynamic maritime path: ${origin} -> ${destination}`);

  const start = groundTruth?.origin || { lat: 1.3521, lng: 103.8198 };
  const end = groundTruth?.destination || { lat: 33.7739, lng: -118.2437 };
  const dist_m = groundTruth?.distance_meters || 12800000;

  return [{
    summary: `Maritime Route: ${origin} to ${destination}`,
    distance: `${(dist_m / 1000).toFixed(0)} km`,
    duration: `${Math.round(dist_m / 1000 / 30 / 24)} days`,
    distance_meters: dist_m,
    duration_seconds: Math.round(dist_m / 1000 / 30 * 3600),
    total_cost: (dist_m / 1000) * 0.15,
    total_fuel: (dist_m / 1000) * 1.5,
    path: [
      start,
      { lat: (start.lat + end.lat) / 2 - 5.0, lng: (start.lng + end.lng) / 2 }, // Deep sea curve
      end
    ]
  }];
};

export default { getVesselStatus, getRoute };
