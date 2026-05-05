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
from app.models.schemas import TacticalDecision, DeliverySummaryRequest, DeliverySummaryResponse

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
    traffic_level: Optional[float] = 0.0
    speed_modifier: Optional[float] = 1.0
    model_name: Optional[str] = "gemini-2.5-flash"

def get_ml_delay_prediction(route: Dict[str, Any], weather: Dict[str, Any], mode: str = "ROAD", 
                             traffic_level: float = 0.0, speed_modifier: float = 1.0) -> float:
    # ml_model = get_ml_model()
    # if ml_model is None:
    #     return 0.0
        
    try:
        base_dur_sec = route.get("duration_seconds") or 1
        traffic_dur_sec = route.get("traffic_duration_seconds") or base_dur_sec
        
        # 1. Start with REAL-WORLD delay from Google Maps (if any)
        google_delay_min = max(0.0, (traffic_dur_sec - base_dur_sec) / 60.0)
        
        # 2. Add/Subtract SIMULATED delay from What-If sliders
        # traffic_level 0.0-1.0 from UI. 1.0 = 100% additional delay based on duration.
        sim_traffic_impact = (base_dur_sec / 60.0) * (traffic_level * 1.2) # Max 120% delay impact
        
        # speed_modifier 1.0 = normal. 0.5 = half speed (adds duration).
        sim_speed_impact = 0.0
        if speed_modifier < 1.0 and speed_modifier > 0:
            sim_speed_impact = (base_dur_sec / 60.0) * (1.0 / speed_modifier - 1.0)
        elif speed_modifier > 1.0:
            sim_speed_impact = (base_dur_sec / 60.0) * (1.0 / speed_modifier - 1.0) # Will be negative (saving time)
            
        # 3. Weather impact (now proportional to duration + base penalty)
        weather_impact = 0.0
        cond = (weather.get("condition") or "clear").lower()
        base_min = base_dur_sec / 60.0
        
        if "storm" in cond or "flood" in cond:
            weather_impact = 20.0 + (base_min * 0.4) # 20m base + 40% slowdown
        elif "rain" in cond or "snow" in cond or "fog" in cond:
            weather_impact = 5.0 + (base_min * 0.15) # 5m base + 15% slowdown
        
        prediction = google_delay_min + sim_traffic_impact + sim_speed_impact + weather_impact
        
        mode_upper = mode.upper()
        if mode_upper == "AIR": prediction *= 0.3 # Air is less affected by ground traffic/weather
        elif mode_upper == "SEA": prediction *= 1.8 # Sea is slow and very weather dependent
            
        return round(max(0.0, prediction), 2)
    except Exception as e:
        logger.error(f"Heuristic Delay Error: {e}")
        return 0.0

def score_and_rank_routes(routes: List[Dict[str, Any]], weather: Dict[str, Any], mode: str = "ROAD", 
                         fuel_level: float = 100.0, vehicle_health: str = "Good", 
                         news_data: List[Dict[str, Any]] = None,
                         traffic_level: float = 0.0, speed_modifier: float = 1.0) -> List[Dict[str, Any]]:
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

        # Base delay from 'Smart Heuristic' (Now handles traffic/speed/weather centrally)
        predicted_delay_mins = get_ml_delay_prediction(route, weather, mode, traffic_level, speed_modifier)
            
        # 4. HOLISTIC COST & FUEL ENGINE (Accounts for idling and traffic impact)
        # Fuel consumption increases with idling/slow traffic: ~0.15L per min of delay
        idling_fuel = predicted_delay_mins * 0.12 
        total_fuel = round((dist_km * FUEL_PER_KM) + idling_fuel, 1)
        total_cost = round((dist_km * COST_PER_KM) + (idling_fuel * 1.6), 2)
            
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
                "time": {"estimated_minutes": 0.0, "delay_minutes": 0.0, "delay_probability": risk_score},
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
                    "time": {{ "estimated_minutes": number, "delay_minutes": number, "delay_probability": 0–1 }},
                    "risk": {{ "score": 0–1, "level": "LOW|MEDIUM|HIGH", "factors": {{ "traffic": number, "weather": number, "route": number }} }},
                    "ai_insights": {{ "decision": "GO|HOLD|REROUTE", "confidence": 0–1, "bottlenecks": [], "recommendation": "clear actionable instruction" }}
                }}
            }}
            """
            
        try:
            model_name = data.model_name or "gemini-1.5-flash"
            
            # --- STRUCTURED OUTPUT ENFORCEMENT ---
            response = client.models.generate_content(
                model=model_name,
                contents=prompt,
                config={ 
                    'response_mime_type': 'application/json',
                    'response_schema': LogisticsEngineResponse
                }
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


# ─────────────────────────────────────────────────────────────
#  DELIVERY COMPLETION ENGINE
#  Called once when a shipment reaches DELIVERED status.
#  Returns a deterministic performance report + AI narrative.
# ─────────────────────────────────────────────────────────────

def generate_delivery_summary(req: DeliverySummaryRequest) -> dict:
    """
    Post-delivery intelligence report.
    Deterministic metrics are computed first (always available).
    Gemini enriches with narrative + maintenance assessment.
    """
    # --- 1. DETERMINISTIC PERFORMANCE METRICS ---
    delay_variance = round(req.actual_duration_min - req.planned_duration_min, 1)
    on_time = delay_variance <= 5.0  # 5-min tolerance

    # Efficiency = how close to plan (capped 0–1)
    if req.planned_duration_min > 0:
        raw_eff = 1.0 - (abs(delay_variance) / req.planned_duration_min)
        efficiency_rating = round(max(0.0, min(1.0, raw_eff)), 3)
    else:
        efficiency_rating = 1.0 if on_time else 0.6

    # Grade: A ≥0.90, B ≥0.75, C ≥0.55, D <0.55
    if efficiency_rating >= 0.90:
        grade = "A"
    elif efficiency_rating >= 0.75:
        grade = "B"
    elif efficiency_rating >= 0.55:
        grade = "C"
    else:
        grade = "D"

    # Maintenance flag: high risk score OR poor efficiency
    maintenance_flag = req.peak_risk_score >= 0.7 or efficiency_rating < 0.55

    # Deterministic fallback (returned if AI call fails)
    delay_label = f"{abs(delay_variance):.0f} min{'s' if abs(delay_variance) != 1 else ''}"
    timing_text = f"{'on time' if on_time else f'delayed by {delay_label}'}"
    fallback_summary = (
        f"Shipment {req.shipment_id} from {req.origin} to {req.destination} "
        f"via {req.mode} was delivered {timing_text}. "
        f"Total distance: {req.distance_km:.1f} km. "
        f"Fuel used: {req.total_fuel:.1f} L. "
        f"Overall cost: ${req.total_cost:.2f}. "
        f"Performance grade: {grade}."
    )
    fallback_insights = [
        f"Delivery was {'on time ✅' if on_time else f'late by {delay_label} ⚠️'}",
        f"Efficiency rating: {efficiency_rating * 100:.0f}%",
        f"Average speed: {req.avg_speed_kmh:.1f} km/h",
        f"Peak risk encountered: {req.peak_risk_score * 100:.0f}%",
        f"Weather: {req.weather_encountered}",
    ]
    fallback_recommendation = (
        "Schedule routine maintenance." if maintenance_flag
        else f"Vehicle is ready for the next assignment."
    )

    # --- 2. AI NARRATIVE ENRICHMENT ---
    client = get_genai_client()
    if client is None:
        return {
            "success": True,
            "on_time": on_time,
            "delay_variance_mins": delay_variance,
            "efficiency_rating": efficiency_rating,
            "performance_grade": grade,
            "summary": fallback_summary,
            "key_insights": fallback_insights,
            "maintenance_flag": maintenance_flag,
            "maintenance_reason": "Heuristic: high risk or low efficiency" if maintenance_flag else None,
            "next_shipment_recommendation": fallback_recommendation,
            "ai_generated": False,
        }

    try:
        prompt = f"""
