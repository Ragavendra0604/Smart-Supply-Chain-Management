from fastapi import FastAPI, Request, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, model_validator
from google import genai
from google.cloud import storage, firestore
from typing import List, Dict, Any, Optional

import google.auth
import json
import joblib
import pandas as pd
import numpy as np
import os
import base64
import traceback
from datetime import datetime
import logging
from logging.handlers import RotatingFileHandler

app = FastAPI()
db = firestore.Client()
ml_model = None

# Enable CORS for frontend/backend communication
# Lock CORS to the API gateway origin only.
# Set ALLOWED_ORIGINS env var as comma-separated list for production.
_raw_origins = os.environ.get(
    "ALLOWED_ORIGINS",
    "http://localhost:5000,http://localhost:3000,http://localhost:8080,https://ssm-sb.web.app,https://ssm-sb.firebaseapp.com"
)
_allowed_origins = [o.strip() for o in _raw_origins.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_credentials=True,
    allow_methods=["POST", "GET"],
    allow_headers=["Content-Type", "Authorization"],
)

# --- CENTRALIZED LOGGING UTILITY ---
LOG_DIR = os.path.join(os.path.dirname(__file__), "../../logs")
if not os.path.exists(LOG_DIR):
    os.makedirs(LOG_DIR)

log_formatter = logging.Formatter('{"timestamp": "%(asctime)s", "service": "AI_SERVICE", "level": "%(levelname)s", "message": "%(message)s"}')
log_handler = RotatingFileHandler(os.path.join(LOG_DIR, "ai_service.log"), maxBytes=5*1024*1024, backupCount=2)
log_handler.setFormatter(log_formatter)

logger = logging.getLogger("ai_service")
logger.setLevel(logging.INFO)
logger.addHandler(log_handler)
logger.addHandler(logging.StreamHandler()) # Also print to console

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

# -------- PRODUCTION ML MODEL --------
MODEL_PATH = "delay_model.pkl"
try:
    ml_model = joblib.load(MODEL_PATH)
    print(f"Production XGBoost Model loaded from {MODEL_PATH}")
except Exception as e:
    print(f"Warning: Could not load production model: {e}")
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
    shipment_id: Optional[str] = None   # FIX: was silently ignored (not declared)
    origin: Optional[str] = None
    destination: Optional[str] = None
    routeData: Optional[Any] = None
    weatherData: Optional[Any] = None
    newsData: Optional[Any] = None
    currentLocation: Optional[Any] = None
    source: Optional[str] = None
    mode: Optional[str] = "ROAD"  # Multi-modal support

