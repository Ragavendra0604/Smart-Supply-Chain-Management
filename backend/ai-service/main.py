from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, model_validator
from google import genai
from typing import List, Dict, Any, Optional
import google.auth
import json

app = FastAPI()

# -------- VALIDATION ERROR HANDLER --------
# Logs the exact field + error so 422s are instantly diagnosable in the console
@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    errors = exc.errors()
    print("VALIDATION ERROR on", request.url.path)
    for e in errors:
        print(f"   Field: {e.get('loc')} | Type: {e.get('type')} | Msg: {e.get('msg')}")
    try:
        body = await request.body()
        print(f"   Raw body (first 500 chars): {body[:500]}")
    except Exception:
        pass
    return JSONResponse(
        status_code=422,
        content={"detail": errors, "hint": "Check field types: routeData=array, weatherData=object, newsData=array"}
    )

# -------- AUTHENTICATION --------
credentials, project_id = google.auth.default(
    scopes=["https://www.googleapis.com/auth/cloud-platform"]
)

client = genai.Client(
    vertexai=True,
    project=project_id,
    location="us-central1"
)

# -------- INPUT MODEL --------
# All fields are Optional[...] = None so that Node.js sending `null`
# (instead of `{}` or `[]`) does NOT trigger a 422 validation error.
class InputData(BaseModel):
    routeData: Optional[Any] = None
    weatherData: Optional[Any] = None
    newsData: Optional[Any] = None
    currentLocation: Optional[Any] = None
    source: Optional[str] = None

    @model_validator(mode="after")
    def coerce_and_normalize(self):
        """
        Normalize incoming data regardless of sender format:
        - routeData: null→[], single dict→[dict], array→array (all valid)
        - Strips heavy 'path' polyline arrays (not needed for AI scoring)
        - weatherData/newsData: null→safe empty defaults
        """
        # --- routeData: handle null / single dict / array ---
        rd = self.routeData
        if rd is None:
            self.routeData = []
        elif isinstance(rd, dict):
            # Single route object — wrap in list
            self.routeData = [rd]
        elif not isinstance(rd, list):
            self.routeData = []

        # Strip heavy path arrays from each route
        self.routeData = [
            {k: v for k, v in r.items() if k != "path"}
            for r in self.routeData
            if isinstance(r, dict)
        ]

        # --- weatherData ---
        if self.weatherData is None or not isinstance(self.weatherData, dict):
            self.weatherData = {}

        # --- newsData ---
        if self.newsData is None:
            self.newsData = []

        return self

# -------- CONSTANTS --------
FUEL_CONSUMPTION_L_PER_KM = 0.3
FUEL_PRICE_USD = 1.20
DRIVING_COST_PER_HOUR = 25.0

# -------- HELPERS --------

def calculate_costs(distance_meters, duration_seconds):
    distance_km = (distance_meters or 0) / 1000.0
    duration_hours = (duration_seconds or 0) / 3600.0

    fuel = distance_km * FUEL_CONSUMPTION_L_PER_KM
    fuel_cost = fuel * FUEL_PRICE_USD
    time_cost = duration_hours * DRIVING_COST_PER_HOUR

    return {
        "fuel_liters": round(fuel, 1),
        "fuel_cost": round(fuel_cost, 2),
        "total_cost": round(fuel_cost + time_cost, 2),
        "distance_km": round(distance_km, 1)
    }


