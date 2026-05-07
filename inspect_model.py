import joblib
import pandas as pd
import os

MODEL_PATH = "delay_model.pkl"

if os.path.exists(MODEL_PATH):
    try:
        model = joblib.load(MODEL_PATH)
        print(f"Model type: {type(model)}")

        if hasattr(model, "feature_names_in_"):
            print(f"Feature names: {model.feature_names_in_}")
        elif hasattr(model, "get_booster"):
            print(f"Booster feature names: {model.get_booster().feature_names}")
        else:
            print("No feature names found in model.")

    except Exception as e:
        print(f"Error loading model: {e}")
else:
    print(f"Model not found at {MODEL_PATH}")
