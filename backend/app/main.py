from fastapi import FastAPI

from app.api.routes import auth, orders

app = FastAPI(title="DentalFlow API")

app.include_router(auth.router)
app.include_router(orders.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
