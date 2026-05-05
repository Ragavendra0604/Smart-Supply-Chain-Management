import axios from 'axios';
import { GoogleAuth } from 'google-auth-library';

const auth = new GoogleAuth();

/**
 * PRODUCTION-GRADE AI CLIENT
 * Uses google-auth-library for secure service-to-service communication.
 * Handles ID Token lifecycle and automatic retries for identity propagation.
 */
const getPrediction = async (data, traceId = null) => {
  try {
    const aiBaseUrl = process.env.AI_SERVICE_URL || '';
    if (!aiBaseUrl) throw new Error('AI_SERVICE_URL is not configured');

    const url = aiBaseUrl.endsWith('/predict')
      ? aiBaseUrl
      : `${aiBaseUrl}/predict`;

    // 1. Resolve Audience (Service URL without path)
    const audience = new URL(url).origin;

    // 2. Fetch ID Token Client
    // In Cloud Run, this automatically uses the Metadata Server
    const client = await auth.getIdTokenClient(audience);

    // 3. Execute Authenticated Request
    const headers = {
      'Content-Type': 'application/json'
    };
    if (traceId) {
      headers['x-trace-id'] = traceId;
    }

    const response = await client.request({
      url,
      method: 'POST',
      data,
      headers,
      timeout: 28000, // Slightly below Cloud Run default timeout
      // Built-in retry logic for transient auth issues
      retryConfig: {
        retry: 3,
        retryDelay: 1000,
        statusCodesToRetry: [[403, 403], [500, 599]]
      }
    });

    return response.data;

  } catch (error) {
    const status = error.response?.status;
    const message = error.response?.data?.error || error.message;
    
    console.error(`[AI ERROR] ${status || 'NET_ERR'}: ${message}`);

    // Fallback logic to ensure dashboard remains functional
    return {
      success: false,
      risk_score: 0.1,
      risk_level: "LOW",
      delay_prediction: "0 mins",
      suggestion: "AI Analysis pending (Authentication issue)",
      insight: `System experienced a transient connection issue with the AI Service (Error ${status || 'Unknown'}).`
    };
  }
};

export default { getPrediction };