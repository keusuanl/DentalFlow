import uuid
from datetime import datetime, date

from pydantic import BaseModel


class OrderCreate(BaseModel):
    patient_name: str
    patient_dob: date
    patient_gender: str
    case_type: str
    notes: str | None = None


class OrderStatusUpdate(BaseModel):
    status: str


class OrderResponse(BaseModel):
    id: uuid.UUID
    patient_name: str
    patient_dob: date
    patient_gender: str
    case_type: str
    notes: str | None
    s3_object_key: str | None
    status: str
    dentist_id: uuid.UUID
    assigned_lab_tech_id: uuid.UUID | None
    created_at: datetime
    updated_at: datetime
    completed_at: datetime | None

    class Config:
        from_attributes = True
