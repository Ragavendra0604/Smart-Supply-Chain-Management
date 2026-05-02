import axios from 'axios';
import polyline from '@mapbox/polyline';
import { cacheManager } from '../utils/cache.js';

const ROUTE_CACHE_TTL = 30 * 60 * 1000; // 30 minutes

/**
 * PRODUCTION MAPS SERVICE
 * Fetches real-world route data using Google Maps Directions API.
 * No hardcoded fallbacks for specific cities.
 */
const getRoute = async (origin, destination) => {
  const cacheKey = `route:${origin.toLowerCase()}:${destination.toLowerCase()}`;
  const cached = cacheManager.get(cacheKey);
  if (cached) return cached;

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

    const results = response.data.routes.map((route, index) => {
      const leg = route.legs[0];
      
      // 1. EXTRACT LANDMARKS FROM STEPS
      const landmarks = leg.steps.map(step => {
        const cleanName = step.html_instructions.replace(/<[^>]*>?/gm, '');
        return {
          name: cleanName,
          lat: step.start_location.lat,
          lng: step.start_location.lng
        };
      });

      // 2. PATH EXTRACTION (High-Resolution Overview)
      const fullPath = polyline.decode(route.overview_polyline.points).map(([lat, lng]) => ({
        lat,
        lng
      }));
      
      // Ensure the exact start and end coordinates are included
      if (fullPath.length > 0) {
        fullPath[0] = { lat: leg.start_location.lat, lng: leg.start_location.lng };
        fullPath[fullPath.length - 1] = { lat: leg.end_location.lat, lng: leg.end_location.lng };
      }

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
        path: fullPath,
        source: 'google_maps_api_overview'
      };
    });

    cacheManager.set(cacheKey, results, ROUTE_CACHE_TTL);
    return results;
  } catch (error) {
    console.error(`[MAPS SERVICE ERROR] Critical API Failure: ${error.message}.`);
    
    // Attempt to extract coordinates from strings for a minimal fallback path
    const extractCoords = (str) => {
      const parts = str.split(',').map(p => parseFloat(p.trim()));
      return (parts.length === 2 && !isNaN(parts[0])) ? { lat: parts[0], lng: parts[1] } : null;
    };

    const start = extractCoords(origin);
    const end = extractCoords(destination);
    const fallbackPath = (start && end) ? [start, end] : [];

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
        { name: `Start`, lat: start?.lat || 0, lng: start?.lng || 0 },
        { name: `End`, lat: end?.lat || 0, lng: end?.lng || 0 }
      ],
      path: fallbackPath,
      source: 'error_fallback'
    }];
  }

};

export default { getRoute };