SYSTEM ROLE: Senior Logistics Performance Analyst

You have just completed delivery analysis for a shipment. 
Generate a concise, professional post-delivery intelligence report in JSON.

DELIVERY TELEMETRY:
- Shipment ID: {req.shipment_id}
- Route: {req.origin} → {req.destination} via {req.mode}
- Cargo: {req.cargo_type} | Priority: {req.priority} | Perishable: {req.is_perishable}
- Distance: {req.distance_km:.1f} km
- Planned Duration: {req.planned_duration_min:.0f} mins | Actual: {req.actual_duration_min:.0f} mins
- Delay Variance: {delay_variance:+.1f} mins ({"ON TIME" if on_time else "LATE"})
- Avg Speed: {req.avg_speed_kmh:.1f} km/h
- Total Cost: ${req.total_cost:.2f} | Fuel: {req.total_fuel:.1f} L
- Peak Risk Score: {req.peak_risk_score:.2f}
- Weather Encountered: {req.weather_encountered}
- News Disruptions: {req.news_disruptions}
- Pre-computed Efficiency: {efficiency_rating:.2f} | Grade: {grade}
- Maintenance Flag: {maintenance_flag}

TASK:
1. Write a 2–3 sentence professional SUMMARY of this delivery's performance.
2. List exactly 4 KEY INSIGHTS as short bullets (under 12 words each).
3. Assess if MAINTENANCE is needed and why (max 1 sentence).
4. Write a NEXT_SHIPMENT_RECOMMENDATION (max 1 sentence).

OUTPUT SCHEMA (JSON ONLY, NO EXTRA TEXT):
{{
  "summary": "...",
  "key_insights": ["...", "...", "...", "..."],
  "maintenance_reason": "..." or null,
  "next_shipment_recommendation": "..."
}}
"""
        model_name = req.model_name or "gemini-2.5-flash"
        response = client.models.generate_content(
            model=model_name,
            contents=prompt,
            config={"response_mime_type": "application/json"},
        )

        if response and response.text:
            ai_data = json.loads(response.text.strip())
            return {
                "success": True,
                "on_time": on_time,
                "delay_variance_mins": delay_variance,
                "efficiency_rating": efficiency_rating,
                "performance_grade": grade,
                "summary": ai_data.get("summary", fallback_summary),
                "key_insights": ai_data.get("key_insights", fallback_insights),
                "maintenance_flag": maintenance_flag,
                "maintenance_reason": ai_data.get("maintenance_reason"),
                "next_shipment_recommendation": ai_data.get("next_shipment_recommendation", fallback_recommendation),
                "ai_generated": True,
            }

    except Exception as e:
        logger.error(f"Delivery Summary AI Error: {e}")

    # Fallback if AI fails
    return {
        "success": True,
        "on_time": on_time,
        "delay_variance_mins": delay_variance,
        "efficiency_rating": efficiency_rating,
        "performance_grade": grade,
        "summary": fallback_summary,
        "key_insights": fallback_insights,
        "maintenance_flag": maintenance_flag,
        "maintenance_reason": "Heuristic: high risk or low efficiency" if maintenance_flag else None,
        "next_shipment_recommendation": fallback_recommendation,
        "ai_generated": False,
    }