# -------- GENERATIVE AI INSIGHTS --------
def generate_logistics_insight(prediction: float, data: InputData) -> str:
    """
    Uses Gemini 2.5 Flash to explain the risk and suggest tactical moves.
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

def load_production_model():
    global ml_model
    try:
        bucket_name = os.environ.get("MODEL_BUCKET", "logistics-models-prod")
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        
        # Download latest version dynamically
        blob = bucket.blob("xgboost/delay_model_latest.pkl")
        blob.download_to_filename("/tmp/delay_model.pkl")
        
        ml_model = joblib.load("/tmp/delay_model.pkl")
        print("Production ML Model loaded from GCS")
    except Exception as e:
        print(f"MLOps Warning: Could not load model from GCS: {e}. Falling back to defaults.")
@app.on_event("startup")
def startup_event():
    load_production_model()
# Pub/Sub Push Endpoint
@app.post("/pubsub/push")
async def handle_pubsub(request: Request):
    """
    Cloud Run receives Pub/Sub messages here as HTTP POST.
    Must return 200/204 to acknowledge, or 500 to trigger retry.
    """
    try:
        envelope = await request.json()
        if not envelope or "message" not in envelope:
            # Malformed envelope — ack to avoid poison-pill retry loops
            logger.error("Invalid Pub/Sub envelope received — acknowledging to prevent retry storm")
            return JSONResponse(status_code=200, content={"status": "invalid_envelope"})

        pubsub_message = envelope["message"]
        if "data" in pubsub_message:
            decoded_data = base64.b64decode(pubsub_message["data"]).decode("utf-8")
            # FIX: Removed ast.literal_eval — it is a code injection risk.
            # If the payload is not valid JSON, it should fail loudly.
            try:
                payload = json.loads(decoded_data)
            except json.JSONDecodeError as decode_err:
                logger.error(f"Pub/Sub message is not valid JSON: {decode_err}. Raw: {decoded_data[:200]}")
                # Ack malformed message to avoid infinite retry
                return JSONResponse(status_code=200, content={"status": "malformed_payload"})

            event_type = payload.get("eventType")
            data = payload.get("data", {})

            if event_type == "shipment.location_updated":
                shipment_id = data.get("shipment_id")
                if not shipment_id:
                    logger.error("Missing shipment_id in Pub/Sub event data")
                    return JSONResponse(status_code=200, content={"status": "missing_shipment_id"})
                await process_ai_analysis(shipment_id)

        return JSONResponse(status_code=200, content={"status": "success"})

    except Exception as e:
        error_msg = f"Pub/Sub Processing Error: {traceback.format_exc()}"
        logger.error(error_msg)
        # FIX: Return HTTP 500 so Cloud Pub/Sub retries delivery.
        # Previously this returned 200 which silently dropped failed messages.
        return JSONResponse(status_code=500, content={"status": "error", "message": str(e)})

async def process_ai_analysis(shipment_id: str):
    """Heavy lifting happens here, fully decoupled from user request"""
    doc_ref = db.collection("shipments").document(shipment_id)
     # 1. Fetch live shipment data
    shipment_data = doc_ref.get().to_dict() or {}
    route_data = shipment_data.get("routeData", [])
    if not isinstance(route_data, list): route_data = [route_data]
    
    # 2. Dynamic Evaluation Constants
    COST_PER_KM = float(os.environ.get("COST_PER_KM", 0.88))
    FUEL_PER_KM = float(os.environ.get("FUEL_PER_KM", 0.32))
    
    # 3. Process All Available Routes
    processed_routes = []
    best_route_index = 0
    min_score = float('inf')

    # Fetch weather for ML features (use cached value from shipment doc)
    weather_for_ml = shipment_data.get("weatherData", {})

    for i, route in enumerate(route_data):
        # --- FIX: Robust distance parsing ---
        # Handles: "350 km", "1,234.5 km", "217 miles", numeric values
        dist_km = 0.0
        try:
            raw_dist = route.get("distance_meters")
            if raw_dist is not None:
                dist_km = float(raw_dist) / 1000.0
            else:
                dist_str = str(route.get("distance", "0")).split()[0].replace(",", "")
                dist_km = float(dist_str) if dist_str else 0.0
        except (ValueError, IndexError):
            dist_km = 0.0

        # --- FIX: Robust duration parsing ---
        # Prefer raw seconds (always available from Maps API)
        duration_min = 0
        try:
            raw_dur = route.get("duration_seconds")
            if raw_dur is not None:
                duration_min = int(float(raw_dur) / 60)
            else:
                dur_str = str(route.get("duration", "0")).split()[0]
                duration_min = int(dur_str) if dur_str.isdigit() else 0
        except (ValueError, IndexError):
            duration_min = 0

        # Calculate Costs
        total_cost = round(dist_km * COST_PER_KM, 2)
        total_fuel = round(dist_km * FUEL_PER_KM, 1)

        # --- FIX: Actually call XGBoost model in the async path ---
        risk_score = 0.0
        if ml_model is not None:
            try:
                risk_score = get_ml_delay_prediction_v3(route, weather_for_ml)
                # Normalize delay minutes → risk score (0–1 scale, capped at 2hr = 1.0)
                risk_score = round(min(risk_score / 120.0, 1.0), 3)
            except Exception as ml_err:
                logger.warning(f"XGBoost prediction failed for route {i}: {ml_err}. Using heuristic.")
                risk_score = round(min((duration_min / 60) * 0.15, 1.0), 3)
        else:
            # Heuristic fallback if model failed to load
            risk_score = round(min((duration_min / 60) * 0.15, 1.0), 3)
            
        processed_routes.append({
            "summary": route.get("summary", f"Route {i+1}"),
            "distance_km": dist_km,
            "travel_time_min": duration_min,
            "total_cost": total_cost,
            "total_fuel": total_fuel,
            "risk_level": "LOW" if risk_score < 0.2 else "MEDIUM" if risk_score < 0.5 else "HIGH",
            "risk_score": risk_score,
            "is_recommended": False
        })
        
        if risk_score < min_score:
            min_score = risk_score
            best_route_index = i

    # Mark the best route
    if processed_routes:
        processed_routes[best_route_index]["is_recommended"] = True
        
    # 4. Extract Before/After for Comparison (comparing first route vs recommended)
    best = processed_routes[best_route_index]
    current = processed_routes[0]
    
    optimization_data = {
        "before": {
            "time": f"{current['travel_time_min'] // 60}h {current['travel_time_min'] % 60}m",
            "cost": current['total_cost'],
            "fuel": current['total_fuel']
        },
        "after": {
            "time": f"{best['travel_time_min'] // 60}h {best['travel_time_min'] % 60}m",
            "cost": best['total_cost'],
            "fuel": best['total_fuel']
        }
    }

    # 5. Generate Real AI Insight
    # Pass calculated metrics to Gemini for professional reasoning
    input_data = InputData(
        shipment_id=shipment_id,
        origin=shipment_data.get("origin", "Unknown"),
        destination=shipment_data.get("destination", "Unknown"),
        routeData=route_data,
        weatherData=shipment_data.get("weatherData", {})
    )
    insight = generate_logistics_insight(best['risk_score'], input_data)
    
    # 6. Update Firestore with 100% Dynamic Data
    doc_ref.update({
        "aiResponse": {
            "success": True,
            "risk_score": best['risk_score'],
            "risk_level": best['risk_level'],
            "delay_prediction": f"{best['travel_time_min']} mins",
            "suggestion": f"Switch to {best['summary']} for optimal safety and efficiency." if best_route_index != 0 else "Maintain current optimal route.",
            "insight": insight,
            "optimization_data": optimization_data,
            "all_routes": processed_routes,
            "last_analyzed": firestore.SERVER_TIMESTAMP
        }
    })
    logger.info(f"Dynamic AI Analysis complete for {shipment_id}")


@app.post("/predict")
def predict(data: InputData):
    try:
        # 1. Handle incoming data formats safely
        raw_routes = data.routeData
        if not raw_routes:
            raw_routes = []
        elif not isinstance(raw_routes, list):
            raw_routes = [raw_routes]
            
        weather = data.weatherData or {}
        
        scored_routes = []
        for route in raw_routes:
            if not isinstance(route, dict): continue
            
            # Use upgraded V3 prediction
            try:
                predicted_delay = get_ml_delay_prediction_v3(route, weather)
            except Exception:
                predicted_delay = 5.0 # Fallback 5 min delay
            
            # Simple risk logic
            risk = min(predicted_delay / 120.0, 1.0) # > 2hrs delay = 100% risk
            
            scored_routes.append({
                **route,
                "risk_score": round(risk, 2),
                "predicted_delay_mins": predicted_delay,
            })

        # 2. Safety check for empty results
        if not scored_routes:
            print("⚠️ No valid routes found in request, returning fallback")
            return {
                "success": True,
                "risk_score": 0.1,
                "risk_level": "LOW",
                "delay_prediction": "5 mins",
                "suggestion": "Proceed normally (Simulated Route)",
                "insight": "AI Fallback: No live route data received. Following default corridor.",
                "all_routes": []
            }

        # 3. Sort and pick best
        scored_routes.sort(key=lambda x: x["predicted_delay_mins"])
        best = scored_routes[0]

        # 4. Generate Gemini Insight
        try:
            insight = generate_logistics_insight(best["predicted_delay_mins"], data)
        except Exception:
            insight = "Optimize speed to maintain schedule."

        return {
            "success": True,
            "risk_score": best["risk_score"],
            "risk_level": "HIGH" if best["risk_score"] > 0.7 else "MEDIUM" if best["risk_score"] > 0.3 else "LOW",
            "delay_prediction": f"{best['predicted_delay_mins']} mins",
            "suggestion": f"Optimal {data.mode} route via '{best.get('summary', 'Main Route')}' selected.",
            "insight": insight,
            "all_routes": scored_routes
        }
    except Exception as e:
        print(f"🔥 Critical Prediction Error: {str(e)}")
        return {
            "success": True,
            "risk_score": 0.0,
            "risk_level": "LOW",
            "delay_prediction": "0 mins",
            "suggestion": "Proceed normally (Emergency Fallback)",
            "insight": "AI temporarily unavailable. Using manual route monitoring.",
            "all_routes": []
        }

@app.get("/health")
def health():
    return {"status": "ok", "model_version": "v3-xgboost-gemini-v1"}
