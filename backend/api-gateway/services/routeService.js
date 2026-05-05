import mapsService from './mapsService.js';
import airService from './airService.js';
import seaService from './seaService.js';

/**
 * RouteService abstracts multi-modal routing logic.
 * Decouples the system from road-only Google Maps dependency.
 */
class RouteService {
  /**
   * Fetches route data based on the transport mode.
   * @param {string} origin 
   * @param {string} destination 
   * @param {string} mode ROAD | AIR | SEA
   */
  async getRoute(origin, destination, mode = 'ROAD') {
    const transportMode = (mode || 'ROAD').toUpperCase();

    // 1. Always fetch a base road route to get "Ground Truth" coordinates for origin/destination
    // This eliminates "fake" hardcoded paths in the AIR/SEA services.
    let groundTruth = null;
    try {
      const roadRoutes = await mapsService.getRoute(origin, destination);
      if (roadRoutes && roadRoutes.length > 0) {
        const primary = roadRoutes[0];
        groundTruth = {
          origin: primary.path[0],
          destination: primary.path[primary.path.length - 1],
          distance_meters: primary.distance_meters
        };
      }
    } catch (err) {
      console.warn(`[ROUTE_SERVICE] Ground truth fetch failed, using minimal geocoding fallback.`);
    }

    try {
      switch (transportMode) {
        case 'AIR':
          return await airService.getRoute(origin, destination, groundTruth);
        case 'SEA':
          return await seaService.getRoute(origin, destination, groundTruth);
        case 'ROAD':
        default:
          return await mapsService.getRoute(origin, destination);
      }
    } catch (err) {
      console.error(`[ROUTE_SERVICE] Failed to fetch ${transportMode} route:`, err.message);
      if (transportMode !== 'ROAD') {
        console.warn(`[ROUTE_SERVICE] Attempting road fallback for ${transportMode}`);
        return await mapsService.getRoute(origin, destination).catch(() => []);
      }
      return [];
    }
  }
}

export default new RouteService();
