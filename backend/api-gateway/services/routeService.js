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

    try {
      switch (transportMode) {
        case 'AIR':
          return await airService.getRoute(origin, destination);
        case 'SEA':
          return await seaService.getRoute(origin, destination);
        case 'ROAD':
        default:
          return await mapsService.getRoute(origin, destination);
      }
    } catch (err) {
      console.error(`[ROUTE_SERVICE] Failed to fetch ${transportMode} route:`, err.message);
      // Resilience Fallback: Try Road if Air/Sea fails (if applicable)
      if (transportMode !== 'ROAD') {
        console.warn(`[ROUTE_SERVICE] Attempting road fallback for ${transportMode}`);
        return await mapsService.getRoute(origin, destination).catch(() => []);
      }
      return [];
    }
  }
}

export default new RouteService();
