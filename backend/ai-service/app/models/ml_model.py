import os
import joblib
import pandas as pd
from google.cloud import storage
from app.utils.logger import logger

_ml_model = None
MODEL_PATH = "delay_model.pkl"

def load_ml_model():
    global _ml_model
    try:
        # Try local first
        if os.path.exists(MODEL_PATH):
            _ml_model = joblib.load(MODEL_PATH)
            logger.info(f"Production XGBoost Model loaded from {MODEL_PATH}")
            return _ml_model
            
        # Try GCS fallback
        bucket_name = os.environ.get("MODEL_BUCKET", "logistics-models-prod")
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob("xgboost/delay_model_latest.pkl")
        blob.download_to_filename("/tmp/delay_model.pkl")
        
        _ml_model = joblib.load("/tmp/delay_model.pkl")
        logger.info("Production ML Model loaded from GCS")
    except Exception as e:
        logger.warning(f"ML Model Loading Warning: {e}. Falling back to None.")
        _ml_model = None
    return _ml_model

def get_ml_model():
    global _ml_model
    if _ml_model is None:
        return load_ml_model()
    return _ml_model
