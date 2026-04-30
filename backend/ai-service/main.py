from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, model_validator
from google import genai
from typing import List, Dict, Any, Optional
import google.auth
import json
import joblib
import pandas as pd
import numpy as np
from datetime import datetime

app = FastAPI()

# -------- AUTHENTICATION --------
try:
    credentials, project_id = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    client = genai.Client(
        vertexai=True,
        project=project_id,
        location="us-central1"
    )
except Exception:
    # Fallback for local dev
    client = None

# -------- PRODUCTION ML MODEL (v3 XGBoost) --------
MODEL_PATH = "delay_model_v3.pkl"
try:
    ml_model = joblib.load(MODEL_PATH)
    print(f"🔥 Production XGBoost Model v3 loaded from {MODEL_PATH}")
except Exception as e:
    print(f"⚠️ Warning: Could not load production model: {e}")
    ml_model = None

def get_ml_delay_prediction_v3(route: Dict[str, Any], weather: Dict[str, Any]) -> float:
    """
    Uses the trained XGBoost model with cyclical time features.
    Features: distance_km, traffic_index, weather_severity, is_holiday, hour_sin, hour_cos, day_of_week
    """
    if ml_model is None:
        return 0.0
        
    try:
        # 1. Feature: Distance
        dist_km = (route.get("distance_meters") or 0) / 1000.0
        
        # 2. Feature: Traffic Index (Normalized 1-5)
        base_dur = route.get("duration_seconds") or 1
        traffic_dur = route.get("traffic_duration_seconds") or base_dur
        traffic_index = min(max((traffic_dur / base_dur) * 1.5, 1.0), 5.0)
        
        # 3. Feature: Weather Severity (0-10)
        cond = (weather.get("condition") or "clear").lower()
        severity = 0.0
        if any(x in cond for x in ["storm", "tornado"]): severity = 9.0
        elif "snow" in cond: severity = 7.0
        elif "rain" in cond: severity = 3.0
        elif "cloud" in cond: severity = 1.0
        
        # 4. Feature: Time/Day (Cyclical)
        now = datetime.now()
        hr = now.hour
        dow = now.weekday()
        hr_sin = np.sin(2 * np.pi * hr / 24)
        hr_cos = np.cos(2 * np.pi * hr / 24)
        
        # 5. Feature: Holiday (Simulated)
        is_holiday = 1 if dow >= 5 else 0 # Simple mock for weekends
        
        # Prepare feature vector (Must match train_v3.py exactly)
        features = pd.DataFrame([{
            'distance_km': dist_km,
            'traffic_index': traffic_index,
            'weather_severity': severity,
            'day_of_week': dow,
            'is_holiday': is_holiday,
            'hour_sin': hr_sin,
            'hour_cos': hr_cos
        }])
        
        prediction = ml_model.predict(features)[0]
        return round(float(prediction), 2)
    except Exception as e:
        print(f"ML Prediction Error: {e}")
        return 0.0

# -------- INPUT MODEL --------
class InputData(BaseModel):
    routeData: Optional[Any] = None
    weatherData: Optional[Any] = None
    newsData: Optional[Any] = None
    currentLocation: Optional[Any] = None
    source: Optional[str] = None
    mode: Optional[str] = "ROAD" # NEW: Multi-modal support

# [Validation/Helper methods omitted for brevity - keeping logic identical to main.py but using V3]

@app.post("/predict")
def predict(data: InputData):
    try:
        raw_routes = data.routeData if isinstance(data.routeData, list) else [data.routeData]
        weather = data.weatherData or {}
        
        scored_routes = []
        for route in raw_routes:
            if not isinstance(route, dict): continue
            
            # Use upgraded V3 prediction
            predicted_delay = get_ml_delay_prediction_v3(route, weather)
            
            # Simple risk logic
            risk = min(predicted_delay / 120.0, 1.0) # > 2hrs delay = 100% risk
            
            scored_routes.append({
                **route,
                "risk_score": round(risk, 2),
                "predicted_delay_mins": predicted_delay,
            })

        # Sort by lowest delay
        scored_routes.sort(key=lambda x: x["predicted_delay_mins"])
        best = scored_routes[0]

        return {
            "success": True,
            "risk_score": best["risk_score"],
            "risk_level": "HIGH" if best["risk_score"] > 0.7 else "MEDIUM" if best["risk_score"] > 0.3 else "LOW",
            "delay_prediction": f"{best['predicted_delay_mins']} mins",
            "suggestion": f"Optimal {data.mode} route via '{best.get('summary')}' selected.",
            "all_routes": scored_routes
        }
    except Exception as e:
        return {"success": False, "error": str(e)}

@app.get("/health")
def health():
    return {"status": "ok", "model_version": "v3-xgboost"}