from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session
from passlib.context import CryptContext

import torch
import torch.nn as nn
import pickle
import joblib
import numpy as np

import tensorflow as tf

from database import Base, engine, SessionLocal
from models import User

app = FastAPI()
Base.metadata.create_all(bind=engine)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ─────────────────────────────────────────────────────────────────────────────
# Schemas
# ─────────────────────────────────────────────────────────────────────────────

class RegisterInput(BaseModel):
    name: str
    email: EmailStr
    password: str

class LoginInput(BaseModel):
    email: EmailStr
    password: str

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

class DayInput(BaseModel):
    screen_time_hours: float
    app_switches_per_hour: float
    unique_apps_per_day: float
    social_app_ratio: float
    work_app_ratio: float
    entertainment_ratio: float
    wellness_ratio: float
    sleep_hours: float
    sleep_quality: float
    exercise_min_per_week: float
    social_hours_per_week: float
    call_count: float
    missed_call_ratio: float
    sms_count: float

class TwoDayInput(BaseModel):
    day1: DayInput
    day2: DayInput


# ─────────────────────────────────────────────────────────────────────────────
# Manual PyTorch model — UNCHANGED
# ─────────────────────────────────────────────────────────────────────────────

class BurnoutModel(nn.Module):
    def __init__(self, n_features):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(n_features, 64), nn.ReLU(), nn.Dropout(0.2),
            nn.Linear(64, 32),         nn.ReLU(), nn.Dropout(0.1),
            nn.Linear(32, 1)
        )
    def forward(self, x):
        return self.net(x).squeeze(-1)

# manual_feature_cols.pkl = original 14-feature file (rename your old feature_cols.pkl)
with open("manual_feature_cols.pkl", "rb") as f:
    feature_cols = pickle.load(f)

scaler       = joblib.load("burnout_scaler.pkl")
manual_model = BurnoutModel(n_features=len(feature_cols))
manual_model.load_state_dict(
    torch.load("best_burnout_model.pt", map_location="cpu", weights_only=True))
manual_model.eval()


# ─────────────────────────────────────────────────────────────────────────────
# Keras LSTM — loaded as SavedModel (version-independent)
# ─────────────────────────────────────────────────────────────────────────────

# Load as SavedModel — no Keras version conflicts, no custom_objects needed
_saved = tf.saved_model.load("burnout_lstm_savedmodel")
_infer = _saved.signatures["serving_default"]

# Find the output key (usually "burnout_score" or "output_0")
_output_key = list(_infer.structured_outputs.keys())[0]
print(f"LSTM model loaded ✓  |  output key: '{_output_key}'")

lstm_scaler   = joblib.load("lstm_scaler.pkl")
lstm_baseline = joblib.load("baseline_stats.pkl")
lstm_feat_cols = joblib.load("lstm_feature_cols.pkl")  # 23-feature file from LSTM training

LSTM_FEATURE_COLS = [
    "screen_time_hours", "app_switches_per_hour", "unique_apps_per_day",
    "social_app_ratio", "work_app_ratio", "entertainment_ratio",
    "wellness_ratio", "weighted_app_burnout", "sleep_hours", "sleep_quality",
    "exercise_min_per_week", "social_hours_per_week", "call_count",
    "missed_call_ratio", "sms_count",
    "screen_time_delta", "app_switches_delta", "social_ratio_delta",
    "work_ratio_delta", "sleep_delta",
    "screen_time_zscore", "app_switches_zscore", "social_ratio_zscore",
]


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def get_burnout_level_manual(score: float) -> str:
    if score < 4:  return "Low 🟢"
    if score < 7:  return "Moderate 🟠"
    return "High 🔴"

def get_burnout_level_lstm(score: float) -> str:
    if score < 0.35:  return "Low Burnout 🟢"
    if score < 0.65:  return "Moderate Burnout 🟠"
    return "High Burnout 🔴"

