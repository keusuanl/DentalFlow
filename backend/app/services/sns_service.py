import json
import uuid

import boto3

from app.core.config import settings

sns_client = boto3.client("sns", region_name=settings.aws_region)


def publish_order_notification(order_id: uuid.UUID, event_type: str, patient_name: str) -> None:
    message = {
        "order_id": str(order_id),
        "event_type": event_type,
        "patient_name": patient_name,
    }
    sns_client.publish(
        TopicArn=settings.notification_topic_arn,
        Message=json.dumps(message),
        Subject=f"DentalFlow order {event_type}",
    )
