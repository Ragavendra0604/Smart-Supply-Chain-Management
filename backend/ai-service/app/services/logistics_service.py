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
    current_speed: Optional[float] = 0.0
    is_simulation: Optional[bool] = True
    model_name: Optional[str] = "gemini-1.5-flash"

def get_ml_delay_prediction(route: Dict[str, Any], weather: Dict[str, Any], mode: str = "ROAD", 
                             traffic_level: float = 0.0, speed_modifier: float = 1.0) -> float:
    ml_model = get_ml_model()
        
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
        
        heuristic_prediction = google_delay_min + sim_traffic_impact + sim_speed_impact + weather_impact
        
        mode_upper = mode.upper()
        if mode_upper == "AIR": heuristic_prediction *= 0.3 # Air is less affected by ground traffic/weather
        elif mode_upper == "SEA": heuristic_prediction *= 1.8 # Sea is slow and very weather dependent
            
        heuristic_prediction = max(0.0, heuristic_prediction)
        
        # 4. Enforce ML inference parity
        # ML Model is currently disabled (not fully ready) - Prioritizing Gemini AI strategic reasoning
        """
        if ml_model is not None:
            try:
                # CRITICAL FIX: Map features to match RandomForestRegressor training schema
                # Features: ['traffic_level', 'weather_condition', 'distance_km', 'time_of_day', 'day_of_week']

                # traffic_level: [0.0, 1.0] -> [1, 4]
                ml_traffic = int(round(traffic_level * 3)) + 1
                ml_traffic = max(1, min(4, ml_traffic))

                # weather_condition mapping: 1=Clear, 2=Cloudy, 3=Rain, 4=Storm
                weather_map = {
                    "clear": 1, "sunny": 1,
                    "cloudy": 2, "partly cloudy": 2, "overcast": 2, "fog": 2,
                    "rain": 3, "drizzle": 3, "shower": 3, "snow": 3,
                    "storm": 4, "thunderstorm": 4, "flood": 4, "tornado": 4, "hurricane": 4
                }
                ml_weather = weather_map.get(cond, 2) # Default to Cloudy if unknown

                dist_km = 0.0
                raw_dist = route.get("distance_meters")
                if raw_dist is not None:
                    dist_km = float(raw_dist) / 1000.0
                
                now = datetime.now()
                time_of_day = now.hour
                day_of_week = now.weekday()
                
                features = pd.DataFrame([{
                    "traffic_level": ml_traffic,
                    "weather_condition": ml_weather,
                    "distance_km": dist_km,
                    "time_of_day": time_of_day,
                    "day_of_week": day_of_week
                }])

                # Ensure exact column order as training
                features = features[['traffic_level', 'weather_condition', 'distance_km', 'time_of_day', 'day_of_week']]

                ml_pred = float(ml_model.predict(features)[0])

                # Log the prediction for audit
                logger.info(f"ML Predict [SHP]: features={features.to_dict('records')[0]} -> result={ml_pred}")

                # Ensure deterministic output combining ML + Simulation overrides
                return round(max(0.0, ml_pred + sim_speed_impact), 2)
            except Exception as ml_err:
                logger.error(f"ML Model Parity Error (Mapping/Order): {ml_err}. Falling back to deterministic heuristic.")
                return round(heuristic_prediction, 2)
        """

        return round(heuristic_prediction, 2)
    except Exception as e:
        logger.error(f"Heuristic/ML Delay Error: {e}")
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
                    "recommendation": f"Proceed with {decision} protocol based on heuristic risk of {risk_score}.",
                    "selection_reason": f"Heuristic analysis suggests the current path is viable with a risk score of {risk_score}.",
                    "rejection_reason": "Alternatives were not significantly better in the current heuristic simulation.",
                    "future_disruptions": "No major disruptions predicted by the basic heuristic engine.",
                    "query_cost_rupees": 0.0
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
            - Current Speed: {data.current_speed} km/h
            - Simulation Mode: {"ACTIVE (Ignore high-speed physics anomalies)" if data.is_simulation else "DISABLED (Real-world physics)"}

            AVAILABLE DATA SOURCES (MANDATORY USAGE):
            - Route Summary: {json.dumps([{"summary": r.get("summary"), "distance": r.get("distance_km"), "duration": r.get("travel_time_min")} for r in (data.routeData if isinstance(data.routeData, list) else [])]) if data.routeData else "[]"}
            - Weather: {weather_condition}
            - News/Disruptions: {json.dumps([{"title": n.get("title")} for n in (data.newsData if data.newsData else [])]) if data.newsData else "[]"}
            
            HEURISTIC ENGINE OUTPUT (GROUND TRUTH):
            - Calculated Risk Score: {risk_score}
            - Predicted Delay: {predicted_delay}

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
            - IMPORTANT: If Heuristic Risk is > 0.6, the decision MUST NOT be "GO".

            EXPLAINABILITY REQUIREMENTS (MANDATORY):
            - selection_reason: Provide a clear, data-driven explanation of why the chosen path is superior.
            - rejection_reason: Explicitly state why alternative routes were rejected (e.g., higher risk, cost, or weather impact).
            - future_disruptions: Predict potential upcoming disruptions based on weather trends, traffic patterns, and news signals.

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
                    "ai_insights": {{
                        "decision": "GO|HOLD|REROUTE",
                        "confidence": 0-1,
                        "bottlenecks": [],
                        "recommendation": "clear actionable instruction",
                        "comparative_analysis": ["Detailed reason why Route X was chosen over Y", "Risk/Cost trade-off analysis"],
                        "selection_reason": "Clear explanation of why this specific path was chosen.",
                        "rejection_reason": "Why other available paths were not selected.",
                        "future_disruptions": "Analysis of what potential disruptions might occur in the near future for this route."
                    }}
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
                # Add heuristic cost for Flash query (~$0.001 -> ~₹0.08)
                if "analysis" in res_json and "ai_insights" in res_json["analysis"]:
                    res_json["analysis"]["ai_insights"]["query_cost_rupees"] = 0.08
                
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
    
    TELEMETRY VALIDATION: Flags incomplete/corrupted sensor data separately from performance.
    """
    # --- 0. TELEMETRY VALIDATION ---
    # Check for missing or corrupted telemetry data
    telemetry_anomalies = []
    
    if req.distance_km == 0.0:
        telemetry_anomalies.append("No distance data recorded")
    
    if req.avg_speed_kmh == 0.0 and req.actual_duration_min > 0:
        telemetry_anomalies.append("Zero speed despite duration")
    
    # Sanity check: if distance > 0 but speed = 0, telemetry is broken
    if req.distance_km > 0 and req.avg_speed_kmh == 0.0:
        telemetry_anomalies.append("Distance recorded but no speed data")
    
    has_telemetry_issue = len(telemetry_anomalies) > 0
    
    # --- 1. DETERMINISTIC PERFORMANCE METRICS ---
    delay_variance = round(req.actual_duration_min - req.planned_duration_min, 1)
    on_time = delay_variance <= 5.0  # 5-min tolerance

    # Efficiency = how close to plan (capped 0–1)
    # ONLY calculate if telemetry is valid; otherwise default to timing-only assessment
    if has_telemetry_issue:
        # Fallback: Only use on-time status, not telemetry-based efficiency
        efficiency_rating = 0.95 if on_time else 0.5
        grade = "A" if on_time else "C"
        efficiency_caveat = "⚠️ Incomplete telemetry - grade based on timing only"
    else:
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
        efficiency_caveat = None

    # Maintenance flag: only genuine vehicle issues (high risk score or poor efficiency).
    # Telemetry degradation is a DATA QUALITY issue, not a vehicle maintenance issue.
    # The telemetry status is already surfaced separately in the UI via key_insights icons.
    maintenance_flag = (req.peak_risk_score >= 0.7 or efficiency_rating < 0.55) and not has_telemetry_issue

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
        + (f" ⚠️ {efficiency_caveat}" if efficiency_caveat else "")
    )
    
    fallback_insights = [
        f"Delivery was {'on time ✅' if on_time else f'late by {delay_label} ⚠️'}",
        f"Efficiency rating: {efficiency_rating * 100:.0f}%",
        f"Average speed: {req.avg_speed_kmh:.1f} km/h" if not has_telemetry_issue else "⚠️ Speed telemetry unavailable",
        f"Peak risk encountered: {req.peak_risk_score * 100:.0f}%",
        f"Weather: {req.weather_encountered}",
    ]
    
    if has_telemetry_issue:
        fallback_insights.append(f"⚠️ TELEMETRY ALERT: {'; '.join(telemetry_anomalies)}")
    
    fallback_recommendation = (
        "Investigate sensor/telematics system and schedule routine maintenance." if has_telemetry_issue
        else "Schedule routine maintenance." if maintenance_flag
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
            "telemetry_quality": "VALID" if not has_telemetry_issue else "DEGRADED",
            "telemetry_anomalies": telemetry_anomalies if has_telemetry_issue else None,
            "summary": fallback_summary,
            "key_insights": fallback_insights,
            "maintenance_flag": maintenance_flag,
            "maintenance_reason": ("Telemetry system failure - check sensors and vehicle diagnostics." if has_telemetry_issue 
                                  else "Heuristic: high risk or low efficiency" if maintenance_flag else None),
            "next_shipment_recommendation": fallback_recommendation,
            "ai_generated": False,
        }

    try:
        telemetry_status = "⚠️ DEGRADED - " + "; ".join(telemetry_anomalies) if has_telemetry_issue else "✅ VALID"
        
        prompt = f"""
