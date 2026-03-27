from fastapi import FastAPI
from pydantic import BaseModel
import torch
import torch.nn as nn
import pickle
import joblib
import numpy as np

app = FastAPI()


# ----------------------------
# Input schema for Swagger/API
# ----------------------------
class BurnoutInput(BaseModel):
    sleep_hours: float
    sleep_quality: float
    app_switches_per_hour: float
    social_app_ratio: float
    productivity_ratio: float
    unique_apps_per_day: float
    call_count: float
    total_call_min: float
    missed_call_ratio: float
    sms_count: float
    sms_sent_ratio: float
    screen_time_hours: float
    exercise_min_per_week: float
    social_hours_per_week: float


# ----------------------------
# Model architecture
# ----------------------------
class BurnoutModel(nn.Module):
    def __init__(self, n_features: int):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(n_features, 64),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(64, 32),
            nn.ReLU(),
            nn.Dropout(0.1),
            nn.Linear(32, 1)
        )

    def forward(self, x):
        return self.net(x).squeeze(-1)


# ----------------------------
# Load feature columns
# ----------------------------
with open("feature_cols.pkl", "rb") as f:
    feature_cols = pickle.load(f)

print("Feature columns:", feature_cols)

# ----------------------------
# Load scaler
# ----------------------------
scaler = joblib.load("burnout_scaler.pkl")

# ----------------------------
# Load model weights
# ----------------------------
model = BurnoutModel(n_features=len(feature_cols))
state_dict = torch.load(
    "best_burnout_model.pt",
    map_location="cpu",
    weights_only=True
)
model.load_state_dict(state_dict)
model.eval()


@app.get("/")
def home():
    return {
        "message": "Burnout prediction API is running",
        "expected_features": feature_cols
    }


@app.post("/predict")
def predict(data: BurnoutInput):
    # Build row in exact feature order
    row_dict = {
        "sleep_hours": data.sleep_hours,
        "sleep_quality": data.sleep_quality,
        "app_switches_per_hour": data.app_switches_per_hour,
        "social_app_ratio": data.social_app_ratio,
        "productivity_ratio": data.productivity_ratio,
        "unique_apps_per_day": data.unique_apps_per_day,
        "call_count": data.call_count,
        "total_call_min": data.total_call_min,
        "missed_call_ratio": data.missed_call_ratio,
        "sms_count": data.sms_count,
        "sms_sent_ratio": data.sms_sent_ratio,
        "screen_time_hours": data.screen_time_hours,
        "exercise_min_per_week": data.exercise_min_per_week,
        "social_hours_per_week": data.social_hours_per_week,
    }

    row = [float(row_dict[col]) for col in feature_cols]

    input_array = np.array([row], dtype=np.float32)
    input_scaled = scaler.transform(input_array)
    input_tensor = torch.tensor(input_scaled, dtype=torch.float32)

    with torch.no_grad():
        raw_output = model(input_tensor).item()

    # Match notebook behavior: clip to 1-10
    prediction = float(np.clip(raw_output, 1, 10))

    if prediction < 4:
        level = "Low 🟢"
    elif prediction < 7:
        level = "Moderate 🟠"
    else:
        level = "High 🔴"

    return {
        "raw_prediction": round(raw_output, 4),
        "prediction": round(prediction, 2),
        "stress_level": level
    }