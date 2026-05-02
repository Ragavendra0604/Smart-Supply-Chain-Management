import os
from fastapi import FastAPI, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from google.oauth2 import id_token
from google.auth.transport import requests
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
    allow_headers=["Content-Type", "Authorization", "X-Trace-Id"],
)

# --- OIDC AUTH MIDDLEWARE ---
@app.middleware("http")
async def validate_oidc_token(request: Request, call_next):
    # Allow health check without auth
    if request.url.path == "/health":
        return await call_next(request)

    # In local development, skip validation if header is "dummy-local-token"
    auth_header = request.headers.get("Authorization")
    if os.environ.get("ENV") != "production" and auth_header == "Bearer dummy-local-token":
        return await call_next(request)

    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")

    token = auth_header.split(" ")[1]
    try:
        # Verify the OIDC token. The audience should be the service URL.
        # In Cloud Run, the audience is the service URL.
        # We can also verify that the 'iss' is accounts.google.com
        id_info = id_token.verify_oauth2_token(token, requests.Request())
        
        # Optionally verify the service account email if known
        # if id_info['email'] != expected_service_account:
        #     raise HTTPException(status_code=403, detail="Unauthorized service account")
            
        request.state.user = id_info
    except Exception as e:
        logger.error(f"OIDC Token Validation Failed: {e}")
        raise HTTPException(status_code=403, detail="Invalid OIDC token")

    return await call_next(request)

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
