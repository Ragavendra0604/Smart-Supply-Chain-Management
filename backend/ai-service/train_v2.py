import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, mean_squared_error
import joblib
import os

# 1. GENERATE SYNTHETIC DATASET (1000 rows for better training)
def generate_data(n=1000):
    np.random.seed(42)
    
    # Features
    traffic_level = np.random.randint(0, 6, n)  # 0: None, 5: Gridlock
    weather_condition = np.random.randint(0, 5, n) # 0: Clear, 1: Rain, 2: Snow, 3: Fog, 4: Storm
    distance_km = np.random.uniform(5, 500, n)
    time_of_day = np.random.randint(0, 24, n)
    day_of_week = np.random.randint(0, 7, n)
    
    # Target: Delay in minutes
    # Logic: 
    # - Base delay is 0
    # - Traffic adds 5-15 mins per level
    # - Weather adds 10-30 mins per level
    # - Distance adds 0.05 mins per km (noise)
    # - Peak hours (8-10, 16-19) add 20 mins
    
    delay = (
        (traffic_level * 12) + 
        (weather_condition * 15) + 
        (distance_km * 0.02) + 
        (np.where(((time_of_day >= 8) & (time_of_day <= 10)) | ((time_of_day >= 16) & (time_of_day <= 19)), 25, 0)) +
        np.random.normal(0, 5, n) # Random noise
    )
    
    # Ensure no negative delay
    delay = np.maximum(delay, 0)
    
    df = pd.DataFrame({
        'traffic_level': traffic_level,
        'weather_condition': weather_condition,
        'distance_km': distance_km,
        'time_of_day': time_of_day,
        'day_of_week': day_of_week,
        'delay_mins': delay
    })
    
    return df

# 2. PREPROCESSING & TRAINING
print("Generating synthetic logistics dataset...")
data = generate_data(2000)
data.to_csv("synthetic_logistics_data_v2.csv", index=False)

X = data.drop('delay_mins', axis=1)
y = data['delay_mins']

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

print("Training RandomForestRegressor...")
model = RandomForestRegressor(n_estimators=100, random_state=42)
model.fit(X_train, y_train)

# 3. EVALUATION
y_pred = model.predict(X_test)
mae = mean_absolute_error(y_test, y_pred)
rmse = np.sqrt(mean_squared_error(y_test, y_pred))

print(f"Model Evaluation:")
print(f"  MAE: {mae:.2f} mins")
print(f"  RMSE: {rmse:.2f} mins")

# 4. SAVE MODEL
MODEL_PATH = "delay_model.pkl"
joblib.dump(model, MODEL_PATH)
print(f"✅ Model saved to {MODEL_PATH}")

# 5. PREDICTION FUNCTION (Demo)
def predict_delay(traffic, weather, dist, time, day):
    features = pd.DataFrame([{
        'traffic_level': traffic,
        'weather_condition': weather,
        'distance_km': dist,
        'time_of_day': time,
        'day_of_week': day
    }])
    return model.predict(features)[0]

print(f"Demo Prediction (Heavy Traffic, Storm, 100km, 5PM): {predict_delay(5, 4, 100, 17, 1):.2f} mins")