def calculate_risk(route: Dict[str, Any], weather: Dict[str, Any], news: List[Any]) -> float:
    """
    Multi-factor risk scoring combining:
    - Traffic delay ratio
    - Weather severity
    - Wind speed hazard
    - Temperature extremes
    - News disruption signals
    """
    base = route.get("duration_seconds") or 0
    traffic = route.get("traffic_duration_seconds") or base
    delay = traffic - base
    risk = 0.0

    # --- Traffic Delay ---
    if base > 0:
        delay_ratio = delay / base
        # Heavier weighting for traffic delays: max 0.45 from traffic
        risk += min(delay_ratio * 0.8, 0.45) 
    elif delay > 0:
        risk += min(delay / 1200.0, 0.45)

    # --- Weather Condition ---
    condition = (weather.get("condition") or "").lower()
    weather_risk_map = {
        "thunderstorm": 0.40,
        "storm": 0.35,
        "snow": 0.30,
        "blizzard": 0.40,
        "fog": 0.25,
        "rain": 0.20,
        "drizzle": 0.10,
        "haze": 0.10,
        "dust": 0.15,
        "sand": 0.15,
        "ash": 0.20,
        "squall": 0.25,
        "tornado": 0.50,
    }
    for key, val in weather_risk_map.items():
        if key in condition:
            risk += val
            break

    # --- Wind Speed ---
    wind_speed = float(weather.get("windSpeed") or 0)
    if wind_speed > 60:
        risk += 0.20
    elif wind_speed > 40:
        risk += 0.12
    elif wind_speed > 20:
        risk += 0.05

    # --- Temperature Extremes ---
    temp = float(weather.get("temperature") or 20)
    if temp > 45 or temp < -10:
        risk += 0.10
    elif temp > 38 or temp < 0:
        risk += 0.05

    # --- News Disruptions ---
    disruption_keywords = [
        "accident", "crash", "closure", "blocked", "strike",
        "flood", "protest", "evacuation", "disaster", "delay",
        "road closed", "highway shut", "bridge collapse"
    ]
    news_risk_count = 0
    for article in news:
        title = (article.get("title") or "").lower()
        if any(kw in title for kw in disruption_keywords):
            news_risk_count += 1

    if news_risk_count >= 3:
        risk += 0.25
    elif news_risk_count == 2:
        risk += 0.15
    elif news_risk_count == 1:
        risk += 0.08

    return round(min(risk, 1.0), 2)


def get_risk_level(risk: float) -> str:
    if risk > 0.65:
        return "HIGH"
    elif risk > 0.35:
        return "MEDIUM"
    return "LOW"


def format_news_for_prompt(news: List[Any]) -> str:
    if not news:
        return "No recent news disruptions reported."
    lines = []
    for i, article in enumerate(news[:5], 1):
        title = article.get("title", "Unknown")
        source = article.get("source", "Unknown")
        lines.append(f"  {i}. [{source}] {title}")
    return "\n".join(lines)


def format_routes_for_prompt(routes: List[Dict[str, Any]]) -> str:
    lines = []
    for i, route in enumerate(routes, 1):
        summary = route.get("summary", f"Route {i}")
        dist = route.get("distance_meters", 0) / 1000
        base_dur = route.get("duration_seconds", 0) // 60
        traffic_dur = route.get("traffic_duration_seconds", 0) // 60
        delay = traffic_dur - base_dur
        risk = route.get("risk_score", 0)
        cost = route.get("costs", {}).get("total_cost", 0)
        lines.append(
            f"  Route {i} via '{summary}': {dist:.1f} km, "
            f"Base={base_dur}min, Traffic={traffic_dur}min, "
            f"Delay={delay}min, Risk={risk}, Cost=${cost}"
        )
    return "\n".join(lines)


# -------- AI REASONING --------

