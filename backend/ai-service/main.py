from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
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

# Enable CORS for frontend/backend communication
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

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

# -------- GENERATIVE AI INSIGHTS --------
def generate_logistics_insight(prediction: float, data: InputData) -> str:
    """
    Uses Gemini 2.0 Flash to explain the risk and suggest tactical moves.
    """
    if client is None:
        return "Insight unavailable (AI connection pending)."

    try:
        # Construct the context for Gemini
        mode = data.mode
        weather = data.weatherData or {}
        news = data.newsData or []
        
        prompt = f"""
            You are a Senior Logistics Strategy Consultant at Google, specializing in real-time supply chain optimization and disruption management.

            ---

            ## CONTEXT
            - Transport Mode: {mode}
            - Predicted Delay: {prediction} minutes
            - Destination Weather: {weather.get('condition', 'Unknown')} ({weather.get('temperature', 'N/A')}°C)
            - News Alerts (Top Signals): {json.dumps(news[:2])}

            ---

            ## OBJECTIVE
            Generate a precise, data-driven, and operationally actionable recommendation for a logistics manager managing time-sensitive shipments.

            ---

            ## OUTPUT STRUCTURE (STRICT)

            Provide EXACTLY 10–12 sentences. Follow this structure:

            1. **Root Cause Analysis**  
            Clearly explain the most likely cause of the delay by correlating traffic, weather, and external disruptions.

            2. **Primary Risk Assessment**  
            Quantify severity (Low / Medium / High) and explain operational impact.

            3. **Immediate Action Recommendation**  
            Suggest ONE clear action:
            - Reroute
            - Mode switch (Road → Air/Sea)
            - Delay departure
            - Maintain route (if safe)

            4. **Alternative Strategy**  
            Provide a secondary fallback option.

            5. **Time Impact Justification**  
            Explain how your recommendation reduces delay or risk.

            6. **Operational Considerations**  
            Mention cost, fuel, compliance, or resource implications.

            7. **Geographical / Route Insight**  
            Highlight any route-specific or region-specific risk patterns.

            8. **Predictive Insight**  
            Briefly mention how conditions may evolve in next few hours.

            9. **Confidence Level**  
            State confidence (e.g., "Confidence: 78%") based on data reliability.

            10. **Final Executive Summary**  
            One strong concluding sentence for decision-making.

            ---

            ## STYLE REQUIREMENTS

            - Professional, concise, and authoritative
            - No generic advice
            - No repetition
            - Avoid vague statements like "it may" or "possibly"
            - Use deterministic, decision-ready language
            - Focus on real logistics impact

            ---

            ## IMPORTANT

            - Base reasoning ONLY on provided data
            - Do NOT hallucinate unknown data
            - Prioritize actionability over explanation

            ---

            Now generate the recommendation.
            """
        
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt
        )
        return response.text.strip()
    except Exception as e:
        print(f"Gemini Insight Error: {e}")
        return "Strategizing ongoing... (Insight delayed)"

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

        # NEW: Generate Gemini Insight for the best route
        insight = generate_logistics_insight(best["predicted_delay_mins"], data)

        return {
            "success": True,
            "risk_score": best["risk_score"],
            "risk_level": "HIGH" if best["risk_score"] > 0.7 else "MEDIUM" if best["risk_score"] > 0.3 else "LOW",
            "delay_prediction": f"{best['predicted_delay_mins']} mins",
            "suggestion": f"Optimal {data.mode} route via '{best.get('summary')}' selected.",
            "insight": insight,
            "all_routes": scored_routes
        }
    except Exception as e:
        print(f"Prediction Error: {str(e)}") # Log for internal debugging
        return {"success": False, "error": "An internal error occurred during prediction analysis."}

@app.get("/health")
def health():
    return {"status": "ok", "model_version": "v3-xgboost-gemini-v1"}