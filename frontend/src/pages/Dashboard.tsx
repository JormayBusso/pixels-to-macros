import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ChevronLeft, ChevronRight, Plus, Trash2, Edit2, Check, X } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import api from '../services/api';
import type { DailySummary, FoodLog } from '../types';
import { MEAL_COLORS } from '../types';
import { getFoodIcon } from '../utils/foodIcons';
import DonutChart from '../components/DonutChart';
import PlantWidget from '../components/PlantWidget';
import VitaminTracker from '../components/VitaminTracker';
import SmartSuggestions from '../components/SmartSuggestions';
import LiquidTracker from '../components/LiquidTracker';
import LoadingSpinner from '../components/LoadingSpinner';

function addDays(d: Date, n: number) {
  const r = new Date(d); r.setDate(r.getDate() + n); return r;
}
function subDays(d: Date, n: number) {
  const r = new Date(d); r.setDate(r.getDate() - n); return r;
}
function isToday(d: Date) {
  const t = new Date();
  return d.getFullYear() === t.getFullYear() && d.getMonth() === t.getMonth() && d.getDate() === t.getDate();
}
function formatDate(d: Date): string {
  return d.toISOString().split('T')[0];
}
function displayDate(d: Date): string {
  if (isToday(d)) return 'Today';
  return d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
}

const MEAL_ORDER = ['breakfast', 'lunch', 'dinner', 'snack', 'other'];

interface EditState { id: number; food_name: string; weight_g: number; }

