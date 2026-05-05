import { db } from '../config/firebase.js';
import routeService from '../services/routeService.js';
import { cacheManager } from '../utils/cache.js';

/**
 * PRODUCTION STATELESS SIMULATOR (V5)
 * Optimized for Cloud Run (Zero background execution)
 */

export const startSimulator = async (req, res) => {
  const { shipment_id } = req.body || {};

  if (!shipment_id) {
    return res.status(400).json({ success: false, message: 'shipment_id is required' });
  }

  try {
    // 1. Check Global Stop
    const sysDoc = await db().collection('system').doc('config').get();
    if (sysDoc.exists && sysDoc.data().isGlobalStopped) {
      return res.status(403).json({ success: false, message: 'Simulation blocked: Global Stop is active' });
    }

    // Clear any existing stop cache for this shipment when restarting
    cacheManager.delete(`stop:${shipment_id}`);

    // 2. Fetch Route Truth
    const shipmentDoc = await db().collection('shipments').doc(shipment_id).get();
    if (!shipmentDoc.exists) {
      return res.status(404).json({ success: false, message: 'Shipment record not found' });
    }

    const { origin, destination, vehicle_type } = shipmentDoc.data();
    
    // 3. Initialize Route Data (Supports ROAD | AIR | SEA)
    const routes = await routeService.getRoute(origin, destination, vehicle_type || 'ROAD');
    if (!routes || routes.length === 0) {
      return res.status(404).json({ success: false, message: 'No valid routes found for this shipment' });
    }
    const route = routes[0];

    await db().collection('shipments').doc(shipment_id).update({
      status: 'IN_TRANSIT',
      routeData: routes,
      current_step_index: 0,
      updated_at: new Date()
    });

    console.log(`📡 [SIMULATOR] Stateless initialization for ${shipment_id}`);

    res.json({
      success: true,
      message: `Stateless simulation initialized for ${shipment_id}`,
      total_points: route.path.length
    });

  } catch (err) {
    console.error(`[SIMULATOR ERROR] ${err.message}`);
    res.status(500).json({ success: false, error: err.message });
  }
};

export const stopSimulator = async (req, res) => {
  const { shipment_id } = req.body;
  
  try {
    if (!shipment_id) {
      return res.status(400).json({ success: false, message: 'shipment_id is required' });
    }
    if (shipment_id) {
      // 1. Update Firestore
      await db().collection('shipments').doc(shipment_id).update({
        status: 'STOPPED',
        updated_at: new Date()
      });

      // 2. Sync Local Cache for immediate blocking
      cacheManager.set(`stop:${shipment_id}`, true, 3600000); // 1hr TTL
      console.log(`🛑 [SIMULATOR] Individual stop cached for ${shipment_id}`);
    }
    res.json({ success: true, message: 'Simulation marked as stopped in state.' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
};

export default { startSimulator, stopSimulator };
