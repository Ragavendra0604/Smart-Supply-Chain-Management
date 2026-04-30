import pandas as pd
import numpy as np
from xgboost import XGBRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, r2_score
import joblib
import datetime

def generate_professional_dataset(n=5000):
    """
    Generates a VC-grade logistics dataset with non-linear interactions
    representing real-world infrastructure failures.
    """
    np.random.seed(42)
    
    # 1. CORE FEATURES
    distance_km = np.random.uniform(10, 800, n)
    traffic_index = np.random.uniform(1.0, 4.5, n) # 1.0 = Free flow, 4.5 = Gridlock
    weather_severity = np.random.uniform(0, 10, n) # 0 = Clear, 10 = Hurricane/Blizzard
    
    # Time/Day context
    hour = np.random.randint(0, 24, n)
    day_of_week = np.random.randint(0, 7, n)
    is_holiday = np.random.choice([0, 1], size=n, p=[0.95, 0.05])
    
    # 2. NON-LINEAR DELAY LOGIC (The "Real World")
    # Base delay based on distance (noise-heavy)
    base_delay = distance_km * 0.01 + np.random.normal(0, 2, n)
    
    # Exponential traffic impact (1.0-2.0 is linear, 3.0+ is exponential)
    traffic_impact = np.where(traffic_index > 2.5, (traffic_index**2.2) * 5, traffic_index * 8)
    
    # Weather-Traffic Interaction (Rain makes traffic worse)
    interaction_impact = (weather_severity * traffic_index) * 1.5
    
    # Sudden Infrastructure Failures (Outliers/Black Swans)
    # 2% chance of a "major incident" (accident/closure) adding 60-180 mins
    incidents = np.random.choice([0, 1], size=n, p=[0.98, 0.02])
    incident_delay = incidents * np.random.uniform(60, 180, n)
    
    # Cyclical Time Impact (Rush hour peaks)
    rush_hour_impact = np.where(((hour >= 7) & (hour <= 9)) | ((hour >= 16) & (hour <= 19)), 
                                np.random.uniform(15, 45, n), 0)
    
    # 3. COMPUTE FINAL DELAY
    actual_delay = (
        base_delay + 
        traffic_impact + 
        interaction_impact + 
        rush_hour_impact + 
        incident_delay +
        (is_holiday * 30)
    )
    
    # Clip negatives
    actual_delay = np.maximum(actual_delay, 0)
    
    df = pd.DataFrame({
        'distance_km': distance_km,
        'traffic_index': traffic_index,
        'weather_severity': weather_severity,
        'hour': hour,
        'day_of_week': day_of_week,
        'is_holiday': is_holiday,
        'actual_delay': actual_delay
    })
    
    return df

# --- EXECUTION ---
print("🚀 Generating VC-Grade Logistics Dataset...")
df = generate_professional_dataset(10000)

# Save for reference
df.to_csv("logistics_realworld_v3.csv", index=False)

# Feature Engineering: Cyclical Hour encoding (Sin/Cos)
# This prevents the model from thinking 23 is "far" from 0
df['hour_sin'] = np.sin(2 * np.pi * df['hour'] / 24)
df['hour_cos'] = np.cos(2 * np.pi * df['hour'] / 24)

X = df.drop(['actual_delay', 'hour'], axis=1)
y = df['actual_delay']

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.15, random_state=42)

print("🤖 Training XGBoost Regressor (Handling non-linearities)...")
model = XGBRegressor(
    n_estimators=500,
    learning_rate=0.05,
    max_depth=6,
    subsample=0.8,
    colsample_bytree=0.8,
    n_jobs=-1
)

model.fit(X_train, y_train)

# --- VALIDATION ---
y_pred = model.predict(X_test)
mae = mean_absolute_error(y_test, y_pred)
r2 = r2_score(y_test, y_pred)

print(f"\n📊 Model Performance:")
print(f"   MAE: {mae:.2f} minutes")
print(f"   R2 Score: {r2:.4f} (Variance explained)")

# --- SAVE ---
joblib.dump(model, "delay_model_v3.pkl")
print("\n✅ Production Model v3 (XGBoost) saved.")
