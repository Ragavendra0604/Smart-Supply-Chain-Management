import axios from 'axios';

const getPrediction = async (data) => {
  try {
    const response = await axios.post(
      process.env.AI_SERVICE_URL,
      data,
      {
        headers: { 'Content-Type': 'application/json' },
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