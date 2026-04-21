"""
db_models.py
────────────
SQLAlchemy ORM models for NutriLens.
"""

import json
from datetime import datetime, date as date_type

from sqlalchemy import (
    Column, Integer, String, Float, Boolean,
    Date, DateTime, Text, ForeignKey,
)
from sqlalchemy.orm import relationship

from app.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(254), unique=True, index=True, nullable=False)
    username = Column(String(50), unique=True, index=True, nullable=False)
    hashed_password = Column(String(128), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Onboarding / goals
    dietary_goal = Column(String(50), nullable=True)       # set during onboarding
    caloric_target = Column(Integer, nullable=True)         # optional
    gamification_icon = Column(String(30), default="plant")

    food_logs = relationship("FoodLog", back_populates="user", cascade="all, delete-orphan")
    liquid_logs = relationship("LiquidLog", back_populates="user", cascade="all, delete-orphan")
    daily_streaks = relationship("DailyStreak", back_populates="user", cascade="all, delete-orphan")


class FoodLog(Base):
    __tablename__ = "food_logs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    date = Column(Date, nullable=False, default=date_type.today)
    food_name = Column(String(200), nullable=False)
    matched_food = Column(String(200), nullable=True)
    fdc_id = Column(Integer, nullable=True)
    weight_g = Column(Float, nullable=False)
    meal_type = Column(String(20), default="other")
    nutrients_json = Column(Text, default="{}")
    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="food_logs")

    @property
    def nutrients(self) -> dict:
        try:
            return json.loads(self.nutrients_json or "{}")
        except (json.JSONDecodeError, TypeError):
            return {}


class LiquidLog(Base):
    __tablename__ = "liquid_logs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    date = Column(Date, nullable=False, default=date_type.today)
    liquid_type = Column(String(50), nullable=False)
    amount_ml = Column(Float, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="liquid_logs")


class DailyStreak(Base):
    __tablename__ = "daily_streaks"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    date = Column(Date, nullable=False)
    goal_met = Column(Boolean, default=False)

    user = relationship("User", back_populates="daily_streaks")
