from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

class InputData(BaseModel):
    value: float

@app.get("/")
def root():
    return {"status": "AegisGPU operational"}

@app.post("/predict")
def predict(data: InputData):
    result = data.value * 2
    return {"prediction": result}
