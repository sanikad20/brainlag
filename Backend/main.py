from fastapi import FastAPI
import torch
import torch.nn as nn
import pickle
import joblib
import numpy as np

app = FastAPI()

class BurnoutModel(nn.Module):
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(14, 64),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(64, 32),
            nn.ReLU(),
            nn.Dropout(0.2),
            nn.Linear(32, 1)
        )

    def forward(self, x):
        return self.net(x)

model = BurnoutModel()
state_dict = torch.load(
    "best_burnout_model.pt",
    map_location="cpu",
    weights_only=True
)
model.load_state_dict(state_dict)
model.eval()

# feature columns can use pickle
with open("feature_cols.pkl", "rb") as f:
    feature_cols = pickle.load(f)

# scaler should use joblib
scaler = joblib.load("burnout_scaler.pkl")

print("Feature columns:", feature_cols)

@app.get("/")
def home():
    return {
        "message": "Burnout prediction API is running",
        "expected_features": feature_cols
    }

@app.post("/predict")
def predict(data: dict):
    row = [float(data.get(col, 0)) for col in feature_cols]

    input_array = np.array([row], dtype=np.float32)
    input_scaled = scaler.transform(input_array)
    input_tensor = torch.tensor(input_scaled, dtype=torch.float32)

    with torch.no_grad():
        output = model(input_tensor)

    prediction = float(output.detach().cpu().numpy()[0][0])

    return {
        "prediction": prediction,
        "used_features": feature_cols,
        "input_row": row
    }