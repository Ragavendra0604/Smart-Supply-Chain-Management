import axios from 'axios';

/**
 * MarineTraffic / Spire AIS integration
 * For MVP: Fetches vessel position via MMSI (Maritime Mobile Service Identity)
 */
const getVesselStatus = async (mmsi) => {
  try {
    // Demo Mock: Resilient logistics system must handle ship delays (port congestion)
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

export default { getVesselStatus };
