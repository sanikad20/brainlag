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

from database import Base, engine, SessionLocal
from models import User

app = FastAPI()

# ----------------------------
# Create DB tables
# ----------------------------
Base.metadata.create_all(bind=engine)

# ----------------------------
# Password hashing (bcrypt)
# ----------------------------
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ----------------------------
# Schemas
# ----------------------------
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


# -------- LSTM schemas --------
class DailyLSTMInput(BaseModel):
    screen_time_hours: float
    work_screen_hours: float
    leisure_screen_hours: float
    sleep_hours: float
    sleep_quality_1_5: float
    social_hours_per_week: float
    productivity_0_100: float


class LSTMSequenceInput(BaseModel):
    sequence: List[DailyLSTMInput]


# ----------------------------
# Manual Model Architecture
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
# LSTM Model Architecture
# ----------------------------
class BurnoutLSTM(nn.Module):
    def __init__(self, input_size: int, hidden_size: int = 64):
        super().__init__()
        self.lstm = nn.LSTM(input_size, hidden_size, batch_first=True)
        self.fc1 = nn.Linear(hidden_size, 32)
        self.relu = nn.ReLU()
        self.dropout = nn.Dropout(0.2)
        self.fc2 = nn.Linear(32, 1)

    def forward(self, x):
        out, _ = self.lstm(x)
        out = out[:, -1, :]
        out = self.fc1(out)
        out = self.relu(out)
        out = self.dropout(out)
        out = self.fc2(out)
        return out


# ----------------------------
# Load Manual ML Model
# ----------------------------
with open("feature_cols.pkl", "rb") as f:
    feature_cols = pickle.load(f)

scaler = joblib.load("burnout_scaler.pkl")

model = BurnoutModel(n_features=len(feature_cols))

state_dict = torch.load(
    "best_burnout_model.pt",
    map_location="cpu",
    weights_only=True
)

model.load_state_dict(state_dict)
model.eval()


# ----------------------------
# Load LSTM Model
# ----------------------------
with open("lstm_feature_cols.pkl", "rb") as f:
    lstm_feature_cols = pickle.load(f)

lstm_scaler = joblib.load("lstm_scaler.pkl")

lstm_model = BurnoutLSTM(input_size=len(lstm_feature_cols))

lstm_state_dict = torch.load(
    "lstm_burnout_model.pt",
    map_location="cpu",
    weights_only=True
)

lstm_model.load_state_dict(lstm_state_dict)
lstm_model.eval()

LSTM_SEQ_LEN = 5


# ----------------------------
# Helper
# ----------------------------
def get_burnout_level(score: float) -> str:
    if score < 4:
        return "Low 🟢"
    elif score < 7:
        return "Moderate 🟠"
    return "High 🔴"


# ----------------------------
# Routes
# ----------------------------
@app.get("/")
def home():
    return {"message": "Backend is running"}


# ----------------------------
# Register
# ----------------------------
@app.post("/register")
def register(data: RegisterInput, db: Session = Depends(get_db)):
    existing_user = db.query(User).filter(User.email == data.email).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Email already registered")

    if len(data.password) > 72:
        raise HTTPException(
            status_code=400,
            detail="Password too long (max 72 characters)"
        )

    safe_password = data.password[:72]
    hashed_password = pwd_context.hash(safe_password)

    new_user = User(
        name=data.name,
        email=data.email,
        hashed_password=hashed_password
    )

    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    return {
        "message": "User registered successfully",
        "user": {
            "id": new_user.id,
            "name": new_user.name,
            "email": new_user.email
        }
    }


# ----------------------------
# Login
# ----------------------------
@app.post("/login")
def login(data: LoginInput, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == data.email).first()

    if not user:
        raise HTTPException(status_code=401, detail="Invalid email or password")

    safe_password = data.password[:72]

    if not pwd_context.verify(safe_password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    return {
        "message": "Login successful",
        "user": {
            "id": user.id,
            "name": user.name,
            "email": user.email
        }
    }


# ----------------------------
# Manual Prediction
# ----------------------------
@app.post("/predict")
def predict(data: BurnoutInput):
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

    prediction = float(np.clip(raw_output, 1, 10))
    level = get_burnout_level(prediction)

    return {
        "raw_prediction": round(raw_output, 4),
        "prediction": round(prediction, 2),
        "stress_level": level
    }


# ----------------------------
# Continuous LSTM Prediction
# ----------------------------
@app.post("/predict_lstm")
def predict_lstm(data: LSTMSequenceInput):
    if len(data.sequence) != LSTM_SEQ_LEN:
        raise HTTPException(
            status_code=400,
            detail=f"Exactly {LSTM_SEQ_LEN} days of input are required"
        )

    sequence_data = []
    for day in data.sequence:
        row_dict = {
            "screen_time_hours": day.screen_time_hours,
            "work_screen_hours": day.work_screen_hours,
            "leisure_screen_hours": day.leisure_screen_hours,
            "sleep_hours": day.sleep_hours,
            "sleep_quality_1_5": day.sleep_quality_1_5,
            "social_hours_per_week": day.social_hours_per_week,
            "productivity_0_100": day.productivity_0_100,
        }

        row = [float(row_dict[col]) for col in lstm_feature_cols]
        sequence_data.append(row)

    sequence_array = np.array(sequence_data, dtype=np.float32)
    sequence_scaled = lstm_scaler.transform(sequence_array)
    sequence_scaled = np.expand_dims(sequence_scaled, axis=0)

    input_tensor = torch.tensor(sequence_scaled, dtype=torch.float32)

    with torch.no_grad():
        raw_output = lstm_model(input_tensor).item()

    prediction = float(np.clip(raw_output, 1, 10))
    level = get_burnout_level(prediction)

    return {
        "raw_prediction": round(raw_output, 4),
        "prediction": round(prediction, 2),
        "stress_level": level
    }