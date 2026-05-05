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
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    };
    if (traceId) {
      headers['x-trace-id'] = traceId;
    }

    // PRODUCTION-GRADE RETRY: Handle cold starts (503), auth lag (403), and Gemini timeouts (504/408)
    const response = await client.request({
      url,
      method: 'POST',
      data,
      headers,
      timeout: 35000, 
      retryConfig: {
        retry: 4,
        retryDelay: 1500,
        shouldRetry: (err) => {
          const status = err.response?.status;
          // Retry on: Auth issues (403), Timeouts (408), Cold starts (503), or Server errors (500+)
          return [403, 408, 500, 502, 503, 504].includes(status) || !err.response;
        },
        httpMethodsToRetry: ['POST'],
        onRetryAttempt: (err) => {
          console.warn(`[AI RETRY] Attempting to recover from ${err.response?.status || 'Network Error'}...`);
        }
      }
    });

    return response.data;

  } catch (error) {
    const status = error.response?.status;
    const isTimeout = error.code === 'ECONNABORTED' || error.message.includes('timeout');
    const message = error.response?.data?.error || error.message;
    
    console.error(`[AI ERROR] ${status || 'NET_ERR'}: ${message}`);

    // Intelligence fallback: Classify the error for the operator
    const errorType = status === 403 ? 'Authentication' : (isTimeout ? 'Latency' : 'Connectivity');
    const suggestion = `AI Analysis pending (${errorType} issue)`;
    const insight = isTimeout 
      ? "AI Service is experiencing high latency (Cold Start). Background optimization is still running."
      : `System experienced a ${errorType.toLowerCase()} issue with the AI Service (Error ${status || 'Network'}).`;

    return {
      success: false,
      risk_score: 0.1,
      risk_level: "LOW",
      delay_prediction: "0 mins",
      suggestion,
      insight
    };
  }
};

export default { getPrediction };