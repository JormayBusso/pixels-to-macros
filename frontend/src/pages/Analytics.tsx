import { useEffect, useState } from 'react';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip,
  ResponsiveContainer, BarChart, Bar, Legend,
} from 'recharts';
import api from '../services/api';
import type { HistoryEntry } from '../types';
import LoadingSpinner from '../components/LoadingSpinner';

const PERIOD_OPTIONS = [
  { label: '7 days',  value: 7  },
  { label: '14 days', value: 14 },
  { label: '30 days', value: 30 },
];

function shortDate(dateStr: string) {
  const d = new Date(dateStr);
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

export default function Analytics() {
  const [days, setDays]         = useState(14);
  const [history, setHistory]   = useState<HistoryEntry[]>([]);
  const [loading, setLoading]   = useState(true);

  useEffect(() => {
    loadHistory();
  }, [days]);

  const loadHistory = async () => {
    setLoading(true);
    try {
      const res = await api.get(`/dashboard/history?days=${days}`);
      setHistory(res.data.history);
    } finally {
      setLoading(false);
    }
  };

  const chartData = history.map((h) => ({
    ...h,
    date: shortDate(h.date),
    calories: Math.round(h.calories),
    protein:  Math.round(h.protein),
    carbs:    Math.round(h.carbohydrates),
    fat:      Math.round(h.fat),
  }));

  const avgCalories = history.length
    ? Math.round(history.reduce((s, h) => s + h.calories, 0) / history.length)
    : 0;
  const goalDays = history.filter((h) => h.goal_met).length;
  const activeDays = history.filter((h) => h.calories > 0).length;

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold text-gray-900">Analytics</h1>
        <div className="flex gap-1 bg-white rounded-xl p-1 border border-green-100">
          {PERIOD_OPTIONS.map(({ label, value }) => (
            <button
              key={value}
              onClick={() => setDays(value)}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors
                ${days === value ? 'bg-green-600 text-white' : 'text-gray-600 hover:bg-green-50'}`}
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-16"><LoadingSpinner size="lg" /></div>
      ) : (
        <>
          {/* KPI cards */}
          <div className="grid grid-cols-3 gap-3">
            <div className="card text-center">
              <p className="text-2xl font-bold text-green-600">{avgCalories}</p>
              <p className="text-xs text-gray-500 mt-1">Avg kcal / day</p>
            </div>
            <div className="card text-center">
              <p className="text-2xl font-bold text-blue-600">{activeDays}</p>
              <p className="text-xs text-gray-500 mt-1">Active days</p>
            </div>
            <div className="card text-center">
              <p className="text-2xl font-bold text-amber-500">{goalDays}</p>
              <p className="text-xs text-gray-500 mt-1">Goals met</p>
            </div>
          </div>

          {/* Calorie area chart */}
          <div className="card">
            <h2 className="font-bold text-gray-900 mb-4">Calorie Intake</h2>
            <ResponsiveContainer width="100%" height={200}>
              <AreaChart data={chartData} margin={{ top: 5, right: 10, left: -10, bottom: 5 }}>
                <defs>
                  <linearGradient id="calGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%"  stopColor="#16a34a" stopOpacity={0.3} />
                    <stop offset="95%" stopColor="#16a34a" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="#f0fdf4" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} />
                <Tooltip
                  formatter={(v: number) => [`${v} kcal`, 'Calories']}
                  contentStyle={{ borderRadius: 12, border: 'none', boxShadow: '0 4px 20px rgba(0,0,0,.1)' }}
                />
                <Area
                  type="monotone"
                  dataKey="calories"
                  stroke="#16a34a"
                  strokeWidth={2}
                  fill="url(#calGrad)"
                  dot={{ r: 3, fill: '#16a34a' }}
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>

          {/* Macros bar chart */}
          <div className="card">
            <h2 className="font-bold text-gray-900 mb-4">Macronutrient Breakdown</h2>
            <ResponsiveContainer width="100%" height={220}>
              <BarChart data={chartData} margin={{ top: 5, right: 10, left: -10, bottom: 5 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f0fdf4" />
                <XAxis dataKey="date" tick={{ fontSize: 11 }} />
                <YAxis tick={{ fontSize: 11 }} />
                <Tooltip
                  contentStyle={{ borderRadius: 12, border: 'none', boxShadow: '0 4px 20px rgba(0,0,0,.1)' }}
                />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar dataKey="protein" name="Protein (g)" fill="#3b82f6" radius={[3, 3, 0, 0]} />
                <Bar dataKey="carbs"   name="Carbs (g)"   fill="#22c55e" radius={[3, 3, 0, 0]} />
                <Bar dataKey="fat"     name="Fat (g)"     fill="#f59e0b" radius={[3, 3, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </div>

          {/* Goal history */}
          <div className="card">
            <h2 className="font-bold text-gray-900 mb-3">Goal Calendar</h2>
            <div className="flex flex-wrap gap-1.5">
              {history.map((h) => (
                <div
                  key={h.date}
                  title={`${h.date}: ${Math.round(h.calories)} kcal ${h.goal_met ? '✓' : ''}`}
                  className={`w-7 h-7 rounded-lg text-xs flex items-center justify-center font-medium
                    ${h.calories === 0 ? 'bg-gray-100 text-gray-300'
                      : h.goal_met ? 'bg-green-500 text-white'
                      : 'bg-amber-100 text-amber-600'
                    }`}
                >
                  {new Date(h.date).getDate()}
                </div>
              ))}
            </div>
            <div className="flex gap-4 mt-3 text-xs text-gray-500">
              <span className="flex items-center gap-1"><span className="w-3 h-3 rounded bg-green-500 inline-block" /> Goal met</span>
              <span className="flex items-center gap-1"><span className="w-3 h-3 rounded bg-amber-100 inline-block" /> Logged</span>
              <span className="flex items-center gap-1"><span className="w-3 h-3 rounded bg-gray-100 inline-block" /> No data</span>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
