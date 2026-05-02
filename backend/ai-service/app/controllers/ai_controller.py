import base64
import json
import traceback
from datetime import datetime
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
    
    # Global Stop Check
    try:
        sys_doc = db.collection("system").document("config").get()
        if sys_doc.exists and sys_doc.to_dict().get("isGlobalStopped"):
            logger.info("Skipping analysis: Global Stop is active.")
            return
    except Exception: pass

    if shipment_data.get("status") in ["STOPPED", "COMPLETED", "CANCELLED"]:
        return

    
    existing_ai = shipment_data.get("aiResponse", {})
    last_analyzed = existing_ai.get("last_analyzed")
    
    # Cooldown Logic
    if last_analyzed and msg_timestamp:
        try:
            msg_dt = datetime.fromisoformat(msg_timestamp.replace("Z", "+00:00"))
            if hasattr(last_analyzed, 'timestamp'):
                diff_seconds = msg_dt.timestamp() - last_analyzed.timestamp()
                if diff_seconds < 120 and existing_ai.get("risk_level") != "HIGH":
                    logger.info(f"Skipping analysis for {shipment_id} (Cooldown active)")
                    return
        except (ValueError, AttributeError): pass

    route_data = shipment_data.get("routeData", [])
    if not isinstance(route_data, list): route_data = [route_data]
    mode = shipment_data.get("vehicle_type", "ROAD")
    weather_data = shipment_data.get("weatherData", {})
    news_data = shipment_data.get("newsData", [])

    processed_routes = score_and_rank_routes(route_data, weather_data, mode)
    if not processed_routes: return

    best = next((r for r in processed_routes if r["is_recommended"]), processed_routes[0])
    current = processed_routes[0]
    
    # Semantic Caching
    prev_risk_level = existing_ai.get("risk_level")
    prev_risk_score = existing_ai.get("risk_score", 0)
    prev_insight = existing_ai.get("insight")
    
    should_call_gemini = True
    if prev_insight and prev_risk_level == best['risk_level']:
        score_diff = abs(best['risk_score'] - prev_risk_score)
        if score_diff < 0.15:
            prev_weather = existing_ai.get("cached_state", {}).get("weather_condition")
            curr_weather = (weather_data.get("condition") or "clear").lower()
            if prev_weather == curr_weather:
                should_call_gemini = False

    insight = prev_insight
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
            vehicle_health=shipment_data.get("vehicle_health", "Good")
        )
        insight = generate_logistics_insight(
            best['risk_score'], 
            f"{best['predicted_delay_mins']} mins", 
            input_data
        )


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

    doc_ref.update({
        "aiResponse": {
            "success": True,
            "risk_score": best['risk_score'],
            "risk_level": best['risk_level'],
            "delay_prediction": f"{best['predicted_delay_mins']} mins",
            "suggestion": f"Switch to {best['summary']} for optimal safety." if best is not current else "Maintain current optimal route.",
            "insight": insight,
            "optimization_data": optimization_data,
            "all_routes": processed_routes,
            "last_analyzed": firestore.SERVER_TIMESTAMP,
            "cached_state": {
                "weather_condition": (weather_data.get("condition") or "clear").lower(),
                "mode": mode
            }
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
        scored_routes = score_and_rank_routes(raw_routes, weather, mode)

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

        insight = generate_logistics_insight(
            best["risk_score"], 
            f"{best['predicted_delay_mins']} mins", 
            data
        )

        optimization_data = {
            "before": {
                "time": f"{scored_routes[0]['travel_time_min'] // 60}h {scored_routes[0]['travel_time_min'] % 60}m",
                "cost": scored_routes[0]['total_cost'],
                "fuel": scored_routes[0]['total_fuel']
            },
            "after": {
                "time": f"{best['travel_time_min'] // 60}h {best['travel_time_min'] % 60}m",
                "cost": best['total_cost'],
                "fuel": best['total_fuel']
            }
        }

        # Final structural alignment for Senior Architect requirements
        ai_insights = {
            "delay_probability": round(best["risk_score"] * 100, 1),
            "bottlenecks": [n['title'] for n in data.newsData[:2]] if data.newsData else ["No critical bottlenecks"],
            "recommendation": insight
        }

        return {
            "success": True,
            "risk_score": best["risk_score"],
            "risk_level": best["risk_level"],
            "delay_prediction": f"{best['predicted_delay_mins']} mins",
            "suggestion": f"Optimal {data.mode} route via '{best.get('summary', 'Main Route')}' selected.",
            "insight": insight,
            "ai_insights": ai_insights,
            "optimization_data": optimization_data,
            "all_routes": scored_routes
        }
    except Exception as e:
        logger.error(f"Prediction Error: {str(e)}")
        return {
            "success": True, "risk_score": 0.0, "risk_level": "LOW",
            "delay_prediction": "0 mins", "suggestion": "Proceed normally",
            "insight": "AI temporarily unavailable.", "all_routes": []
        }
