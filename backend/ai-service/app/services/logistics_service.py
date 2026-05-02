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

def score_and_rank_routes(routes: List[Dict[str, Any]], weather: Dict[str, Any], mode: str = "ROAD") -> List[Dict[str, Any]]:
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
            
        risk_score = 0.0
        if duration_min > 0:
            risk_ratio = predicted_delay_mins / duration_min
            risk_score = round(min(risk_ratio * 2.0, 1.0), 3) 
        else: risk_score = 0.0

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

def generate_logistics_insight(prediction: float, data: InputData) -> str:
    client = get_genai_client()
    if client is None:
        return "Insight unavailable (AI connection pending)."

    try:
        mode = data.mode
        origin = data.origin or "Current Location"
        dest = data.destination or "Destination"
        weather = data.weatherData or {}
        news = data.newsData or []
        
        prompt = f"""
            System: Senior Logistics Strategy Consultant.
            Context: {mode} Trip from {origin} to {dest}. 
            Prediction: {prediction}min delay risk. 
            Weather: {weather.get('condition', 'Unknown')} at destination.
            News Alerts: {json.dumps(news[:2])}
            
            Objective: Generate a 4-5 sentence tactical recommendation. 
            Focus on Root Cause, Operational Impact, and a specific "Go/No-Go" or "Reroute" action.
            Style: Authoritative, deterministic.
            """
        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt
        )
        return response.text.strip()

    except Exception as e:
        logger.error(f"Gemini Insight Error: {e}")
        return "Tactical evaluation in progress..."
