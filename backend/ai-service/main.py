import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routes.api import router as api_router
from app.models.ml_model import load_ml_model
from app.utils.logger import logger

app = FastAPI(title="Smart Supply Chain AI Service")

# CORS Configuration
_raw_origins = os.environ.get(
    "ALLOWED_ORIGINS",
    "http://localhost:5000,http://localhost:3000,http://localhost:8080,https://ssm-sb.web.app,https://ssm-sb.firebaseapp.com"
)
_allowed_origins = [o.strip() for o in _raw_origins.split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_credentials=True,
    allow_methods=["POST", "GET"],
    allow_headers=["Content-Type", "Authorization"],
)

# Include Modular Routes
app.include_router(api_router)

@app.on_event("startup")
def startup_event():
    logger.info("AI Service starting up...")
    load_ml_model()

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8080))
    uvicorn.run(app, host="0.0.0.0", port=port)
