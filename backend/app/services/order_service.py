import uuid
from datetime import datetime, timezone

from fastapi import HTTPException, status
from sqlalchemy.orm import Session

from app.db.models.order import Order
from app.db.models.user import User
from app.schemas.order import OrderCreate
from app.services.s3_service import generate_upload_url

# Per data-model.md lifecycle: pending_upload -> received -> in_fabrication -> completed
VALID_TRANSITIONS = {
    "pending_upload": {"received"},
    "received": {"in_fabrication"},
    "in_fabrication": {"completed"},
    "completed": set(),
}


def create_order(db: Session, order_in: OrderCreate, dentist: User) -> tuple[Order, str]:
    order = Order(
        patient_name=order_in.patient_name,
        patient_dob=order_in.patient_dob,
        patient_gender=order_in.patient_gender,
        case_type=order_in.case_type,
        notes=order_in.notes,
        dentist_id=dentist.id,
        status="pending_upload",
    )
    db.add(order)
    db.commit()
    db.refresh(order)

    upload_url, object_key = generate_upload_url(order.id, order_in.filename)
    order.s3_object_key = object_key
    db.commit()
    db.refresh(order)

    return order, upload_url


def get_orders_for_user(db: Session, current_user: User) -> list[Order]:
    if current_user.role == "dentist":
        return db.query(Order).filter(Order.dentist_id == current_user.id).all()

    if current_user.role == "lab_tech":
        return db.query(Order).filter(
            (Order.assigned_lab_tech_id.is_(None))
            | (Order.assigned_lab_tech_id == current_user.id)
        ).all()

    return []


def get_order_by_id(db: Session, order_id: uuid.UUID, current_user: User) -> Order:
    order = db.query(Order).filter(Order.id == order_id).first()

    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")

    if current_user.role == "dentist" and order.dentist_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")

    if current_user.role == "lab_tech" and order.assigned_lab_tech_id not in (None, current_user.id):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")

    return order


def update_order_status(
    db: Session, order_id: uuid.UUID, new_status: str, lab_tech: User
) -> Order:
    order = db.query(Order).filter(Order.id == order_id).first()
    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")

    allowed_next = VALID_TRANSITIONS.get(order.status, set())
    if new_status not in allowed_next:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Cannot transition order from '{order.status}' to '{new_status}'",
        )

    if new_status == "in_fabrication":
        order.assigned_lab_tech_id = lab_tech.id
    elif new_status == "completed":
        order.completed_at = datetime.now(timezone.utc)

    order.status = new_status
    db.commit()
    db.refresh(order)
    return order
