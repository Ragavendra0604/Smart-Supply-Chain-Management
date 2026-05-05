import base64
import json
import traceback
from datetime import datetime, timezone
from typing import Optional
from fastapi import Request
from fastapi.responses import JSONResponse
from google.cloud import firestore
from app.models.firestore import db
from app.utils.logger import logger
from app.services.logistics_service import (
    InputData, 
    score_and_rank_routes, 
    generate_logistics_insight
)

async def handle_pubsub_event(request: Request):
    try:
        envelope = await request.json()
        if not envelope or "message" not in envelope:
            logger.error("Invalid Pub/Sub envelope received")
            return JSONResponse(status_code=200, content={"status": "invalid_envelope"})

        pubsub_message = envelope["message"]
        if "data" in pubsub_message:
            decoded_data = base64.b64decode(pubsub_message["data"]).decode("utf-8")
            try:
                payload = json.loads(decoded_data)
            except json.JSONDecodeError as decode_err:
                logger.error(f"Pub/Sub message is not valid JSON: {decode_err}")
                return JSONResponse(status_code=200, content={"status": "malformed_payload"})

            event_type = payload.get("eventType")
            data = payload.get("data", {})

            if event_type == "shipment.location_updated":
                shipment_id = data.get("shipment_id")
                msg_timestamp = payload.get("timestamp")
                if shipment_id:
                    await process_ai_analysis(shipment_id, msg_timestamp)

        return JSONResponse(status_code=200, content={"status": "success"})
    except Exception as e:
        logger.error(f"Pub/Sub Processing Error: {traceback.format_exc()}")
        return JSONResponse(status_code=500, content={"status": "error", "message": str(e)})