def generate_ai_reasoning(
    scored_routes: List[Dict[str, Any]],
    best: Dict[str, Any],
    weather: Dict[str, Any],
    news: List[Any],
    source_city: str = "Unknown",
    current_loc_data: Any = None
) -> str:
    """
    Send full context (Weather API + Maps API + News API) to Gemini
    and get a detailed reasoning + recommendation.
    """
    try:
        route_text = format_routes_for_prompt(scored_routes)
        news_text = format_news_for_prompt(news)
        
        # Determine live position text
        current_loc = best.get("origin") or "In Transit"
        if isinstance(current_loc_data, dict) and "lat" in current_loc_data:
            current_loc = f"Coordinates {current_loc_data['lat']}, {current_loc_data['lng']}"

        weather_desc = (
            f"Condition: {weather.get('condition', 'Unknown')}, "
            f"Temp: {weather.get('temperature', '?')}°C, "
            f"Wind: {weather.get('windSpeed', '?')} km/h, "
            f"Humidity: {weather.get('humidity', '?')}%"
        )

        best_summary = best.get("summary", "Optimized Route")
        best_dist = (best.get("distance_meters", 0)) / 1000
        best_traffic_min = (best.get("traffic_duration_seconds", 0)) // 60
        best_risk = best.get("risk_score", 0)
        best_cost = best.get("costs", {}).get("total_cost", 0)
        best_fuel = best.get("costs", {}).get("fuel_liters", 0)

        # Explicit traffic summary for AI context
        traffic_status = "Significant congestion detected." if (best.get("traffic_duration_seconds", 0) - best.get("duration_seconds", 0)) > 600 else "Normal traffic flow."
        if (best.get("traffic_duration_seconds", 0) - best.get("duration_seconds", 0)) > 1800:
            traffic_status = "HEAVY TRAFFIC DELAYS: Major congestion on this route."

        prompt = f"""
You are an expert AI logistics analyst for a Smart Supply Chain Management system.

Your job is to analyze real-time data from three live APIs — Maps, Weather, and News —
and provide a clear, intelligent recommendation for the best delivery route.

=== MAPS API — Available Routes ===
{route_text}

=== WEATHER API — Current Conditions at Destination ===
{weather_desc}

=== NEWS API — Recent Disruptions & Events ===
{news_text}

=== JOURNEY CONTEXT ===
Fixed Origin (Source): {source_city}
Current Live Position: {current_loc}

=== TRAFFIC SUMMARY ===
{traffic_status}

=== SELECTED OPTIMIZED ROUTE ===
Route via '{best_summary}':
- Distance: {best_dist:.1f} km
- Travel Time (with traffic): {best_traffic_min} minutes
- Risk Score: {best_risk} ({get_risk_level(best_risk)} risk)
- Estimated Total Cost: ${best_cost}
- Fuel Consumption: {best_fuel} L

=== YOUR TASK ===
1. Explain WHY this route was selected as the best option, referencing the weather, traffic, and news data.
2. Identify any specific risks or hazards on the route (weather/news-based).
3. Give a concrete operational recommendation for the driver/logistics team.
4. If risk is HIGH, suggest a mitigation strategy (e.g., delay departure, take alternate route, extra stops).

Keep your response professional, clear, and actionable. Use 3-4 sentences maximum.
"""

        response = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt
        )

        return response.text.strip()

    except Exception as e:
        print(f"Gemini AI Error: {e}")
        return (
            f"Route via '{best.get('summary', 'selected route')}' was chosen based on "
            f"lowest combined risk score and estimated cost. "
            f"Current weather is {weather.get('condition', 'unknown')} — proceed with standard precautions."
        )


# -------- API --------

