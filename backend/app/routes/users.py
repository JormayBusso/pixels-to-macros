"""
users.py
────────
User profile and dietary-goals endpoints.
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel

from app.database import get_db
from app.models.db_models import User
from app.services.auth_service import get_current_user

router = APIRouter(prefix="/users", tags=["users"])

VALID_DIETARY_GOALS = {
    "balanced", "diabetic", "low_carb", "muscle_growth",
    "weight_loss", "vegan", "keto", "mediterranean",
}
VALID_ICONS = {"plant", "tree", "flower", "cactus", "sunflower", "bonsai"}


# ── Schemas ───────────────────────────────────────────────────────────────────

class UserProfileResponse(BaseModel):
    id: int
    email: str
    username: str
    dietary_goal: Optional[str]
    caloric_target: Optional[int]
    gamification_icon: str

    model_config = {"from_attributes": True}


class UpdateProfileRequest(BaseModel):
    username: Optional[str] = None
    gamification_icon: Optional[str] = None


class UpdateGoalsRequest(BaseModel):
    dietary_goal: str
    caloric_target: Optional[int] = None


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/me", response_model=UserProfileResponse)
def get_profile(current_user: User = Depends(get_current_user)):
    return current_user


@router.put("/me", response_model=UserProfileResponse)
def update_profile(
    body: UpdateProfileRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if body.username is not None:
        clash = (
            db.query(User)
            .filter(User.username == body.username, User.id != current_user.id)
            .first()
        )
        if clash:
            raise HTTPException(status_code=409, detail="Username already taken")
        current_user.username = body.username

    if body.gamification_icon is not None:
        if body.gamification_icon not in VALID_ICONS:
            raise HTTPException(
                status_code=422,
                detail=f"Invalid icon. Choose from: {', '.join(sorted(VALID_ICONS))}",
            )
        current_user.gamification_icon = body.gamification_icon

    db.commit()
    db.refresh(current_user)
    return current_user


@router.put("/goals", response_model=UserProfileResponse)
def update_goals(
    body: UpdateGoalsRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if body.dietary_goal not in VALID_DIETARY_GOALS:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid dietary goal. Choose from: {', '.join(sorted(VALID_DIETARY_GOALS))}",
        )
    if body.caloric_target is not None:
        if body.caloric_target < 500:
            raise HTTPException(status_code=422, detail="Caloric target must be at least 500 kcal")
        if body.caloric_target > 10_000:
            raise HTTPException(status_code=422, detail="Caloric target cannot exceed 10 000 kcal")

    current_user.dietary_goal = body.dietary_goal
    current_user.caloric_target = body.caloric_target
    db.commit()
    db.refresh(current_user)
    return current_user
