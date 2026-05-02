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
    model_name: Optional[str] = "gemini-2.5-flash"

def get_ml_delay_prediction(route: Dict[str, Any], weather: Dict[str, Any], mode: str = "ROAD") -> float:
    ml_model = get_ml_model()
    if ml_model is None:
        return 0.0
        
    try:
        dist_km = 0.0
        raw_dist = route.get("distance_meters")
        if raw_dist is not None:
            dist_km = float(raw_dist) / 1000.0
        else:
            dist_str = str(route.get("distance", "0")).split()[0].replace(",", "")
            dist_km = float(dist_str) if dist_str else 0.0
        
        base_dur = route.get("duration_seconds") or 1
        traffic_dur = route.get("traffic_duration_seconds") or base_dur
        traffic_index = min(max((traffic_dur / base_dur) * 1.5, 1.0), 5.0)
        
        cond = (weather.get("condition") or "clear").lower()
        severity = 0.0
        if any(x in cond for x in ["storm", "tornado"]): severity = 9.0
        elif "snow" in cond: severity = 7.0
        elif "rain" in cond: severity = 3.0
        elif "cloud" in cond: severity = 1.0
        
        now = datetime.now()
        hr = now.hour
        dow = now.weekday()
        hr_sin = np.sin(2 * np.pi * hr / 24)
        hr_cos = np.cos(2 * np.pi * hr / 24)
        is_holiday = 1 if dow >= 5 else 0
        
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
        mode_upper = mode.upper()
        if mode_upper == "AIR": prediction *= 0.4
        elif mode_upper == "SEA": prediction *= 2.5
            
        return round(float(prediction), 2)
    except Exception as e:
        logger.error(f"ML Prediction Error: {e}")
        return 0.0

def score_and_rank_routes(routes: List[Dict[str, Any]], weather: Dict[str, Any], mode: str = "ROAD", 
                         fuel_level: float = 100.0, vehicle_health: str = "Good", 
                         news_data: List[Dict[str, Any]] = None) -> List[Dict[str, Any]]:
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
        predicted_delay_mins = get_ml_delay_prediction(route, weather, mode)
            
        # --- HOLISTIC RISK SCORING ENGINE ---
        # 1. Base Risk (Traffic/ML Delay)
        base_risk = 0.0
        if duration_min > 0:
            risk_ratio = predicted_delay_mins / duration_min
            base_risk = risk_ratio * 2.0 # Scale 0.5 delay to 1.0 risk
        
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

        # COMPOSITE SCORE (Safety First)
        raw_risk_score = base_risk + weather_penalty + resource_penalty + news_penalty
        risk_score = round(min(raw_risk_score, 1.0), 3)

        processed_routes.append({
            "summary": route.get("summary", f"Route {i+1}"),
            "distance_km": dist_km,
            "travel_time_min": duration_min,
            "total_cost": total_cost,
            "total_fuel": total_fuel,
            "risk_level": "LOW" if risk_score < 0.35 else "MEDIUM" if risk_score < 0.75 else "HIGH",
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

def generate_logistics_insight(risk_score: float, predicted_delay: str, data: InputData) -> str:
    client = get_genai_client()
    if client is None:
        return "Insight unavailable (AI connection pending)."

    try:
        mode = data.mode
        origin = data.origin or "Current Location"
        dest = data.destination or "Destination"
        weather = data.weatherData or {}
        news = data.newsData or []
        
        # Determine risk level for the prompt
        risk_level = "LOW" if risk_score < 0.3 else "MEDIUM" if risk_score < 0.7 else "HIGH"
        
        prompt = f"""
            ROLE: Logistics Decision Engine (Deterministic)

            INPUT:
            Route: {origin}->{dest} | Mode: {mode}
            Cargo: {data.cargo_type}, Priority={data.priority}, Perishable={data.is_perishable}
            Deadline: {data.delivery_deadline or 'Flexible'}
            Fuel: {data.fuel_level}% | Health: {data.vehicle_health}
            Delay: {predicted_delay} | Risk: {risk_score} ({risk_level})
            Weather: {weather.get('condition','Clear')}, {weather.get('temperature','N/A')}°C

            RULES:
            NO_GO if:
            - Fuel <15 OR Health=CRITICAL OR (Risk>85 AND Priority=HIGH)

            REROUTE if:
            - 60<=Risk<=85 OR Weather in [Storm,Flood] OR (Delay>30 AND Deadline exists)

            GO if:
            - Risk<60 AND no above conditions

            SLA_RISK:
            - TRUE if delay breaches deadline buffer

            OUTPUT (JSON ONLY):
            {{
            "decision":"GO|REROUTE|NO_GO",
            "sla_risk":true/false,
            "confidence":0-100,
            "reason":"max 20 words",
            "action":"rwo clear instruction"
            }}

            CONSTRAINTS:
            - No extra text
            - Deterministic output
            - Safety > SLA > Cost
            """
            
        try:
            model_name = data.model_name or "gemini-2.5-flash"
            
            response = client.models.generate_content(
                model=model_name,
                contents=prompt,
                config={
                    'response_mime_type': 'application/json',
                }
            )
            
            if not response or not response.text:
                return "AI Insight currently unavailable (Empty response from model)."

            # Parse the structured JSON response
            import json
            try:
                res_data = json.loads(response.text.strip())
            except json.JSONDecodeError:
                # If JSON fails, return the raw text as a fallback if it looks like a string
                return response.text.strip()[:200]
            
            # Format for the Premium Dashboard Insight
            decision = res_data.get("decision", "GO")
            reason = res_data.get("reason", "Conditions verified.")
            action = res_data.get("action", "Proceed as planned.")
            
            # Create a professional, formatted string for the UI
            icon = "✅" if decision == "GO" else "⚠️" if decision == "REROUTE" else "🛑"
            return f"{icon} {decision}: {reason} Instruction: {action}"

        except Exception as e:
            logger.error(f"AI Prediction Error: {str(e)}")
            # Return the specific error for debugging in the UI
            error_detail = str(e).split(':')[-1].strip() if ':' in str(e) else str(e)
            return f"AI Insight currently unavailable ({error_detail[:50]})."

    except Exception as e:
        logger.error(f"Gemini Insight Wrapper Error: {e}")
        return "Tactical evaluation in progress..."
