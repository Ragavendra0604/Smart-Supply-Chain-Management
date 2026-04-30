import axios from 'axios';

/**
 * OpenSky Network / FlightAware integration
 * For MVP: Fetches active flights by callsign or geographic bounding box
 */
const getFlightStatus = async (flightNumber) => {
  try {
    // Mocking real-world API call for demo if no key provided
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

export default { getFlightStatus };
