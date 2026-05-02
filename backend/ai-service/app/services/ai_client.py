import google.auth
from google import genai
import os

_client = None

def get_genai_client():
    global _client
    if _client is not None:
        return _client

    try:
        credentials, project_id = google.auth.default(
            scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
        _client = genai.Client(
            vertexai=True,
            project=project_id,
            location="us-central1"
        )
    except Exception:
        # Fallback for local dev
        _client = None
    return _client
