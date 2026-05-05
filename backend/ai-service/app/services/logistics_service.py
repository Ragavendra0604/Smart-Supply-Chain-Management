import os
import json
import numpy as np
import pandas as pd
from datetime import datetime
from typing import List, Dict, Any, Optional
from pydantic import BaseModel
from app.models.ml_model import get_ml_model
from app.utils.logger import logger
from app.services.ai_client import get_genai_client
from app.models.schemas import TacticalDecision

class InputData(BaseModel):
    shipment_id: Optional[str] = None
    origin: Optional[str] = None
    destination: Optional[str] = None
    routeData: Optional[Any] = None
    weatherData: Optional[Any] = None
    newsData: Optional[Any] = None
    currentLocation: Optional[Any] = None
    source: Optional[str] = None
    mode: Optional[str] = "ROAD"
    # --- STRATEGIC PARAMETERS ---
    cargo_type: Optional[str] = "General"
    priority: Optional[str] = "Normal"
    is_perishable: Optional[bool] = False
    delivery_deadline: Optional[str] = None
    fuel_level: Optional[float] = 100.0
    vehicle_health: Optional[str] = "Good"
    traffic_level: Optional[float] = 1.0
    speed_modifier: Optional[float] = 1.0
    model_name: Optional[str] = "gemini-2.5-flash"

def get_ml_delay_prediction(route: Dict[str, Any], weather: Dict[str, Any], mode: str = "ROAD", 
                             traffic_level: float = 1.0, speed_modifier: float = 1.0) -> float:
    # ml_model = get_ml_model()
    # if ml_model is None:
    #     return 0.0
        
    try:
        # ML DISABLED: Moving intelligence to Gemini AI as requested
        # Using a base heuristic for the 'Risk Engine' math while AI generates reasoning
        base_dur = route.get("duration_seconds") or 1
        traffic_dur = route.get("traffic_duration_seconds") or base_dur
        
        # Calculate heuristic delay based on What-If sliders
        traffic_impact = (base_dur / 60) * (traffic_level - 1.0)
        speed_impact = (base_dur / 60) * (1.0 - speed_modifier)
        
        weather_impact = 0
        cond = (weather.get("condition") or "clear").lower()
        if "storm" in cond: weather_impact = 45
        elif "rain" in cond: weather_impact = 15
        
        prediction = max(0.0, float(traffic_impact + speed_impact + weather_impact))
        
        mode_upper = mode.upper()
        if mode_upper == "AIR": prediction *= 0.4
        elif mode_upper == "SEA": prediction *= 2.5
            
        return round(prediction, 2)
    except Exception as e:
        logger.error(f"Heuristic Fallback Error: {e}")
        return 0.0

