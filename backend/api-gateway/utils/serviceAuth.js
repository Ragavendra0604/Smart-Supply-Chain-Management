import { GoogleAuth } from 'google-auth-library';
import axios from 'axios';

/**
 * ServiceAuthManager handles OIDC token generation for service-to-service communication
 * in GCP environment.
 */
class ServiceAuthManager {
  constructor() {
    this.auth = new GoogleAuth();
    this.tokenCache = new Map();
  }

  /**
   * Fetches an OIDC ID token for the target audience (service URL)
   * @param {string} audience The URL of the target service
   * @returns {Promise<string>}
   */
  async getIdToken(audience) {
    try {
      // In local development, return a dummy token if no credentials found
      if (process.env.NODE_ENV !== 'production' && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
        return 'dummy-local-token';
      }

      const client = await this.auth.getIdTokenClient(audience);
      const res = await client.getRequestHeaders(audience);
      return res.Authorization.split(' ')[1];
    } catch (err) {
      console.error(`[AUTH] Failed to fetch ID token for ${audience}:`, err.message);
      return null;
    }
  }

  /**
   * Wraps an axios instance with automatic OIDC token injection
   * @param {string} targetUrl The base URL of the target service
   */
  createAuthenticatedClient(targetUrl) {
    const client = axios.create({ baseURL: targetUrl });

    client.interceptors.request.use(async (config) => {
      const token = await this.getIdToken(targetUrl);
      if (token) {
        config.headers.Authorization = `Bearer ${token}`;
      }
      return config;
    });

    return client;
  }
}

export const serviceAuth = new ServiceAuthManager();
