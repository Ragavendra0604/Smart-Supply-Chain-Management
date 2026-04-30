import requests
import json
import time

AI_SERVICE_URL = "http://localhost:8000"
GATEWAY_URL = "http://localhost:5000"

def test_ai_service_health():
    print("Testing AI Service Health...")
    try:
        response = requests.get(f"{AI_SERVICE_URL}/health")
        print(f"Status: {response.status_code}, Body: {response.json()}")
        return response.status_code == 200
    except Exception as e:
        print(f"AI Service not running: {e}")
        return False

def test_ai_prediction():
    print("\nTesting AI Prediction Logic...")
    payload = {
        "routeData": [
            {
                "summary": "Express Highway",
                "distance_meters": 150000,
                "duration_seconds": 7200,
                "traffic_duration_seconds": 9000
            }
        ],
        "weatherData": {"condition": "Storm", "temperature": 22},
        "newsData": [],
        "source": "Chennai"
    }
    try:
        response = requests.post(f"{AI_SERVICE_URL}/predict", json=payload)
        data = response.json()
        print(f"Prediction Response: {json.dumps(data, indent=2)}")
        assert data['success'] is True
        assert 'risk_score' in data
        assert 'delay_prediction' in data
        print("AI Prediction Test Passed")
        return True
    except Exception as e:
        print(f"AI Prediction Test Failed: {e}")
        return False

def test_gateway_health():
    print("\nTesting API Gateway Health...")
    try:
        response = requests.get(f"{GATEWAY_URL}/health")
        print(f"Status: {response.status_code}, Body: {response.json()}")
        return response.status_code == 200
    except Exception as e:
        print(f"Gateway not running: {e}")
        return False

if __name__ == "__main__":
    # We expect these to fail if services aren't started yet, 
    # but this script serves as the verification tool.
    ai_ok = test_ai_service_health()
    if ai_ok:
        test_ai_prediction()
    
    test_gateway_health()
