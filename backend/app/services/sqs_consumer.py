import asyncio
import json
import re
import uuid

import boto3

from app.core.config import settings
from app.db.base import SessionLocal
from app.db.models.order import Order
from app.db.models.user import User
from app.services.sns_service import publish_order_notification

sqs_client = boto3.client("sqs", region_name=settings.aws_region)

# Matches: scans/{order_id}/{filename}
OBJECT_KEY_PATTERN = re.compile(r"^scans/([0-9a-fA-F-]{36})/")

POLL_WAIT_SECONDS = 10  # long-polling wait time


def _process_message(body: dict) -> None:
    for record in body.get("Records", []):
        object_key = record["s3"]["object"]["key"]
        match = OBJECT_KEY_PATTERN.match(object_key)
        if not match:
            continue

        order_id = uuid.UUID(match.group(1))
        db = SessionLocal()
        try:
            order = db.query(Order).filter(Order.id == order_id).first()
            if order and order.status == "pending_upload":
                order.status = "received"
                db.commit()
                publish_order_notification(order.id, "received", order.patient_name)
        finally:
            db.close()


def _poll_once() -> None:
    response = sqs_client.receive_message(
        QueueUrl=settings.upload_queue_url,
        MaxNumberOfMessages=10,
        WaitTimeSeconds=POLL_WAIT_SECONDS,
    )

    for message in response.get("Messages", []):
        try:
            body = json.loads(message["Body"])
            _process_message(body)
        finally:
            sqs_client.delete_message(
                QueueUrl=settings.upload_queue_url,
                ReceiptHandle=message["ReceiptHandle"],
            )


async def sqs_poll_loop() -> None:
    while True:
        await asyncio.to_thread(_poll_once)
