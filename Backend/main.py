
from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session
from passlib.context import CryptContext

import torch
import torch.nn as nn
import pickle
import joblib
import numpy as np
from typing import List

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

# Manual model input — unchanged
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

# One day of usage data
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

# NEW: 7-day history + today for personalised LSTM
class PersonalisedPredictInput(BaseModel):
    history: List[DayInput]  # exactly 7 days, oldest first
    today: DayInput


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

with open("manual_feature_cols.pkl", "rb") as f:
    manual_feature_cols = pickle.load(f)

manual_scaler = joblib.load("burnout_scaler.pkl")
manual_model  = BurnoutModel(n_features=len(manual_feature_cols))
manual_model.load_state_dict(
    torch.load("best_burnout_model.pt", map_location="cpu", weights_only=True))
manual_model.eval()


# ─────────────────────────────────────────────────────────────────────────────
# Personalised LSTM — 7-day baseline → today's burnout
# ─────────────────────────────────────────────────────────────────────────────

_lstm_saved      = tf.saved_model.load("burnout_lstm_savedmodel")
_lstm_infer      = _lstm_saved.signatures["serving_default"]
_output_key      = list(_lstm_infer.structured_outputs.keys())[0]

day_scaler       = joblib.load("lstm_day_scaler.pkl")
today_scaler     = joblib.load("lstm_today_scaler.pkl")
DAY_FEATURES     = joblib.load("lstm_day_features.pkl")
TODAY_FEATURES   = joblib.load("lstm_today_features.pkl")
SEQ_LEN          = joblib.load("lstm_seq_len.pkl")   # 7

print(f"LSTM loaded ✓  |  seq_len={SEQ_LEN}  |  output key: '{_output_key}'")


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def get_burnout_level_manual(score: float) -> str:
    if score < 4:  return "Low 🟢"
    if score < 7:  return "Moderate 🟠"
    return "High 🔴"

def get_burnout_level_lstm(score_01: float) -> str:
    """score_01 is 0–1 from sigmoid; convert to level."""
    if score_01 < 0.35:  return "Low 🟢"
    if score_01 < 0.65:  return "Moderate 🟠"
    return "High 🔴"

def compute_user_baseline(history: List[DayInput]) -> dict:
    """Compute per-user baseline from their 7-day history."""
    def vals(attr): return [getattr(d, attr) for d in history]
    def safe_std(v): return max(float(np.std(v)), 1e-6)

    screens  = vals("screen_time_hours")
    switches = vals("app_switches_per_hour")
    socials  = vals("social_app_ratio")
    works    = vals("work_app_ratio")
    sleeps   = vals("sleep_hours")

    return {
        "mean_screen":   float(np.mean(screens)),
        "std_screen":    safe_std(screens),
        "p75_screen":    float(np.percentile(screens, 75)),
        "mean_switches": float(np.mean(switches)),
        "std_switches":  safe_std(switches),
        "p75_switches":  float(np.percentile(switches, 75)),
        "mean_social":   float(np.mean(socials)),
        "std_social":    safe_std(socials),
        "p75_social":    float(np.percentile(socials, 75)),
        "mean_work":     float(np.mean(works)),
        "mean_sleep":    float(np.mean(sleeps)),
        "std_sleep":     safe_std(sleeps),
    }

def weighted_app_burnout(d: DayInput) -> float:
    return float(np.clip(
        d.social_app_ratio    * 0.85
      + d.entertainment_ratio * 0.60
      - d.work_app_ratio      * 0.25
      - d.wellness_ratio      * 0.40,
      -1.0, 1.0))

def day_to_raw_features(d: DayInput) -> list:
    wab = weighted_app_burnout(d)
    return [
        d.screen_time_hours, d.app_switches_per_hour, d.unique_apps_per_day,
        d.social_app_ratio, d.work_app_ratio, d.entertainment_ratio,
        d.wellness_ratio, wab, d.sleep_hours, d.sleep_quality,
        d.exercise_min_per_week, d.social_hours_per_week,
        d.call_count, d.missed_call_ratio, d.sms_count,
    ]