@app.post("/predict")
def predict(data: InputData):
    try:
        print("Incoming AI request")
        print(f"  Routes: {len(data.routeData)} | Weather: {bool(data.weatherData)} | News: {len(data.newsData)}")

        # -------- SAFE EXTRACTION (deep normalization) --------
        raw_routes = data.routeData if isinstance(data.routeData, list) else []
        weather = data.weatherData if isinstance(data.weatherData, dict) else {}
        raw_news = data.newsData if isinstance(data.newsData, list) else []

        # Normalize each route item to a plain dict
        routes = []
        for item in raw_routes:
            if isinstance(item, dict):
                routes.append(item)
            elif hasattr(item, "model_dump"):
                routes.append(item.model_dump())
            elif hasattr(item, "__dict__"):
                routes.append(vars(item))

        # Normalize each news item to a plain dict
        news = []
        for item in raw_news:
            if isinstance(item, dict):
                news.append(item)
            elif isinstance(item, str):
                news.append({"title": item, "source": "Unknown"})
            elif hasattr(item, "model_dump"):
                news.append(item.model_dump())
            elif hasattr(item, "__dict__"):
                news.append(vars(item))

        if len(routes) == 0:
            return {
                "success": False,
                "message": "No route data provided. Ensure origin/destination are set.",
                "risk_score": 0.0,
                "risk_level": "UNKNOWN",
                "delay_prediction": "0 mins",
                "suggestion": "Cannot analyze — no routes available.",
                "explanation": "No route data was received from the Maps API.",
            }

        # -------- SCORE EACH ROUTE --------
        scored_routes = []

        for route in routes:
            risk = calculate_risk(route, weather, news)
            costs = calculate_costs(
                route.get("distance_meters"),
                route.get("traffic_duration_seconds") or route.get("duration_seconds")
            )

            # Composite score: lower is better
            # Weighted: 40% cost + 60% risk (risk is more important for safety)
            score = (costs["total_cost"] / 200.0) + (risk * 3.0)

            scored_routes.append({
                **route,
                "risk_score": risk,
                "risk_level": get_risk_level(risk),
                "costs": costs,
                "score": score
            })

        # -------- SELECT BEST (lowest score = safest + cheapest) --------
        scored_routes.sort(key=lambda x: x["score"])

        best = scored_routes[0]
        current = scored_routes[0] if len(scored_routes) == 1 else scored_routes[-1]  # worst route as baseline

        # -------- GENERATE FULL AI REASONING --------
        explanation = generate_ai_reasoning(
            scored_routes, 
            best, 
            weather, 
            news, 
            source_city=data.source or "Unknown",
            current_loc_data=data.currentLocation
        )

        # -------- CALCULATE SAVINGS --------
        current_time_sec = current.get("traffic_duration_seconds") or current.get("duration_seconds") or 0
        best_time_sec = best.get("traffic_duration_seconds") or best.get("duration_seconds") or 0
        time_saved = round((current_time_sec - best_time_sec) / 60, 1)

        current_costs = calculate_costs(
            current.get("distance_meters"),
            current.get("traffic_duration_seconds") or current.get("duration_seconds")
        )
        cost_saved = round(current_costs["total_cost"] - best["costs"]["total_cost"], 2)

        # -------- DELAY PREDICTION --------
        best_base_sec = best.get("duration_seconds") or 0
        delay_mins = max(0, (best_time_sec - best_base_sec) // 60)

        # -------- RISK-BASED ALERT --------
        risk_level = best["risk_level"]
        if risk_level == "HIGH":
            suggestion = (
                f"⚠️ HIGH RISK: Route via '{best.get('summary')}' — "
                f"consider delaying departure or using alternate path. "
                f"Weather: {weather.get('condition', 'adverse')}."
            )
        elif risk_level == "MEDIUM":
            suggestion = (
                f"Route via '{best.get('summary')}' selected (save {time_saved} min, "
                f"${abs(cost_saved)}). Moderate risk — monitor conditions."
            )
        else:
            suggestion = (
                f"✅ Optimal route via '{best.get('summary')}' — "
                f"save {time_saved} min and ${abs(cost_saved)}. Low risk, proceed normally."
            )

        return {
            "success": True,
            "risk_score": best["risk_score"],
            "risk_level": risk_level,
            "delay_prediction": f"{delay_mins} mins",
            "suggestion": suggestion,
            "explanation": explanation,
            "optimization_data": {
                "before": {
                    "time": current.get("traffic_duration") or current.get("duration") or "--",
                    "cost": current_costs["total_cost"],
                    "fuel": current_costs["fuel_liters"]
                },
                "after": {
                    "time": best.get("traffic_duration") or best.get("duration") or "--",
                    "cost": best["costs"]["total_cost"],
                    "fuel": best["costs"]["fuel_liters"]
                }
            },
            "all_routes": [
                {
                    "route_id": r.get("route_id", f"route_{i}"),
                    "summary": r.get("summary", f"Route {i+1}"),
                    "distance_km": r["costs"]["distance_km"],
                    "travel_time_min": (r.get("traffic_duration_seconds") or 0) // 60,
                    "risk_score": r["risk_score"],
                    "risk_level": r["risk_level"],
                    "total_cost": r["costs"]["total_cost"],
                    "fuel_liters": r["costs"]["fuel_liters"],
                    "is_recommended": (i == 0)
                }
                for i, r in enumerate(scored_routes)
            ]
        }

    except Exception as e:
        print("AI SERVICE ERROR:", str(e))
        import traceback
        traceback.print_exc()
        return {
            "success": False,
            "error": str(e),
            "fallback": True,
            "risk_score": 0.0,
            "risk_level": "UNKNOWN",
            "delay_prediction": "0 mins",
            "suggestion": "AI analysis unavailable - fallback mode.",
            "explanation": f"System error during AI analysis: {str(e)}"
        }


@app.get("/health")
def health():
    return {"status": "ok", "service": "ai-service"}