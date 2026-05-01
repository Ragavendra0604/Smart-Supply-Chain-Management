import { auth } from '../config/firebase.js';

/**
 * Production-grade Authentication Middleware
 * Verifies Firebase ID Token and attaches user to request
 */
export const authMiddleware = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    const simSecret = req.headers['x-simulator-secret'];

    // --- SYSTEM ACCESS: Allow Simulator Bypass ---
    // In production, this allows automated telemetry components to talk to the gateway.
    const CONFIG_SIM_SECRET = process.env.SIMULATOR_SECRET || 'hackathon-2026-secret';
    if (simSecret === CONFIG_SIM_SECRET) {
      req.user = { uid: 'system-simulator', role: 'SIMULATOR' };
      return next();
    }

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      console.warn(`[AUTH] Unauthorized access attempt to ${req.path} from ${req.ip}`);
      return res.status(401).json({
        success: false,
        error: 'Unauthorized: Missing or malformed authentication token'
      });
    }

    const idToken = authHeader.split('Bearer ')[1]?.trim();
    if (!idToken) {
      return res.status(401).json({ success: false, error: 'Unauthorized: Token missing' });
    }
    const decodedToken = await auth().verifyIdToken(idToken);

    // Attach user context for downstream logic (RBAC, auditing)
    req.user = decodedToken;

    next();
  } catch (error) {
    console.error(`[AUTH ERROR] Token verification failed: ${error.message}`);
    return res.status(401).json({
      success: false,
      error: `Unauthorized: ${error.message}`
    });
  }
};