def build_lstm_row(d: DayInput, baseline: dict) -> list:
    r = d.model_dump()
    r["weighted_app_burnout"] = float(np.clip(
        r["social_app_ratio"]    * 0.85
      + r["entertainment_ratio"] * 0.60
      - r["work_app_ratio"]      * 0.25
      - r["wellness_ratio"]      * 0.40, -1, 1))
    r["screen_time_delta"]   = r["screen_time_hours"]     - baseline["screen_time_hours"][0]
    r["app_switches_delta"]  = r["app_switches_per_hour"] - baseline["app_switches_per_hour"][0]
    r["social_ratio_delta"]  = r["social_app_ratio"]      - baseline["social_app_ratio"][0]
    r["work_ratio_delta"]    = r["work_app_ratio"]        - baseline["work_app_ratio"][0]
    r["sleep_delta"]         = r["sleep_hours"]           - baseline["sleep_hours"][0]
    r["screen_time_zscore"]  = r["screen_time_delta"]     / baseline["screen_time_hours"][1]
    r["app_switches_zscore"] = r["app_switches_delta"]    / baseline["app_switches_per_hour"][1]
    r["social_ratio_zscore"] = r["social_ratio_delta"]    / baseline["social_app_ratio"][1]
    return [r[c] for c in LSTM_FEATURE_COLS]


# ─────────────────────────────────────────────────────────────────────────────
# Routes
# ─────────────────────────────────────────────────────────────────────────────

@app.get("/")
def home():
    return {"message": "BrainLag backend is running"}

@app.post("/register")
def register(data: RegisterInput, db: Session = Depends(get_db)):
    if db.query(User).filter(User.email == data.email).first():
        raise HTTPException(status_code=400, detail="Email already registered")
    if len(data.password) > 72:
        raise HTTPException(status_code=400, detail="Password too long (max 72 characters)")
    new_user = User(
        name=data.name, email=data.email,
        hashed_password=pwd_context.hash(data.password[:72]),
    )
    db.add(new_user); db.commit(); db.refresh(new_user)
    return {"message": "User registered successfully",
            "user": {"id": new_user.id, "name": new_user.name, "email": new_user.email}}

@app.post("/login")
def login(data: LoginInput, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == data.email).first()
    if not user or not pwd_context.verify(data.password[:72], user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")
    return {"message": "Login successful",
            "user": {"id": user.id, "name": user.name, "email": user.email}}

# Manual prediction — completely unchanged
@app.post("/predict")
def predict(data: BurnoutInput):
    row_dict     = data.model_dump()
    row          = [float(row_dict[col]) for col in feature_cols]
    input_scaled = scaler.transform(np.array([row], dtype=np.float32))
    input_tensor = torch.tensor(input_scaled, dtype=torch.float32)
    with torch.no_grad():
        raw_output = manual_model(input_tensor).item()
    prediction = float(np.clip(raw_output, 1, 10))
    return {
        "raw_prediction": round(raw_output, 4),
        "prediction":     round(prediction, 2),
        "stress_level":   get_burnout_level_manual(prediction),
    }

# Continuous monitoring — SavedModel inference (no Keras version issues)
@app.post("/predict_lstm")
def predict_lstm(data: TwoDayInput):
    row1 = build_lstm_row(data.day1, lstm_baseline)
    row2 = build_lstm_row(data.day2, lstm_baseline)

    seq        = np.array([[row1, row2]], dtype=np.float32)  # (1, 2, 23)
    N, S, F    = seq.shape
    seq_scaled = lstm_scaler.transform(seq.reshape(N*S, F)).reshape(N, S, F)

    # Run inference via SavedModel signature
    input_tensor = tf.constant(seq_scaled, dtype=tf.float32)
    result       = _infer(sequence_input=input_tensor)
    score        = float(result[_output_key].numpy()[0][0])
    score        = float(np.clip(score, 0.0, 1.0))

    return {
        "prediction":   round(score, 4),
        "stress_level": get_burnout_level_lstm(score),
    }