import axios from 'axios';
import polyline from '@mapbox/polyline';

const getRoute = async (origin, destination) => {
  try {
    const url = `https://maps.googleapis.com/maps/api/directions/json`;
    
    if (!process.env.GOOGLE_MAPS_API_KEY) {
      console.error('GOOGLE_MAPS_API_KEY not configured');
      return getDefaultRoute(origin, destination);
    }

    const response = await axios.get(url, {
      params: {
        origin,
        destination,
        key: process.env.GOOGLE_MAPS_API_KEY,
        departure_time: 'now',
        alternatives: true
      }
    });

    // Check API error status
    if (response.data.status !== 'OK') {
      console.error(`Maps API status: ${response.data.status}`, response.data.error_message);
      return getDefaultRoute(origin, destination);
    }

    if (!response.data.routes || response.data.routes.length === 0) {
      console.warn(`No routes found between ${origin} and ${destination}`);
      return getDefaultRoute(origin, destination);
    }

    return response.data.routes.map((route, index) => {
      const leg = route.legs[0];

      return {
        route_id: `route_${index}`,
        summary: route.summary,
        distance: leg.distance.text,
        distance_meters: leg.distance.value,
        duration: leg.duration.text,
        duration_seconds: leg.duration.value,
        traffic_duration: leg.duration_in_traffic?.text || leg.duration.text,
        traffic_duration_seconds: leg.duration_in_traffic?.value || leg.duration.value,
        path: polyline.decode(route.overview_polyline.points).map(([lat, lng]) => ({
          lat,
          lng
        })),
      };
    });
  } catch (error) {
    console.error('Maps API error:', error.message);
    return getDefaultRoute(origin, destination);
  }
};

// Fallback route generator
// const getDefaultRoute = (origin, destination) => {
//   // Calculate approximate distance based on location names (fallback)
//   const distances = {
//     'Chennai-Bangalore': { distance_meters: 350000, duration_seconds: 18000 },
//     'Mumbai-Delhi': { distance_meters: 1450000, duration_seconds: 68400 },
//     'Bangalore-Hyderabad': { distance_meters: 565000, duration_seconds: 29400 },
//     'Chennai-Hyderabad': { distance_meters: 620000, duration_seconds: 32400 },
//   };
  
//   const key = `${origin}-${destination}`;
//   const distanceData = distances[key] || {
//     distance_meters: 500000 + Math.random() * 500000,
//     duration_seconds: 25200 + Math.random() * 25200
//   };

//   return [{
//     route_id: 'route_0',
//     summary: `${origin} to ${destination}`,
//     distance: `${Math.round(distanceData.distance_meters / 1000)} km`,
//     distance_meters: distanceData.distance_meters,
//     duration: `${Math.round(distanceData.duration_seconds / 3600)} hours`,
//     duration_seconds: distanceData.duration_seconds,
//     traffic_duration: `${Math.round(distanceData.duration_seconds / 3600)} hours`,
//     traffic_duration_seconds: distanceData.duration_seconds,
//     path: [], // No polyline available in fallback
//     source: 'fallback'
//   }];
// };

export default { getRoute };
