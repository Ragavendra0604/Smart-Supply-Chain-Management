from pydantic import BaseModel, Field
from typing import Optional, List

class TacticalDecision(BaseModel):
    decision: str = Field(..., pattern="^(GO|REROUTE|NO_GO)$")
    sla_risk: bool
    confidence: int = Field(..., ge=0, le=100)
    reason: str = Field(..., max_length=500)
    action: str = Field(..., max_length=300)

class AIInsights(BaseModel):
    delay_probability: float
    bottlenecks: List[str]
    recommendation: str

class OptimizationPoint(BaseModel):
    time: str
    cost: float
    fuel: float

class OptimizationData(BaseModel):
    before: OptimizationPoint
    after: OptimizationPoint

class ScoredRoute(BaseModel):
    summary: str
    distance_km: float
    travel_time_min: float  # Float: includes float delay prediction addend
    total_cost: float
    total_fuel: float
    risk_level: str
    risk_score: float
    predicted_delay_mins: float
    is_recommended: bool
    path: List[dict]

class FullAIResponse(BaseModel):
    success: bool
    risk_score: float
    risk_level: str
    delay_prediction: str
    suggestion: str
    insight: str
    ai_insights: Optional[AIInsights] = None
    optimization_data: Optional[OptimizationData] = None
    all_routes: List[ScoredRoute]
    is_cached: Optional[bool] = False

# --- NEW SENIOR LOGISTICS ENGINE SCHEMAS ---

class RouteAnalysis(BaseModel):
    origin: Optional[str] = "Unknown"
    destination: Optional[str] = "Unknown"
    distance_km: Optional[float] = 0.0

class TrafficAnalysis(BaseModel):
    duration_minutes: Optional[float] = 0.0
    congestion_level: Optional[str] = "LOW"
    traffic_index: Optional[float] = 0.0

class WeatherAnalysis(BaseModel):
    condition: Optional[str] = "Clear"
    severity_index: Optional[float] = 0.1

class FuelAnalysis(BaseModel):
    fuel_price_per_litre: Optional[float] = 1.2
    consumption_kmpl: Optional[float] = 12.0
    fuel_cost: Optional[float] = 0.0

class CostingAnalysis(BaseModel):
    base_cost: Optional[float] = 100.0
    fuel_cost: Optional[float] = 0.0
    total_cost: Optional[float] = 100.0

class TimeAnalysis(BaseModel):
    estimated_minutes: Optional[float] = 0.0
    delay_minutes: Optional[float] = 0.0
    delay_probability: Optional[float] = 0.0

class RiskFactors(BaseModel):
    traffic: Optional[float] = 0.33
    weather: Optional[float] = 0.33
    route: Optional[float] = 0.33

class RiskAnalysis(BaseModel):
    score: Optional[float] = 0.0
    level: Optional[str] = "LOW"
    factors: Optional[RiskFactors] = None

class EngineAiInsights(BaseModel):
    decision: Optional[str] = "GO"
    confidence: Optional[float] = 1.0
    bottlenecks: Optional[List[str]] = []
    recommendation: Optional[str] = "Proceed normally."

class EngineAnalysis(BaseModel):
    route: Optional[RouteAnalysis] = None
    traffic: Optional[TrafficAnalysis] = None
    weather: Optional[WeatherAnalysis] = None
    fuel: Optional[FuelAnalysis] = None
    costing: Optional[CostingAnalysis] = None
    time: Optional[TimeAnalysis] = None
    risk: Optional[RiskAnalysis] = None
    ai_insights: Optional[EngineAiInsights] = None

class LogisticsEngineResponse(BaseModel):
    success: bool
    analysis: EngineAnalysis


# --- DELIVERY COMPLETION SCHEMAS ---

class DeliverySummaryRequest(BaseModel):
    shipment_id: str
    origin: Optional[str] = "Unknown"
    destination: Optional[str] = "Unknown"
    mode: Optional[str] = "ROAD"
    cargo_type: Optional[str] = "General"
    priority: Optional[str] = "Normal"
    is_perishable: Optional[bool] = False
    distance_km: Optional[float] = 0.0
    actual_duration_min: Optional[float] = 0.0
    planned_duration_min: Optional[float] = 0.0
    total_cost: Optional[float] = 0.0
    total_fuel: Optional[float] = 0.0
    avg_speed_kmh: Optional[float] = 0.0
    peak_risk_score: Optional[float] = 0.0
    weather_encountered: Optional[str] = "Clear"
    delays_mins: Optional[float] = 0.0
    news_disruptions: Optional[int] = 0
    model_name: Optional[str] = "gemini-2.5-flash"


class DeliverySummaryResponse(BaseModel):
    on_time: bool
    delay_variance_mins: float
    efficiency_rating: float   # 0.0–1.0
    performance_grade: str     # A / B / C / D
    summary: str               # Narrative paragraph
    key_insights: List[str]    # Bullet insights
    maintenance_flag: bool     # True if vehicle needs inspection
    maintenance_reason: Optional[str] = None
    next_shipment_recommendation: str
