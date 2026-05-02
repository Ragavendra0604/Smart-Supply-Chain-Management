import axios from 'axios';
import polyline from '@mapbox/polyline';

/**
 * PRODUCTION MAPS SERVICE
 * Fetches real-world route data using Google Maps Directions API.
 * No hardcoded fallbacks for specific cities.
 */
const getRoute = async (origin, destination) => {
  const url = `https://maps.googleapis.com/maps/api/directions/json`;

  if (!process.env.GOOGLE_MAPS_API_KEY) {
    throw new Error('GOOGLE_MAPS_API_KEY is not configured in the environment.');
  }

  try {
    const response = await axios.get(url, {
      params: {
        origin,
        destination,
        key: process.env.GOOGLE_MAPS_API_KEY,
        departure_time: 'now',
        alternatives: true
      }
    });

    if (response.data.status !== 'OK') {
      const errorMsg = response.data.error_message || response.data.status;
      throw new Error(`Google Maps API Error: ${errorMsg}`);
    }

    if (!response.data.routes || response.data.routes.length === 0) {
      throw new Error(`No routes found between "${origin}" and "${destination}". Please check the addresses.`);
    }

    return response.data.routes.map((route, index) => {
      const leg = route.legs[0];
      
      // Extract landmarks from instructions for high-fidelity simulation
      const landmarks = leg.steps.map(step => {
        const cleanName = step.html_instructions.replace(/<[^>]*>?/gm, '');
        return {
          name: cleanName,
          lat: step.start_location.lat,
          lng: step.start_location.lng
        };
      });

      return {
        route_id: `route_${index}`,
        summary: route.summary || `Route via ${leg.steps[0]?.html_instructions.replace(/<[^>]*>?/gm, '').split(' ')[0] || 'Main Road'}`,
        distance: leg.distance.text,
        distance_meters: leg.distance.value,
        duration: leg.duration.text,
        duration_seconds: leg.duration.value,
        traffic_duration: leg.duration_in_traffic?.text || leg.duration.text,
        traffic_duration_seconds: leg.duration_in_traffic?.value || leg.duration.value,
        landmarks: landmarks,
        path: polyline.decode(route.overview_polyline.points).map(([lat, lng]) => ({
          lat,
          lng
        })),
        source: 'google_maps_api'
      };
    });
  } catch (error) {
    console.error(`[MAPS SERVICE ERROR] Critical API Failure: ${error.message}.`);
    
    // FALLBACK: Instead of 'random' California routes, we return a minimal 
    // structure that the simulator can handle without jumping across the globe.
    // The real fix is to ensure GOOGLE_MAPS_API_KEY is active and has Directions API enabled.
    return [{
      route_id: `route_fallback`,
      summary: "Direct Path (API Fallback)",
      distance: "Calculating...",
      distance_meters: 0, 
      duration: "Calculating...",
      duration_seconds: 0,
      traffic_duration: "Calculating...",
      traffic_duration_seconds: 0,
      landmarks: [
        { name: `Start: ${origin}`, lat: 0, lng: 0 },
        { name: `End: ${destination}`, lat: 0, lng: 0 }
      ],
      path: [], // Return empty path so simulation doesn't 'jump' to SF/LA
      source: 'error_fallback'
    }];
  }

};

export default { getRoute };
