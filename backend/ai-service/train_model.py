import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, mean_squared_error
import joblib
import os

# 1. Generate Synthetic Dataset (50-100 rows as requested, using 200 for better stability)
def generate_data(n=200):
    np.random.seed(42)
    data = {
        'traffic_level': np.random.randint(0, 6, n),  # 0: None, 5: Jam
        'weather_condition': np.random.randint(0, 5, n), # 0: Clear, 1: Rain, 2: Snow, 3: Fog, 4: Storm
        'distance_km': np.random.uniform(10, 300, n),
        'time_of_day': np.random.randint(0, 24, n),
        'day_of_week': np.random.randint(0, 7, n)
    }
    df = pd.DataFrame(data)
    
    # Synthetic delay logic (Real-world patterns)
    # 1. Distance base delay (assuming 80km/h avg, so ~0.75 min/km)
    delay = df['distance_km'] * 0.1 
    
    # 2. Traffic Multiplier
    delay += df['traffic_level'] * 12
    
    # 3. Weather impact
    delay += df['weather_condition'] * 8
    
    # 4. Peak Hour impact (07:00-09:00 and 16:00-19:00)
    delay += np.where(((df['time_of_day'] >= 7) & (df['time_of_day'] <= 9)) | 
                     ((df['time_of_day'] >= 16) & (df['time_of_day'] <= 19)), 25, 0)
    
    # 5. Weekend vs Weekday
    delay += np.where(df['day_of_week'] >= 5, -5, 5) # Slightly faster on weekends
    
    # 6. Add Noise
    delay += np.random.normal(0, 3, n)
    
    df['delay_minutes'] = delay.clip(lower=0)
    
    return df

def train_and_save():
    print("--- Starting ML Pipeline ---")
    df = generate_data(200)
    print(f"Generated {len(df)} rows of synthetic logistics data.")
    
    # Features & Target
    X = df.drop('delay_minutes', axis=1)
    y = df['delay_minutes']
    
    # Split
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    
    # Model: RandomForestRegressor (Robust for tabular data)
    model = RandomForestRegressor(n_estimators=100, max_depth=10, random_state=42)
    model.fit(X_train, y_train)
    
    # Evaluation
    predictions = model.predict(X_test)
    mae = mean_absolute_error(y_test, predictions)
    rmse = np.sqrt(mean_squared_error(y_test, predictions))
    
    print(f"Evaluation Metrics:")
    print(f"  MAE: {mae:.2f} minutes")
    print(f"  RMSE: {rmse:.2f} minutes")
    
    # Save Model
    model_path = 'delay_model.pkl'
    joblib.dump(model, model_path)
    print(f"Model saved successfully to {model_path}")
    
    # Save a sample for testing
    df.head(10).to_csv('synthetic_logistics_data.csv', index=False)
    print("Sample data saved to synthetic_logistics_data.csv")

if __name__ == "__main__":
    train_and_save()
