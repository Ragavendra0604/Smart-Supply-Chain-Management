import { db } from '../config/firebase.js';
import simulatorController from './simulatorController.js';
import { cacheManager } from '../utils/cache.js';

/**
 * PRODUCTION SYSTEM CONTROLLER
 * Manages global application states (e.g., Global Stop)
 */

export const toggleGlobalStop = async (req, res) => {
  try {
    const { stopped } = req.body; // true or false

    // 1. Update Global State in Firestore
    await db().collection('system').doc('config').set({
      isGlobalStopped: stopped,
      updated_at: new Date(),
      updated_by: 'ADMIN'
    }, { merge: true });

    // 2. Sync Local Cache for high-performance blocking in Gateway
    cacheManager.set('sys:global_stop', stopped, 300000); // 5 min TTL

    // 3. Immediate Action: Kill all local simulations if stopped is true
    if (stopped) {
      simulatorController.stopSimulator({ body: {} }, { json: () => { } });
      console.log('🚨 [SYSTEM] GLOBAL STOP TRIGGERED. All local simulations killed.');
    }

    res.json({ success: true, isGlobalStopped: stopped });
  } catch (error) {
    console.error('[SYSTEM ERROR] Toggle Global Stop failed:', error.message);
    res.status(500).json({ success: false, error: error.message });
  }
};

export const getSystemStatus = async (req, res) => {
  try {
    const doc = await db().collection('system').doc('config').get();
    const config = doc.exists ? doc.data() : { isGlobalStopped: false };
    res.json({ success: true, config });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
};

export default { toggleGlobalStop, getSystemStatus };
