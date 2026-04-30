import { auth } from '../config/firebase.js';

/**
 * Production-grade Authentication Middleware
 * Verifies Firebase ID Token and attaches user to request
 */
export const authMiddleware = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    const simulatorSecret = req.headers['x-simulator-secret'];

    // Internal Simulator Bypass (for Demo/Testing scalability)
    if (simulatorSecret && simulatorSecret === process.env.SIMULATOR_SECRET) {
      req.user = { uid: 'simulator-service', email: 'simulator@internal' };
      return next();
    }
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      console.warn(`[AUTH] Unauthorized access attempt to ${req.path} from ${req.ip}`);
      return res.status(401).json({ 
        success: false, 
        error: 'Unauthorized: Missing or malformed authentication token' 
      });
    }

    const idToken = authHeader.split('Bearer ')[1];
    const decodedToken = await auth().verifyIdToken(idToken);
    
    // Attach user context for downstream logic (RBAC, auditing)
    req.user = decodedToken;
    
    next();
  } catch (error) {
    console.error(`[AUTH ERROR] Token verification failed: ${error.message}`);
    return res.status(401).json({ 
      success: false, 
      error: 'Unauthorized: Invalid or expired token' 
    });
  }
};
