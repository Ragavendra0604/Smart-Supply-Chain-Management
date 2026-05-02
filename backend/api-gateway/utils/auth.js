import { GoogleAuth } from 'google-auth-library';

/**
 * GCP SERVICE-TO-SERVICE AUTHENTICATION
 * Generates an ID Token to call private Cloud Run services.
 */
const auth = new GoogleAuth();

export const getServiceIdToken = async (targetAudience) => {
  try {
    const client = await auth.getIdTokenClient(targetAudience);
    const tokenResponse = await client.getRequestHeaders();
    return tokenResponse.Authorization; // Returns "Bearer <token>"
  } catch (error) {
    console.error('[AUTH ERROR] Failed to generate ID Token:', error.message);
    return null;
  }
};