SYSTEM ROLE: Senior Logistics Performance Analyst

You have just completed delivery analysis for a shipment. 
Generate a concise, professional post-delivery intelligence report in JSON.

⚠️ DATA QUALITY NOTICE: Telemetry Status = {telemetry_status}
📊 SIMULATION MODE: {"ACTIVE (Ignore physics violations/high speeds)" if req.is_simulation else "DISABLED (Real-world enforcement)"}

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

IMPORTANT: If telemetry is degraded (0 distance, 0 speed, etc.), acknowledge this in your analysis.
Do NOT extrapolate performance metrics from incomplete data.
Focus on timing-based assessment when telemetry is invalid.

TASK:
1. Write a 2–3 sentence professional SUMMARY of this delivery's performance.
2. List exactly 4 KEY INSIGHTS as short bullets (under 12 words each).
3. Assess if MAINTENANCE is needed and why (max 1 sentence). Include telematics check if applicable.
4. Write a NEXT_SHIPMENT_RECOMMENDATION (max 1 sentence).

OUTPUT SCHEMA (JSON ONLY, NO EXTRA TEXT):
{{
  "summary": "...",
  "key_insights": ["...", "...", "...", "..."],
  "maintenance_reason": "..." or null,
  "next_shipment_recommendation": "..."
}}
"""
        model_name = req.model_name or "gemini-1.5-flash"
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
                "telemetry_quality": "VALID" if not has_telemetry_issue else "DEGRADED",
                "telemetry_anomalies": telemetry_anomalies if has_telemetry_issue else None,
                "summary": ai_data.get("summary") or fallback_summary,
                "key_insights": ai_data.get("key_insights") or fallback_insights,
                "maintenance_flag": maintenance_flag,
                "maintenance_reason": ai_data.get("maintenance_reason"),
                "next_shipment_recommendation": ai_data.get("next_shipment_recommendation") or fallback_recommendation,
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
        "telemetry_quality": "VALID" if not has_telemetry_issue else "DEGRADED",
        "telemetry_anomalies": telemetry_anomalies if has_telemetry_issue else None,
        "summary": fallback_summary,
        "key_insights": fallback_insights,
        "maintenance_flag": maintenance_flag,
        "maintenance_reason": ("Telemetry system failure - check sensors and vehicle diagnostics." if has_telemetry_issue 
                              else "Heuristic: high risk or low efficiency" if maintenance_flag else None),
        "next_shipment_recommendation": fallback_recommendation,
        "ai_generated": False,
    }
