import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_role
from app.db.base import get_db
from app.db.models.user import User
from app.schemas.order import OrderCreate, OrderResponse, OrderStatusUpdate
from app.services.order_service import create_order, get_orders_for_user, update_order_status

router = APIRouter(prefix="/orders", tags=["orders"])


@router.post("", response_model=OrderResponse, status_code=201)
def create_new_order(
    order_in: OrderCreate,
    db: Session = Depends(get_db),
    dentist: User = Depends(require_role("dentist")),
):
    return create_order(db, order_in, dentist)


@router.get("", response_model=list[OrderResponse])
def list_orders(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return get_orders_for_user(db, current_user)


@router.patch("/{order_id}", response_model=OrderResponse)
def patch_order_status(
    order_id: uuid.UUID,
    status_update: OrderStatusUpdate,
    db: Session = Depends(get_db),
    lab_tech: User = Depends(require_role("lab_tech")),
):
    return update_order_status(db, order_id, status_update.status, lab_tech)
