import google.auth
from google import genai
import os

_client = None

def get_genai_client():
    global _client
    if _client is not None:
        return _client

    apiKey = os.environ.get("GEMINI_API_KEY")
    
    try:
        if apiKey:
            _client = genai.Client(api_key=apiKey)
            return _client

        # Fallback to Vertex AI / ADC
        credentials, project_id = google.auth.default(
            scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
        _client = genai.Client(
            vertexai=True,
            project=project_id,
            location="us-central1"
        )
    except Exception as e:
        print(f"AI Client Initialization Error: {e}")
        _client = None
    return _client
