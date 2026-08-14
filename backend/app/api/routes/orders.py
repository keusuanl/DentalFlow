import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_role
from app.db.base import get_db
from app.db.models.user import User
from app.schemas.order import OrderCreate, OrderCreateResponse, OrderResponse, OrderStatusUpdate
from app.services.order_service import (
    create_order,
    get_orders_for_user,
    get_order_by_id,
    update_order_status,
    get_download_url_for_order,
)

router = APIRouter(prefix="/orders", tags=["orders"])


@router.post("", response_model=OrderCreateResponse, status_code=201)
def create_new_order(
    order_in: OrderCreate,
    db: Session = Depends(get_db),
    dentist: User = Depends(require_role("dentist")),
):
    order, upload_url = create_order(db, order_in, dentist)
    return OrderCreateResponse(**OrderResponse.model_validate(order).model_dump(), upload_url=upload_url)


@router.get("", response_model=list[OrderResponse])
def list_orders(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return get_orders_for_user(db, current_user)


@router.get("/{order_id}", response_model=OrderResponse)
def get_order(
    order_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return get_order_by_id(db, order_id, current_user)


@router.patch("/{order_id}", response_model=OrderResponse)
def patch_order_status(
    order_id: uuid.UUID,
    status_update: OrderStatusUpdate,
    db: Session = Depends(get_db),
    lab_tech: User = Depends(require_role("lab_tech")),
):
    return update_order_status(db, order_id, status_update.status, lab_tech)


@router.get("/{order_id}/download-url")
def get_order_download_url(
    order_id: uuid.UUID,
    db: Session = Depends(get_db),
    lab_tech: User = Depends(require_role("lab_tech")),
):
    url = get_download_url_for_order(db, order_id, lab_tech)
    return {"download_url": url}
