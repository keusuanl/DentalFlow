from fastapi import FastAPI

from app.api.routes import auth

app = FastAPI(title="DentalFlow API")

app.include_router(auth.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
