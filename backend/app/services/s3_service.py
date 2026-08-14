import uuid

from app.core.aws_clients import s3_client
from app.core.config import settings

PRESIGNED_URL_EXPIRY_SECONDS = 900  # 15 minutes


def generate_upload_url(order_id: uuid.UUID, filename: str) -> tuple[str, str]:
    object_key = f"scans/{order_id}/{filename}"

    url = s3_client.generate_presigned_url(
        ClientMethod="put_object",
        Params={
            "Bucket": settings.s3_bucket_name,
            "Key": object_key,
        },
        ExpiresIn=PRESIGNED_URL_EXPIRY_SECONDS,
    )

    return url, object_key


def generate_download_url(object_key: str) -> str:
    return s3_client.generate_presigned_url(
        ClientMethod="get_object",
        Params={
            "Bucket": settings.s3_bucket_name,
            "Key": object_key,
        },
        ExpiresIn=PRESIGNED_URL_EXPIRY_SECONDS,
    )
