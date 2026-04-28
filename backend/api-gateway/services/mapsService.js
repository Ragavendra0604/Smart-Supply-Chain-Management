import axios from 'axios';
import polyline from '@mapbox/polyline';

const getRoute = async (origin, destination) => {
  const url = `https://maps.googleapis.com/maps/api/directions/json`;

  const response = await axios.get(url, {
    params: {
      origin,
      destination,
      key: process.env.GOOGLE_MAPS_API_KEY,
      departure_time: 'now',
      alternatives: true
    }
  });

  if (!response.data.routes || response.data.routes.length === 0) {
    throw new Error('No routes found for the given origin and destination');
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
};

export default { getRoute };
