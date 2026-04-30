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
    // This allows calling Cloud Run services that have --no-allow-unauthenticated
    let authHeaders = {};
    try {
      const client = await auth.getIdTokenClient(aiBaseUrl);
      authHeaders = await client.getRequestHeaders();
    } catch (authError) {
      console.warn('Unable to fetch ID Token (likely local dev):', authError.message);
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