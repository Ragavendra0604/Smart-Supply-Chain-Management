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
    logger.info(f"Production XGBoost Model loaded from {MODEL_PATH}")
except Exception as e:
    logger.warning(f"Could not load production model: {e}")
    ml_model = None

def get_ml_delay_prediction_v3(route: Dict[str, Any], weather: Dict[str, Any], mode: str = "ROAD") -> float:
    """
    Uses the trained XGBoost model with cyclical time features.
    Features: distance_km, traffic_index, weather_severity, is_holiday, hour_sin, hour_cos, day_of_week
    """
    if ml_model is None:
        return 0.0
        
    try:
        # 1. Feature: Distance
        dist_km = 0.0
        raw_dist = route.get("distance_meters")
        if raw_dist is not None:
            dist_km = float(raw_dist) / 1000.0
        else:
            dist_str = str(route.get("distance", "0")).split()[0].replace(",", "")
            dist_km = float(dist_str) if dist_str else 0.0
        
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
        
        # --- FIX: Multi-modal baseline adjustments ---
        # If mode is not ROAD, the XGBoost model (trained on road data) is less accurate.
        # We add a mode-specific bias.
        mode_upper = mode.upper()
        if mode_upper == "AIR":
            prediction *= 0.4 # Air is generally faster/less prone to ground traffic
        elif mode_upper == "SEA":
            prediction *= 2.5 # Sea is slower and delays are much longer
            
        return round(float(prediction), 2)
    except Exception as e:
        logger.error(f"ML Prediction Error: {e}")
        return 0.0

