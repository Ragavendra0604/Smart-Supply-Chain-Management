from fastapi import APIRouter, Request
from app.services.logistics_service import InputData
from app.controllers.ai_controller import handle_pubsub_event, handle_predict

router = APIRouter()

@router.post("/pubsub/push")
async def pubsub_push(request: Request):
    return await handle_pubsub_event(request)

@router.post("/predict")
def predict(data: InputData):
    return handle_predict(data)

@router.get("/health")
def health():
    return {"status": "ok", "model_version": "v3-modular-xgboost-gemini"}
