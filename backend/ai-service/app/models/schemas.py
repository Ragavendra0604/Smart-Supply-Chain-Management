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