def score_and_rank_routes(routes: List[Dict[str, Any]], weather: Dict[str, Any], mode: str = "ROAD", 
                         fuel_level: float = 100.0, vehicle_health: str = "Good", 
                         news_data: List[Dict[str, Any]] = None,
                         traffic_level: float = 1.0, speed_modifier: float = 1.0) -> List[Dict[str, Any]]:
    COST_PER_KM = float(os.environ.get("COST_PER_KM", 0.88))
    FUEL_PER_KM = float(os.environ.get("FUEL_PER_KM", 0.32))
    processed_routes = []
    
    for i, route in enumerate(routes):
        dist_km = 0.0
        try:
            raw_dist = route.get("distance_meters")
            if raw_dist is not None:
                dist_km = float(raw_dist) / 1000.0
            else:
                dist_str = str(route.get("distance", "0")).split()[0].replace(",", "")
                dist_km = float(dist_str) if dist_str else 0.0
        except (ValueError, IndexError): dist_km = 0.0

        duration_min = 0
        try:
            raw_dur = route.get("duration_seconds")
            if raw_dur is not None:
                duration_min = int(float(raw_dur) / 60)
            else:
                dur_str = str(route.get("duration", "0")).split()[0]
                duration_min = int(dur_str) if dur_str.isdigit() else 0
        except (ValueError, IndexError): duration_min = 0

        total_cost = round(dist_km * COST_PER_KM, 2)
        total_fuel = round(dist_km * FUEL_PER_KM, 1)
        
        # Base delay from 'Smart Heuristic' (ML is currently commented out)
        predicted_delay_mins = get_ml_delay_prediction(route, weather, mode, traffic_level, speed_modifier)
        
        # --- OVERRIDE INJECTION ---
        # Apply the tactical traffic level (What-if slider)
        # If traffic_level > 1.0, we add proportional delay
        if traffic_level > 1.0:
            injected_traffic_delay = duration_min * (traffic_level - 1.0) * 0.5
            predicted_delay_mins += injected_traffic_delay
            
        # Apply the tactical speed modifier (What-if slider)
        # Speed modifier 0.5 means half speed (doubles duration)
        if speed_modifier < 1.0:
            slowdown_penalty = duration_min * (1.0 - speed_modifier)
            predicted_delay_mins += slowdown_penalty
            
        # --- HOLISTIC RISK SCORING ENGINE ---
        # 1. Base Risk (Traffic/ML Delay)
        base_risk = 0.0
        if duration_min > 0:
            risk_ratio = predicted_delay_mins / duration_min
            base_risk = risk_ratio * 1.5 # Balanced scaling
        
        # 2. Weather Penalty
        weather_penalty = 0.0
        cond = (weather.get("condition") or "clear").lower()
        if any(x in cond for x in ["storm", "flood", "tornado", "hurricane"]): 
            weather_penalty = 0.6
        elif any(x in cond for x in ["rain", "snow", "fog"]): 
            weather_penalty = 0.25
        
        # 3. Mechanical/Resource Penalty
        resource_penalty = 0.0
        # Low Fuel
        if fuel_level < 15: resource_penalty += 0.5
        elif fuel_level < 30: resource_penalty += 0.2
        
        # Vehicle Health
        health_lower = vehicle_health.lower()
        if "critical" in health_lower: resource_penalty += 0.7
        elif "poor" in health_lower or "warning" in health_lower: resource_penalty += 0.3
        
        # 4. News/Event Signals
        news_penalty = 0.0
        if news_data:
            relevant_news = [n for n in news_data if any(x in n.get('title','').lower() for x in ['accident', 'strike', 'protest', 'closed'])]
            news_penalty = min(len(relevant_news) * 0.15, 0.4)

        # 4. FINAL LOGISTICS METRICS
        travel_time_min = duration_min + predicted_delay_mins
        risk_score = min(base_risk + weather_penalty + resource_penalty + news_penalty, 1.0)
        
        processed_routes.append({
            "summary": route.get("summary", f"Route {i+1}"),
            "distance_km": dist_km,
            "raw_duration_min": duration_min,
            "travel_time_min": travel_time_min,
            "total_cost": total_cost,
            "total_fuel": total_fuel,
            "risk_level": "HIGH" if risk_score > 0.6 else ("MEDIUM" if risk_score > 0.3 else "LOW"),
            "risk_score": risk_score,
            "predicted_delay_mins": predicted_delay_mins,
            "is_recommended": False,
            "path": route.get("path", [])
        })

    if processed_routes:
        max_time = max(r["travel_time_min"] for r in processed_routes) or 1
        max_cost = max(r["total_cost"] for r in processed_routes) or 1
        best_score = float('inf')
        best_route_index = 0
        for i, r in enumerate(processed_routes):
            time_factor = r["travel_time_min"] / max_time
            cost_factor = r["total_cost"] / max_cost
            risk_factor = r["risk_score"]
            # Recommendation weight: Low Risk is now prioritized more (0.4 weight)
            composite_score = (time_factor * 0.3) + (cost_factor * 0.3) + (risk_factor * 0.4)
            if composite_score < best_score:
                best_score = composite_score
                best_route_index = i
        processed_routes[best_route_index]["is_recommended"] = True
        
    return processed_routes

from app.models.schemas import LogisticsEngineResponse, EngineAnalysis