def build_today_features(today: DayInput, baseline: dict) -> list:
    """Build today's full feature vector with personalised deviations."""
    raw = day_to_raw_features(today)

    d_screen = today.screen_time_hours    - baseline["mean_screen"]
    d_switch = today.app_switches_per_hour- baseline["mean_switches"]
    d_social = today.social_app_ratio     - baseline["mean_social"]
    d_work   = today.work_app_ratio       - baseline["mean_work"]
    d_sleep  = today.sleep_hours          - baseline["mean_sleep"]

    z_screen = d_screen / baseline["std_screen"]
    z_switch = d_switch / baseline["std_switches"]
    z_social = d_social / baseline["std_social"]

    ex_screen = 1.0 if today.screen_time_hours     > baseline["p75_screen"]   else 0.0
    ex_social = 1.0 if today.social_app_ratio      > baseline["p75_social"]   else 0.0
    ex_switch = 1.0 if today.app_switches_per_hour > baseline["p75_switches"] else 0.0

    trend_screen = d_screen / max(baseline["mean_screen"],  1e-6)
    trend_social = d_social / max(baseline["mean_social"],  1e-6)

    deviation = [
        d_screen, d_switch, d_social, d_work, d_sleep,
        z_screen, z_switch, z_social,
        ex_screen, ex_social, ex_switch,
        trend_screen, trend_social,
    ]
    return raw + deviation


# ─────────────────────────────────────────────────────────────────────────────
# Routes
# ─────────────────────────────────────────────────────────────────────────────

@app.get("/")
def home():
    return {"message": "BrainLag backend running"}

@app.post("/register")
def register(data: RegisterInput, db: Session = Depends(get_db)):
    if db.query(User).filter(User.email == data.email).first():
        raise HTTPException(400, "Email already registered")
    if len(data.password) > 72:
        raise HTTPException(400, "Password too long")
    new_user = User(name=data.name, email=data.email,
                    hashed_password=pwd_context.hash(data.password[:72]))
    db.add(new_user); db.commit(); db.refresh(new_user)
    return {"message": "Registered", "user": {"id": new_user.id, "name": new_user.name}}

@app.post("/login")
def login(data: LoginInput, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == data.email).first()
    if not user or not pwd_context.verify(data.password[:72], user.hashed_password):
        raise HTTPException(401, "Invalid credentials")
    return {"message": "Login successful",
            "user": {"id": user.id, "name": user.name, "email": user.email}}

# Manual prediction — unchanged
@app.post("/predict")
def predict(data: BurnoutInput):
    row     = [float(data.dict()[c]) for c in manual_feature_cols]
    scaled  = manual_scaler.transform(np.array([row], dtype=np.float32))
    tensor  = torch.tensor(scaled, dtype=torch.float32)
    with torch.no_grad():
        raw = manual_model(tensor).item()
    score = float(np.clip(raw, 1, 10))
    return {
        "raw_prediction": round(raw, 4),
        "prediction":     round(score, 2),
        "stress_level":   get_burnout_level_manual(score),
    }

# NEW: Personalised LSTM — 7-day history → today's burnout
@app.post("/predict_lstm")
def predict_lstm(data: PersonalisedPredictInput):
    if len(data.history) != SEQ_LEN:
        raise HTTPException(400,
            f"history must have exactly {SEQ_LEN} days, got {len(data.history)}")

    # 1. Compute per-user baseline from their 7-day history
    baseline = compute_user_baseline(data.history)

    # 2. Build history matrix (7, 15)
    hist_rows = np.array(
        [day_to_raw_features(d) for d in data.history],
        dtype=np.float32)

    # 3. Build today vector with personalised deviations (28,)
    today_vec = np.array(
        build_today_features(data.today, baseline),
        dtype=np.float32)

    # 4. Scale
    hist_scaled  = day_scaler.transform(hist_rows)           # (7, 15)
    today_scaled = today_scaler.transform(today_vec.reshape(1,-1))  # (1, 28)

    # 5. Reshape for model
    hist_tensor  = tf.constant(hist_scaled.reshape(1, SEQ_LEN, len(DAY_FEATURES)),
                               dtype=tf.float32)
    today_tensor = tf.constant(today_scaled, dtype=tf.float32)

    # 6. Infer
    result  = _lstm_infer(history_input=hist_tensor, today_input=today_tensor)
    score01 = float(result[_output_key].numpy()[0][0])
    score01 = float(np.clip(score01, 0.0, 1.0))

    # Convert 0–1 → 1–10 to match manual model
    score10 = round(1 + score01 * 9, 1)

    return {
        "prediction":   score10,          # 1–10
        "score_raw":    round(score01, 4), # 0–1
        "stress_level": get_burnout_level_lstm(score01),
        # Also return personalised baseline so Flutter can show it
        "user_baseline": {
            "avg_screen_time":   round(baseline["mean_screen"],   2),
            "avg_app_switches":  round(baseline["mean_switches"],  1),
            "avg_social_ratio":  round(baseline["mean_social"],   3),
            "avg_work_ratio":    round(baseline["mean_work"],     3),
            "threshold_screen":  round(baseline["p75_screen"],    2),
            "threshold_switches":round(baseline["p75_switches"],  1),
            "threshold_social":  round(baseline["p75_social"],    3),
        }
    }