def score_and_rank_routes(routes: List[Dict[str, Any]], weather: Dict[str, Any], mode: str = "ROAD") -> List[Dict[str, Any]]:
    """
    Centralized logic to score routes based on ML predictions and multi-objective ranking.
    """
    COST_PER_KM = float(os.environ.get("COST_PER_KM", 0.88))
    FUEL_PER_KM = float(os.environ.get("FUEL_PER_KM", 0.32))
    
    processed_routes = []
    
    for i, route in enumerate(routes):
        # Robust distance parsing
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

        # Robust duration parsing
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

        # Risk Scoring
        predicted_delay_mins = get_ml_delay_prediction_v3(route, weather, mode)
            
        risk_score = 0.0
        if duration_min > 0:
            # RELATIVE RISK: delay as % of trip. 
            risk_ratio = predicted_delay_mins / duration_min
            risk_score = round(min(risk_ratio * 2.0, 1.0), 3) 
        else:
            risk_score = 0.0

        processed_routes.append({
            "summary": route.get("summary", f"Route {i+1}"),
            "distance_km": dist_km,
            "travel_time_min": duration_min,
            "total_cost": total_cost,
            "total_fuel": total_fuel,
            "risk_level": "LOW" if risk_score < 0.3 else "MEDIUM" if risk_score < 0.7 else "HIGH",
            "risk_score": risk_score,
            "predicted_delay_mins": predicted_delay_mins,
            "is_recommended": False,
            "path": route.get("path", [])
        })

    # Multi-Objective Ranking
    if processed_routes:
        max_time = max(r["travel_time_min"] for r in processed_routes) or 1
        max_cost = max(r["total_cost"] for r in processed_routes) or 1
        
        best_score = float('inf')
        best_route_index = 0
        for i, r in enumerate(processed_routes):
            time_factor = r["travel_time_min"] / max_time
            cost_factor = r["total_cost"] / max_cost
            risk_factor = r["risk_score"]
            
            composite_score = (time_factor * 0.4) + (cost_factor * 0.4) + (risk_factor * 0.2)
            
            if composite_score < best_score:
                best_score = composite_score
                best_route_index = i

        processed_routes[best_route_index]["is_recommended"] = True
        
    return processed_routes

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

            Provide EXACTLY 5–7 sentences. Follow this structure:
            1. Root cause of delay.
            2. Severity & operational impact.
            3. Recommended Action (Reroute/Maintain/Switch).
            4. Potential fallback or cost consideration.
            5. Confidence level and final summary.

            ---

            ## STYLE REQUIREMENTS
            - Professional, concise, and authoritative
            - Use deterministic, decision-ready language

            ---

            ## IMPORTANT
            - Base reasoning ONLY on provided data

            ---

            Now generate the recommendation.
            """
        
        response = client.models.generate_content(
            model="gemini-1.5-flash",
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
        logger.info("Production ML Model loaded from GCS")
    except Exception as e:
        logger.warning(f"MLOps Warning: Could not load model from GCS: {e}. Falling back to defaults.")
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
                msg_timestamp = payload.get("timestamp") # Use the payload timestamp
                if not shipment_id:
                    logger.error("Missing shipment_id in Pub/Sub event data")
                    return JSONResponse(status_code=200, content={"status": "missing_shipment_id"})
                await process_ai_analysis(shipment_id, msg_timestamp)

        return JSONResponse(status_code=200, content={"status": "success"})

    except json.JSONDecodeError as e:
        logger.error(f"Malformed JSON in Pub/Sub: {str(e)}")
        return JSONResponse(status_code=200, content={"status": "malformed_json"})
    except Exception as e:
        error_msg = f"Pub/Sub Processing Error: {traceback.format_exc()}"
        logger.error(error_msg)
        # HTTP 500 triggers Cloud Pub/Sub retry.
        return JSONResponse(status_code=500, content={"status": "error", "message": str(e)})

async def process_ai_analysis(shipment_id: str, msg_timestamp: Optional[str] = None):
    """Heavy lifting happens here, fully decoupled from user request"""
    doc_ref = db.collection("shipments").document(shipment_id)
    
    # --- RACE CONDITION PROTECTION ---
    shipment_snapshot = doc_ref.get()
    if not shipment_snapshot.exists:
        logger.warning(f"Shipment {shipment_id} disappeared during processing.")
        return
        
    shipment_data = shipment_snapshot.to_dict()
    if shipment_data.get("status") in ["STOPPED", "COMPLETED", "CANCELLED"]:
        return
    
    existing_ai = shipment_data.get("aiResponse", {})
    last_analyzed = existing_ai.get("last_analyzed")
    
    # Improved Timestamp Comparison
    if last_analyzed and msg_timestamp:
        try:
            # last_analyzed is likely a google.api_core.datetime_helpers.Datetime (aware UTC)
            # msg_timestamp is ISO string
            msg_dt = datetime.fromisoformat(msg_timestamp.replace("Z", "+00:00"))
            
            # Convert both to naive UTC for safe comparison if needed, 
            # but aware comparison is generally safe in Python 3.
            if hasattr(last_analyzed, 'timestamp'):
                if last_analyzed.timestamp() > msg_dt.timestamp():
                    logger.info(f"Skipping stale analysis for {shipment_id}")
                    return
        except (ValueError, AttributeError):
            pass # Fallback to processing if comparison fails

    route_data = shipment_data.get("routeData", [])
    if not isinstance(route_data, list): route_data = [route_data]
    mode = shipment_data.get("vehicle_type", "ROAD")
    weather_for_ml = shipment_data.get("weatherData", {})

    # Use centralized scoring engine
    processed_routes = score_and_rank_routes(route_data, weather_for_ml, mode)
    
    if not processed_routes:
        return

    # Find recommended route
    best = next((r for r in processed_routes if r["is_recommended"]), processed_routes[0])
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
    input_data = InputData(
        shipment_id=shipment_id,
        origin=shipment_data.get("origin", "Unknown"),
        destination=shipment_data.get("destination", "Unknown"),
        routeData=route_data,
        weatherData=weather_for_ml,
        mode=mode
    )
    insight = generate_logistics_insight(best['risk_score'], input_data)
    
    # 6. Update Firestore
    doc_ref.update({
        "aiResponse": {
            "success": True,
            "risk_score": best['risk_score'],
            "risk_level": best['risk_level'],
            "delay_prediction": f"{best['predicted_delay_mins']} mins",
            "suggestion": f"Switch to {best['summary']} for optimal safety and efficiency." if best is not current else "Maintain current optimal route.",
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
        mode = data.mode or "ROAD"
        
        # Use centralized scoring engine
        scored_routes = score_and_rank_routes(raw_routes, weather, mode)

        # 2. Safety check for empty results
        if not scored_routes:
            logger.warning("No valid routes found in request, returning fallback")
            return {
                "success": True,
                "risk_score": 0.1,
                "risk_level": "LOW",
                "delay_prediction": "5 mins",
                "suggestion": "Proceed normally (Simulated Route)",
                "insight": "AI Fallback: No live route data received. Following default corridor.",
                "all_routes": []
            }

        # 3. Pick recommended
        best = next((r for r in scored_routes if r["is_recommended"]), scored_routes[0])

        # 4. Generate Gemini Insight
        try:
            insight = generate_logistics_insight(best["predicted_delay_mins"], data)
        except Exception:
            insight = "Optimize speed to maintain schedule."

        return {
            "success": True,
            "risk_score": best["risk_score"],
            "risk_level": best["risk_level"],
            "delay_prediction": f"{best['predicted_delay_mins']} mins",
            "suggestion": f"Optimal {data.mode} route via '{best.get('summary', 'Main Route')}' selected.",
            "insight": insight,
            "all_routes": scored_routes
        }
    except Exception as e:
        logger.error(f"Critical Prediction Error: {str(e)}")
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