async def process_ai_analysis(shipment_id: str, msg_timestamp: Optional[str] = None):
    doc_ref = db.collection("shipments").document(shipment_id)
    shipment_snapshot = doc_ref.get()
    if not shipment_snapshot.exists:
        return
        
    shipment_data = shipment_snapshot.to_dict()
    
    # Global Stop Check (with simple in-memory cache to reduce costs)
    global_stop_cache = getattr(process_ai_analysis, "_global_stop_cache", {"value": False, "expiry": 0})
    now = datetime.now().timestamp()
    
    if now > global_stop_cache["expiry"]:
        try:
            sys_doc = db.collection("system").document("config").get()
            is_stopped = sys_doc.exists and sys_doc.to_dict().get("isGlobalStopped")
            global_stop_cache = {"value": is_stopped, "expiry": now + 60}
            process_ai_analysis._global_stop_cache = global_stop_cache
        except Exception: 
            pass

    if global_stop_cache["value"]:
        logger.info("Skipping analysis: Global Stop is active.")
        return

    if shipment_data.get("status") in ["STOPPED", "COMPLETED", "CANCELLED"]:
        return

    
    existing_ai = shipment_data.get("aiResponse", {})
    last_analyzed = existing_ai.get("last_analyzed")
    
    # --- DATA INTEGRITY: Out-of-order & Cooldown Logic ---
    if last_analyzed and msg_timestamp:
        try:
            msg_dt = datetime.fromisoformat(msg_timestamp.replace("Z", "+00:00"))
            last_dt = datetime.fromtimestamp(last_analyzed.timestamp(), tz=timezone.utc) if hasattr(last_analyzed, 'timestamp') else None
            
            if last_dt:
                diff_seconds = msg_dt.timestamp() - last_dt.timestamp()
                
                # 1. STALENESS GUARD: If message is older than last analysis, skip it.
                if diff_seconds < 0:
                    logger.info(f"Skipping analysis for {shipment_id}: Out-of-order event (Stale by {-diff_seconds:.1f}s)")
                    return
                
                # 2. COOLDOWN GUARD: Skip if analyzed very recently (60s), unless HIGH risk
                if diff_seconds < 60 and existing_ai.get("risk_level") != "HIGH":
                    logger.info(f"Skipping analysis for {shipment_id}: Cooldown active ({diff_seconds:.1f}s since last)")
                    return
        except Exception as integrity_err:
            logger.warning(f"Integrity check failed for {shipment_id}: {integrity_err}")

    route_data = shipment_data.get("routeData", [])
    if not isinstance(route_data, list): route_data = [route_data]
    mode = shipment_data.get("vehicle_type", "ROAD")
    weather_data = shipment_data.get("weatherData", {})
    news_data = shipment_data.get("newsData", [])

    processed_routes = score_and_rank_routes(
        route_data, 
        weather_data, 
        mode,
        fuel_level=shipment_data.get("fuel_level", 100.0),
        vehicle_health=shipment_data.get("vehicle_health", "Good"),
        news_data=news_data,
        traffic_level=weather_data.get("traffic_level") or 1.0,
        speed_modifier=shipment_data.get("simulation_speed_modifier") or 1.0
    )
    if not processed_routes: return

    best = next((r for r in processed_routes if r["is_recommended"]), processed_routes[0])
    current = processed_routes[0]
    
    # Semantic Caching DISABLED for MVP dynamic testing
    should_call_gemini = True
    insight = existing_ai.get("insight", "")
    suggestion = ""
    strategic_advisory = None
    
    if should_call_gemini:
        input_data = InputData(
            shipment_id=shipment_id,
            origin=shipment_data.get("origin", "Unknown"),
            destination=shipment_data.get("destination", "Unknown"),
            routeData=route_data,
            weatherData=weather_data,
            newsData=news_data,
            mode=mode,
            cargo_type=shipment_data.get("cargo_type", "General"),
            priority=shipment_data.get("priority", "Normal"),
            is_perishable=shipment_data.get("is_perishable", False),
            delivery_deadline=shipment_data.get("delivery_deadline"),
            fuel_level=shipment_data.get("fuel_level", 100.0),
            vehicle_health=shipment_data.get("vehicle_health", "Good"),
            model_name=shipment_data.get("ai_config", {}).get("model") or "gemini-2.5-flash"
        )
        # Optimization: Use summarized routes to save AI tokens
        input_data.routeData = processed_routes
        engine_data = generate_logistics_insight(
            best['risk_score'], 
            f"{best['predicted_delay_mins']} mins", 
            input_data
        )

        # --- STRATEGIC ADVISORY ENGINE (Advisory Only) ---
        analysis = engine_data.get("analysis", {})
        engine_insights = analysis.get("ai_insights", {})

        insight = engine_insights.get("recommendation", "Strategic evaluation complete.")
        suggestion = f"Strategic Decision: {engine_insights.get('decision', 'GO')}"
        
        # Strategic metadata for advanced UI layers (Optional visibility)
        strategic_advisory = {
            "risk_score": float(analysis.get("risk", {}).get("score", 0)),
            "delay_mins": float(analysis.get("time", {}).get("delay_minutes", 0)),
            "decision": engine_insights.get("decision", "GO"),
            "confidence": engine_insights.get("confidence", 0.9)
        }
    
    # --- DETERMINISTIC METRICS (Heuristic Source of Truth) ---
    optimization_data = {
        "before": {
            "time": f"{int(current['raw_duration_min'] // 60)}h {int(current['raw_duration_min'] % 60)}m",
            "cost": float(current['total_cost']),
            "fuel": float(current['total_fuel'])
        },
        "after": {
            "time": f"{int(best['travel_time_min'] // 60)}h {int(best['travel_time_min'] % 60)}m",
            "cost": float(best['total_cost']),
            "fuel": float(best['total_fuel'])
        }
    }

    result = {
        "success": True,
        "risk_score": best['risk_score'], # HEURISTIC TRUTH
        "risk_level": best['risk_level'],   # HEURISTIC TRUTH
        "delay_prediction": f"{int(best['predicted_delay_mins'])} mins", # HEURISTIC TRUTH
        "suggestion": suggestion if should_call_gemini else (f"Switch to {best['summary']} for optimal safety." if best is not current else "Maintain current optimal route."),
        "insight": insight,
        "strategic_advisory": strategic_advisory if should_call_gemini else None,
        "optimization_data": optimization_data,
        "all_routes": processed_routes,
        "last_analyzed": "SERVER_TIMESTAMP",
        "cached_state": {
            "weather_condition": (weather_data.get("condition") or "clear").lower(),
            "mode": mode
        }
    }
    
    # --- LOGGING: Concise View (Stripping path for readability) ---
    log_result = result.copy()
    if "all_routes" in log_result:
        log_result["all_routes"] = [{k: v for k, v in r.items() if k != 'path'} for r in log_result["all_routes"]]
    
    logger.info(f"--- BACKGROUND AI ANALYSIS [{shipment_id}] ---\n{json.dumps(log_result, indent=2, default=str)}")

    doc_ref.update({
        "aiResponse": {
            "success": True,
            "risk_score": best['risk_score'],
            "risk_level": best['risk_level'],
            "delay_prediction": f"{int(best['predicted_delay_mins'])} mins",
            "suggestion": result["suggestion"],
            "insight": result["insight"],
            "strategic_advisory": result.get("strategic_advisory"),
            "optimization_data": optimization_data,
            "all_routes": processed_routes,
            "last_analyzed": firestore.SERVER_TIMESTAMP,
            "cached_state": result["cached_state"]
        }
    })

