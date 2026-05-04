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
    travel_time_min: int
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
    origin: str
    destination: str
    distance_km: float

class TrafficAnalysis(BaseModel):
    duration_minutes: float
    congestion_level: str = Field(..., pattern="^(LOW|MEDIUM|HIGH)$")
    traffic_index: float = Field(..., ge=0, le=1)

class WeatherAnalysis(BaseModel):
    condition: str
    severity_index: float = Field(..., ge=0, le=1)

class FuelAnalysis(BaseModel):
    fuel_price_per_litre: float
    consumption_kmpl: float
    fuel_cost: float

class CostingAnalysis(BaseModel):
    base_cost: float
    fuel_cost: float
    total_cost: float

class TimeAnalysis(BaseModel):
    estimated_minutes: float
    delay_probability: float = Field(..., ge=0, le=1)

class RiskFactors(BaseModel):
    traffic: float
    weather: float
    route: float

class RiskAnalysis(BaseModel):
    score: float
    level: str = Field(..., pattern="^(LOW|MEDIUM|HIGH)$")
    factors: RiskFactors

class EngineAiInsights(BaseModel):
    decision: str = Field(..., pattern="^(GO|HOLD|REROUTE)$")
    confidence: float = Field(..., ge=0, le=1)
    bottlenecks: List[str]
    recommendation: str

class EngineAnalysis(BaseModel):
    route: RouteAnalysis
    traffic: TrafficAnalysis
    weather: WeatherAnalysis
    fuel: FuelAnalysis
    costing: CostingAnalysis
    time: TimeAnalysis
    risk: RiskAnalysis
    ai_insights: EngineAiInsights

class LogisticsEngineResponse(BaseModel):
    success: bool
    analysis: EngineAnalysis
