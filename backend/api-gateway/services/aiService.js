import axios from 'axios';
import { GoogleAuth } from 'google-auth-library';

const auth = new GoogleAuth();

const getPrediction = async (data) => {
  try {
    const aiBaseUrl = process.env.AI_SERVICE_URL || '';
    if (!aiBaseUrl) throw new Error('AI_SERVICE_URL is not configured');

    const url = aiBaseUrl.endsWith('/predict') 
      ? aiBaseUrl 
      : `${aiBaseUrl}/predict`;

    // Production-Grade: Fetch ID Token for Service-to-Service Auth
    // Use the base URL (origin) as the audience to ensure Cloud Run accepts the token.
    let authHeaders = {};
    try {
      const audience = new URL(aiBaseUrl).origin;
      const client = await auth.getIdTokenClient(audience);
      authHeaders = await client.getRequestHeaders();
    } catch (authError) {
      console.warn(`[AI AUTH WARNING] Failed to fetch ID Token for audience ${aiBaseUrl}: ${authError.message}`);
      // In local development, we might not have a service account, so we proceed without headers
      // In production (Cloud Run), this indicates a configuration or permission issue.
    }

    const response = await axios.post(
      url,
      data,
      {
        headers: { 
          ...authHeaders,
          'Content-Type': 'application/json' 
        },
        timeout: 20000
      }
    );

    return response.data;

  } catch (error) {
    console.error('AI Service Error:', error.message);

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