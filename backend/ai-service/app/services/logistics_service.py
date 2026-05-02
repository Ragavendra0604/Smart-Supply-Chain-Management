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
        
        prediction = traffic_impact + speed_impact + weather_impact
        
        mode_upper = mode.upper()
        if mode_upper == "AIR": prediction *= 0.4
        elif mode_upper == "SEA": prediction *= 2.5
            
        return round(float(prediction), 2)
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

def generate_logistics_insight(risk_score: float, predicted_delay: str, data: InputData) -> str:
    client = get_genai_client()
    
    # --- DETERMINISTIC FALLBACK LOGIC ---
    def get_fallback_insight(reason: str) -> str:
        risk_level = "LOW" if risk_score < 0.3 else "MEDIUM" if risk_score < 0.7 else "HIGH"
        decision = "GO"
        action = "Proceed with caution."
        
        if risk_score > 0.85 or data.vehicle_health.upper() == "CRITICAL":
            decision = "NO_GO"
            action = "Halt shipment and await further instructions."
        elif risk_score > 0.6:
            decision = "REROUTE"
            action = "Recalculating optimal path."
            
        return f"⚠️ FALLBACK ({reason}) | {decision}: Environmental risk is {risk_level}. Instruction: {action}"

    if client is None:
        return get_fallback_insight("AI connection pending")

    try:
        mode = data.mode
        origin = data.origin or "Current Location"
        dest = data.destination or "Destination"
        weather = data.weatherData or {}
        weather_condition = weather.get("condition") or "Clear"
        
        prompt = f"""
            ROLE: Strategic AI Logistics Advisor (Primary Intelligence Mode)

            SYSTEM:
            You are the primary intelligence layer for this supply chain.
            The ML model is in observation mode; YOU are responsible for synthesizing 
            environmental data, vehicle telemetry, and tactical overrides into 
            operational decisions.

            ---

            ## INPUT

            Route: {origin} → {dest}
            Mode: {mode}

            Cargo:
            - Type: {data.cargo_type}
            - Priority: {data.priority}
            - Perishable: {data.is_perishable}

            Constraints:
            - Deadline: {data.delivery_deadline or "Flexible"}

            Vehicle:
            - Fuel: {data.fuel_level}%
            - Health: {data.vehicle_health}

            Environment:
            - Traffic Multiplier: {data.traffic_level}
            - Speed Modifier: {data.speed_modifier}
            - Weather: {weather_condition}

            Predictions:
            - Delay: {predicted_delay} minutes
            - Risk Score: {risk_score}

            ---

            ## DECISION RULES (STRICT PRIORITY)

            1. NO_GO (highest priority)
            IF:
            - Fuel < 15
            OR Health == "CRITICAL"
            OR (Risk Score > 85 AND Priority == "HIGH")

            2. REROUTE
            IF:
            - 60 ≤ Risk Score ≤ 85
            OR Delay > 30 AND Deadline != "Flexible"
            OR Traffic Multiplier ≥ 1.5
            OR Weather in ["Storm", "Flood"]

            3. GO
            IF:
            - Risk Score < 60
            AND none of the above conditions apply

            ---

            ## SLA RISK

            sla_risk = true IF:
            - Delay > 20 AND Deadline != "Flexible"
            - OR Risk Score > 70

            ---

            ## CONFIDENCE

            confidence = clamp(100 - (Risk Score × 0.5) - (Delay × 0.5), 0, 100)

            ---

            ## TASK

            1. Evaluate rules strictly (no guessing)
            2. Select ONE decision only
            3. Generate precise reasoning (4–5 sentences, operational tone)
            4. Provide ONE clear action

            ---

            ## OUTPUT (STRICT JSON ONLY)

            {{
                "decision": "GO | REROUTE | NO_GO",
                "sla_risk": true | false,
                "confidence": integer (0–100),
                "reason": "4-5 short, precise sentences explaining key factors (risk, delay, traffic, vehicle, deadline). Keep under 300 characters.",
                "action": "single clear operational instruction"
            }}

            ---

            ## HARD RULES

            - No text outside JSON
            - No markdown
            - No explanation outside "reason"
            - Follow rule priority strictly
            - If uncertain → choose safer option (REROUTE over GO)
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
                return get_fallback_insight("Empty AI response")

            # --- PRODUCTION-GRADE VALIDATION ---
            try:
                # 1. Raw JSON load
                res_json = json.loads(response.text.strip())
                # 2. Pydantic validation (Schema Enforcement)
                decision_obj = TacticalDecision(**res_json)
            except (json.JSONDecodeError, Exception) as parse_err:
                logger.error(f"AI Schema Validation Failed: {parse_err}")
                return get_fallback_insight("Schema mismatch")
            
            # Format for the Premium Dashboard Insight
            icon = "✅" if decision_obj.decision == "GO" else "⚠️" if decision_obj.decision == "REROUTE" else "🛑"
            return f"{icon} {decision_obj.decision}: {decision_obj.reason} Instruction: {decision_obj.action}"

        except Exception as e:
            logger.error(f"Gemini API Error: {str(e)}")
            return get_fallback_insight("API Timeout")

    except Exception as e:
        logger.error(f"Gemini Insight Wrapper Error: {e}")
        return get_fallback_insight("System Error")