export default function Dashboard() {
  const { user } = useAuth();
  const [date, setDate]       = useState(new Date());
  const [summary, setSummary] = useState<DailySummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [editState, setEditState] = useState<EditState | null>(null);
  const [saving, setSaving]   = useState(false);

  useEffect(() => {
    loadSummary();
  }, [date]);

  const loadSummary = async () => {
    setLoading(true);
    try {
      const res = await api.get<DailySummary>(`/dashboard/summary/${formatDate(date)}`);
      setSummary(res.data);
    } catch {
      setSummary(null);
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteFood = async (id: number) => {
    if (!confirm('Remove this item?')) return;
    await api.delete(`/logs/food/${id}`);
    loadSummary();
  };

  const handleSaveEdit = async () => {
    if (!editState) return;
    setSaving(true);
    try {
      await api.put(`/logs/food/${editState.id}`, {
        food_name: editState.food_name,
        weight_g: editState.weight_g,
      });
      setEditState(null);
      loadSummary();
    } finally {
      setSaving(false);
    }
  };

  const handleAddLiquid = async (type: string, ml: number) => {
    await api.post('/logs/liquid', { liquid_type: type, amount_ml: ml, date: formatDate(date) });
    loadSummary();
  };

  const handleDeleteLiquid = async (id: number) => {
    await api.delete(`/logs/liquid/${id}`);
    loadSummary();
  };

  // Group food logs by meal type
  const grouped = MEAL_ORDER.reduce<Record<string, FoodLog[]>>((acc, mt) => {
    const items = summary?.food_logs.filter((l) => l.meal_type === mt) ?? [];
    if (items.length) acc[mt] = items;
    return acc;
  }, {});

  const todayFlag = isToday(date);

  return (
    <div className="space-y-5">
      {/* Date navigator */}
      <div className="flex items-center justify-between card py-3">
        <button onClick={() => setDate(subDays(date, 1))} className="btn-ghost p-2">
          <ChevronLeft className="w-5 h-5" />
        </button>
        <div className="text-center">
          <p className="font-bold text-gray-900 text-lg">{displayDate(date)}</p>
          <p className="text-xs text-gray-400">{formatDate(date)}</p>
        </div>
        <button
          onClick={() => setDate(addDays(date, 1))}
          disabled={todayFlag}
          className="btn-ghost p-2 disabled:opacity-30"
        >
          <ChevronRight className="w-5 h-5" />
        </button>
      </div>

      {loading ? (
        <div className="flex justify-center py-16"><LoadingSpinner size="lg" label="Loading summary…" /></div>
      ) : !summary ? (
        <div className="card text-center py-10 text-gray-400">Failed to load data</div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
          {/* LEFT column */}
          <div className="md:col-span-2 space-y-5">

            {/* Macros donut */}
            <div className="card">
              <h2 className="font-bold text-gray-900 mb-3">Today's Macros</h2>
              <DonutChart totals={summary.totals} calorieTarget={summary.caloric_target} />
            </div>

            {/* Food log */}
            <div className="card">
              <div className="flex items-center justify-between mb-3">
                <h2 className="font-bold text-gray-900">Food Log</h2>
                <Link to="/log-food" className="btn-primary text-sm py-1.5 px-3 flex items-center gap-1">
                  <Plus className="w-3.5 h-3.5" /> Add
                </Link>
              </div>

              {Object.keys(grouped).length === 0 ? (
                <div className="text-center py-8 text-gray-400">
                  <span className="text-4xl block mb-2">🍽️</span>
                  <p className="text-sm">No food logged yet.</p>
                  <Link to="/log-food" className="text-green-600 text-sm font-medium hover:underline">
                    Log your first meal →
                  </Link>
                </div>
              ) : (
                Object.entries(grouped).map(([mealType, items]) => (
                  <div key={mealType} className="mb-4">
                    <span className={`meal-tag ${MEAL_COLORS[mealType]} mb-2 inline-block`}>{mealType}</span>
                    <div className="space-y-2">
                      {items.map((log) => (
                        <div key={log.id}>
                          {editState?.id === log.id ? (
                            <div className="flex gap-2 items-center bg-green-50 rounded-xl p-2">
                              <span className="text-lg">{getFoodIcon(log.food_name)}</span>
                              <input
                                className="input-field flex-1 text-sm py-1.5"
                                value={editState.food_name}
                                onChange={(e) => setEditState({ ...editState, food_name: e.target.value })}
                              />
                              <input
                                type="number"
                                min="1"
                                className="input-field w-20 text-sm py-1.5"
                                value={editState.weight_g}
                                onChange={(e) => setEditState({ ...editState, weight_g: parseFloat(e.target.value) })}
                              />
                              <span className="text-xs text-gray-400">g</span>
                              <button onClick={handleSaveEdit} disabled={saving} className="text-green-600 hover:text-green-700">
                                <Check className="w-4 h-4" />
                              </button>
                              <button onClick={() => setEditState(null)} className="text-gray-400 hover:text-gray-600">
                                <X className="w-4 h-4" />
                              </button>
                            </div>
                          ) : (
                            <div className="flex items-center gap-3 bg-gray-50 rounded-xl px-3 py-2 hover:bg-green-50 transition-colors group">
                              <span className="text-xl">{getFoodIcon(log.food_name)}</span>
                              <div className="flex-1 min-w-0">
                                <p className="text-sm font-medium text-gray-800 truncate">{log.food_name}</p>
                                <p className="text-xs text-gray-400">{log.weight_g}g • {Math.round(log.nutrients.calories?.value ?? 0)} kcal</p>
                              </div>
                              <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                                <button
                                  onClick={() => setEditState({ id: log.id, food_name: log.food_name, weight_g: log.weight_g })}
                                  className="p-1.5 rounded-lg hover:bg-green-100 text-gray-400 hover:text-green-600"
                                >
                                  <Edit2 className="w-3.5 h-3.5" />
                                </button>
                                <button
                                  onClick={() => handleDeleteFood(log.id)}
                                  className="p-1.5 rounded-lg hover:bg-red-50 text-gray-400 hover:text-red-500"
                                >
                                  <Trash2 className="w-3.5 h-3.5" />
                                </button>
                              </div>
                            </div>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                ))
              )}
            </div>

            {/* Liquid tracker */}
            <div className="card">
              <h2 className="font-bold text-gray-900 mb-3">Hydration</h2>
              <LiquidTracker
                logs={summary.liquid_logs as any}
                onAdd={handleAddLiquid}
                onDelete={handleDeleteLiquid}
              />
            </div>

            {/* Vitamins */}
            {summary.vitamin_status.length > 0 && (
              <div className="card">
                <h2 className="font-bold text-gray-900 mb-3">Vitamin Tracker</h2>
                <VitaminTracker vitamins={summary.vitamin_status} />
              </div>
            )}
          </div>

          {/* RIGHT column */}
          <div className="space-y-5">
            {/* Avatar widget */}
            <div className="card text-center">
              <PlantWidget streak={summary.streak} goal={user?.dietary_goal} />
            </div>

            {/* Goal card */}
            <div className={`card ${summary.goal_met ? 'border-green-300 bg-green-50' : ''}`}>
              <p className="text-sm font-medium text-gray-700 mb-1">Daily Goal</p>
              <p className="text-2xl font-bold text-gray-900">
                {Math.round(summary.totals.calories?.value ?? 0)}
                <span className="text-sm font-normal text-gray-400"> / {summary.caloric_target} kcal</span>
              </p>
              <div className="progress-bar mt-2">
                <div
                  className="progress-fill bg-green-500"
                  style={{
                    width: `${Math.min(100, ((summary.totals.calories?.value ?? 0) / summary.caloric_target) * 100)}%`,
                  }}
                />
              </div>
              {summary.goal_met && (
                <p className="text-xs text-green-600 font-medium mt-2">✓ Goal reached!</p>
              )}
            </div>

            {/* Smart suggestions */}
            {summary.suggestions.length > 0 && (
              <div className="card">
                <h2 className="font-bold text-gray-900 mb-3">Smart Tips</h2>
                <SmartSuggestions suggestions={summary.suggestions} />
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
