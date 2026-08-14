import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.routes import auth, orders
from app.services.sqs_consumer import sqs_poll_loop


@asynccontextmanager
async def lifespan(app: FastAPI):
    task = asyncio.create_task(sqs_poll_loop())
    yield
    task.cancel()


app = FastAPI(title="DentalFlow API", lifespan=lifespan)

app.include_router(auth.router)
app.include_router(orders.router)


@app.get("/health")
def health_check():
    return {"status": "ok"}