def handle_predict(data: InputData):
    try:
        if data.shipment_id:
            doc = db.collection("shipments").document(data.shipment_id).get()
            if doc.exists:
                ship_data = doc.to_dict()
                existing_ai = ship_data.get("aiResponse", {})
                cached_state = existing_ai.get("cached_state", {})
                curr_weather = (data.weatherData or {}).get("condition", "clear").lower()
                
                if (existing_ai.get("success") and 
                    cached_state.get("weather_condition") == curr_weather and
                    cached_state.get("mode") == (data.mode or "ROAD")):
                    return {**existing_ai, "is_cached": True}

        raw_routes = data.routeData
        if not raw_routes: raw_routes = []
        elif not isinstance(raw_routes, list): raw_routes = [raw_routes]
            
        weather = data.weatherData or {}
        mode = data.mode or "ROAD"
        scored_routes = score_and_rank_routes(
            raw_routes, 
            weather, 
            mode,
            fuel_level=data.fuel_level if data.fuel_level is not None else 100.0,
            vehicle_health=data.vehicle_health or "Good",
            news_data=data.newsData,
            traffic_level=data.traffic_level or 1.0,
            speed_modifier=data.speed_modifier or 1.0
        )

        if not scored_routes:
            return {
                "success": True, "risk_score": 0.1, "risk_level": "LOW",
                "delay_prediction": "5 mins", "suggestion": "Proceed normally",
                "insight": "AI Fallback: No live route data received.", "all_routes": []
            }

        best = next((r for r in scored_routes if r["is_recommended"]), scored_routes[0])
        
        # Enrich data for /predict if shipment_id was provided
        if data.shipment_id:
            doc = db.collection("shipments").document(data.shipment_id).get()
            if doc.exists:
                ship_data = doc.to_dict()
                data.cargo_type = ship_data.get("cargo_type", data.cargo_type)
                data.priority = ship_data.get("priority", data.priority)
                data.is_perishable = ship_data.get("is_perishable", data.is_perishable)
                data.delivery_deadline = ship_data.get("delivery_deadline", data.delivery_deadline)
                data.fuel_level = ship_data.get("fuel_level", data.fuel_level)
                data.vehicle_health = ship_data.get("vehicle_health", data.vehicle_health)

        # --- STRATEGIC ENGINE PROCESSING ---
        # Optimization: Pass the summarized scored_routes to save tokens
        data.routeData = scored_routes 
        
        engine_data = generate_logistics_insight(
            best["risk_score"], 
            f"{best['predicted_delay_mins']} mins", 
            data
        )
        
        analysis = engine_data.get("analysis", {})
        engine_insights = analysis.get("ai_insights", {})
        engine_risk = analysis.get("risk", {})
        engine_time = analysis.get("time", {})

        # --- STRATEGIC ADVISORY ENGINE (Advisory Only) ---
        analysis = engine_data.get("analysis", {})
        engine_insights = analysis.get("ai_insights", {})
        
        # Strategic metadata for advanced UI layers
        strategic_advisory = {
            "risk_score": float(analysis.get("risk", {}).get("score", 0)),
            "delay_mins": float(analysis.get("time", {}).get("delay_minutes", 0)),
            "decision": engine_insights.get("decision", "GO"),
            "confidence": engine_insights.get("confidence", 0.9)
        }

        # --- DETERMINISTIC METRICS (Heuristic Source of Truth) ---
        # Optimization uses Heuristic scores for strict predictability
        optimization_data = {
            "before": {
                "time": f"{int(scored_routes[0]['raw_duration_min'] // 60)}h {int(scored_routes[0]['raw_duration_min'] % 60)}m",
                "cost": float(scored_routes[0]['total_cost']),
                "fuel": float(scored_routes[0]['total_fuel'])
            },
            "after": {
                "time": f"{int(best['travel_time_min'] // 60)}h {int(best['travel_time_min'] % 60)}m",
                "cost": float(best['total_cost']),
                "fuel": float(best['total_fuel'])
            }
        }

        # Unified AI Insights (Merging ML scores with Strategic Reasoning)
        ai_insights = {
            "delay_probability": round(analysis.get("time", {}).get("delay_probability", 0) * 100, 1),
            "bottlenecks": engine_insights.get("bottlenecks", []),
            "recommendation": engine_insights.get("recommendation", "Strategic evaluation complete.")
        }

        final_response = {
            "success": True,
            "risk_score": float(best["risk_score"]), # HEURISTIC TRUTH
            "risk_level": str(best["risk_level"]),   # HEURISTIC TRUTH
            "delay_prediction": f"{int(best['predicted_delay_mins'])} mins", # HEURISTIC TRUTH
            "suggestion": f"Strategic Decision: {engine_insights.get('decision', 'GO')}",
            "insight": engine_insights.get("recommendation", "Awaiting strategic insight..."),
            "ai_insights": ai_insights,
            "strategic_advisory": strategic_advisory,
            "optimization_data": optimization_data,
            "all_routes": scored_routes,
            "reasoning_timestamp": datetime.now(timezone.utc).isoformat()
        }
        
        # --- LOGGING: Concise View (Stripping path for readability) ---
        log_response = final_response.copy()
        if "all_routes" in log_response:
            log_response["all_routes"] = [{k: v for k, v in r.items() if k != 'path'} for r in log_response["all_routes"]]
        
        logger.info(f"--- SENIOR LOGISTICS ENGINE RESPONSE [{data.shipment_id or 'RAW'}] ---\n{json.dumps(log_response, indent=2, default=str)}")
        return final_response
    except Exception as e:
        logger.error(f"Prediction Error: {str(e)}")
        return {
            "success": True, "risk_score": 0.0, "risk_level": "LOW",
            "delay_prediction": "0 mins", "suggestion": "Proceed normally",
            "insight": "AI temporarily unavailable.", "all_routes": []
        }