def generate_logistics_insight(risk_score: float, predicted_delay: str, data: InputData) -> Dict[str, Any]:
    client = get_genai_client()
    
    # --- DETERMINISTIC FALLBACK LOGIC ---
    def get_fallback_engine_response(reason: str) -> Dict[str, Any]:
        risk_level = "LOW" if risk_score < 0.3 else "MEDIUM" if risk_score < 0.6 else "HIGH"
        decision = "GO" if risk_score < 0.3 else "HOLD" if risk_score < 0.6 else "REROUTE"
        
        # Simple heuristic for fallback metrics
        return {
            "success": True,
            "analysis": {
                "route": {"origin": data.origin or "Unknown", "destination": data.destination or "Unknown", "distance_km": 0.0},
                "traffic": {"duration_minutes": 0.0, "congestion_level": risk_level, "traffic_index": data.traffic_level - 1.0 if data.traffic_level > 1.0 else 0.0},
                "weather": {"condition": (data.weatherData or {}).get("condition", "Clear"), "severity_index": 0.1},
                "fuel": {"fuel_price_per_litre": 1.2, "consumption_kmpl": 12.0, "fuel_cost": 0.0},
                "costing": {"base_cost": 100.0, "fuel_cost": 0.0, "total_cost": 100.0},
                "time": {"estimated_minutes": 0.0, "delay_probability": risk_score},
                "risk": {
                    "score": risk_score,
                    "level": risk_level,
                    "factors": {"traffic": 0.4, "weather": 0.3, "route": 0.3}
                },
                "ai_insights": {
                    "decision": decision,
                    "confidence": 0.9,
                    "bottlenecks": [f"Fallback mode: {reason}"],
                    "recommendation": f"Proceed with {decision} protocol based on heuristic risk of {risk_score}."
                }
            }
        }

    if client is None:
        return get_fallback_engine_response("AI connection pending")

    try:
        weather = data.weatherData or {}
        weather_condition = weather.get("condition") or "Clear"
        timestamp = datetime.now().isoformat()
        
        # --- NEW SENIOR LOGISTICS ENGINE PROMPT ---
        prompt = f"""
            SYSTEM ROLE: Senior AI Logistics Decision Engine (Deterministic + Explainable Mode)

            OBJECTIVE:
            Generate a complete, realistic, and production-ready shipment analysis JSON. 
            The system MUST compute all logistics factors dynamically and avoid assumptions.

            INPUT:
            - Origin: {data.origin or "Unknown"}
            - Destination: {data.destination or "Unknown"}
            - Mode: {data.mode}
            - Cargo Type: {data.cargo_type}
            - Priority: {data.priority}
            - Perishable: {data.is_perishable}
            - Current Time: {timestamp}
            - Fuel Level: {data.fuel_level}%
            - Vehicle Health: {data.vehicle_health}
            - Traffic Level: {data.traffic_level}
            - Speed Modifier: {data.speed_modifier}

            AVAILABLE DATA SOURCES (MANDATORY USAGE):
            - Route Summary: {json.dumps([{"summary": r.get("summary"), "distance": r.get("distance_km"), "duration": r.get("travel_time_min")} for r in (data.routeData if isinstance(data.routeData, list) else [])]) if data.routeData else "[]"}
            - Weather: {weather_condition}
            - News/Disruptions: {json.dumps([{"title": n.get("title")} for n in (data.newsData if data.newsData else [])]) if data.newsData else "[]"}

            STRICT REQUIREMENTS:
            1. Return ONLY valid JSON. No explanations, no extra text.
            2. Numeric values must be numbers (NO strings like "39 mins").
            3. delay_probability MUST NOT be 0 unless mathematically justified.
            4. risk_score = (0.4 × traffic_index) + (0.3 × weather_severity) + (0.3 × route_complexity).
            5. Use probabilistic and realistic modeling.

            DECISION LOGIC:
            - GO -> risk < 0.3
            - HOLD -> risk 0.3–0.6
            - REROUTE -> risk > 0.6 or major bottlenecks

            OUTPUT SCHEMA (STRICT JSON ONLY):
            {{
                "success": true,
                "analysis": {{
                    "route": {{ "origin": "...", "destination": "...", "distance_km": number }},
                    "traffic": {{ "duration_minutes": number, "congestion_level": "LOW|MEDIUM|HIGH", "traffic_index": 0–1 }},
                    "weather": {{ "condition": "...", "severity_index": 0–1 }},
                    "fuel": {{ "fuel_price_per_litre": number, "consumption_kmpl": number, "fuel_cost": number }},
                    "costing": {{ "base_cost": number, "fuel_cost": number, "total_cost": number }},
                    "time": {{ "estimated_minutes": number, "delay_probability": 0–1 }},
                    "risk": {{ "score": 0–1, "level": "LOW|MEDIUM|HIGH", "factors": {{ "traffic": number, "weather": number, "route": number }} }},
                    "ai_insights": {{ "decision": "GO|HOLD|REROUTE", "confidence": 0–1, "bottlenecks": [], "recommendation": "clear actionable instruction" }}
                }}
            }}
            """
            
        try:
            model_name = data.model_name or "gemini-2.5-flash"
            
            response = client.models.generate_content(
                model=model_name,
                contents=prompt,
                config={ 'response_mime_type': 'application/json' }
            )
            
            if not response or not response.text:
                return get_fallback_engine_response("Empty AI response")

            # --- SCHEMA ENFORCEMENT ---
            try:
                res_json = json.loads(response.text.strip())
                # Validate against the new mandatory schema
                validated = LogisticsEngineResponse(**res_json)
                return validated.dict()
            except Exception as parse_err:
                logger.error(f"AI Engine Schema Validation Failed: {parse_err}")
                return get_fallback_engine_response("Schema mismatch")
            
        except Exception as e:
            logger.error(f"Gemini API Engine Error: {str(e)}")
            return get_fallback_engine_response("API Timeout")

    except Exception as e:
        logger.error(f"Gemini Engine Wrapper Error: {e}")
        return get_fallback_engine_response("System Error")
