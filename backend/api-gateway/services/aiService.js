import axios from 'axios';
import axiosRetry from 'axios-retry';
import { GoogleAuth } from 'google-auth-library';

const auth = new GoogleAuth();

// Configure Axios with Exponential Backoff
const aiClient = axios.create();
axiosRetry(aiClient, {
  retries: 3,
  retryDelay: axiosRetry.exponentialDelay,
  retryCondition: (error) => {
    // Retry on 5xx errors or 403 (to handle identity propagation delays)
    return axiosRetry.isNetworkOrIdempotentRequestError(error) ||
      (error.response && (error.response.status >= 500 || error.response.status === 403));
  }
});

const getPrediction = async (data) => {
  try {
    const aiBaseUrl = process.env.AI_SERVICE_URL || '';
    if (!aiBaseUrl) throw new Error('AI_SERVICE_URL is not configured');

    const url = aiBaseUrl.endsWith('/predict')
      ? aiBaseUrl
      : `${aiBaseUrl}/predict`;

    // Production-Grade: Fetch ID Token for Service-to-Service Auth
    let authHeaders = {};
    try {
      const audience = new URL(aiBaseUrl).origin;
      const client = await auth.getIdTokenClient(audience);
      authHeaders = await client.getRequestHeaders();
    } catch (authError) {
      console.warn(`[AI AUTH WARNING] ID Token fetch failed. Ensure Gateway has 'roles/run.invoker' on AI Service.`);
    }

    const response = await aiClient.post(
      url,
      data,
      {
        headers: {
          ...authHeaders,
          'Content-Type': 'application/json'
        },
        timeout: 25000 // Increased timeout to handle AI cold starts
      }
    );

    return response.data;

  } catch (error) {
    const status = error.response?.status;
    console.error(`[AI ERROR] ${status || 'NET_ERR'}: ${error.message}`);

    return {
      success: false,
      risk_score: 0,
      risk_level: "LOW",
      delay_prediction: "0 mins",
      suggestion: "Proceed normally",
      explanation: "AI unavailable - fallback mode"
    };
  }
};

export default { getPrediction };