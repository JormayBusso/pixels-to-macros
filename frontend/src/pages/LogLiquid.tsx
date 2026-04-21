import { useEffect, useState } from 'react';
import api from '../services/api';
import type { LiquidLog } from '../types';
import LiquidTracker from '../components/LiquidTracker';
import LoadingSpinner from '../components/LoadingSpinner';

function today() {
  return new Date().toISOString().split('T')[0];
}

export default function LogLiquid() {
  const [logs, setLogs]     = useState<LiquidLog[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadLogs();
  }, []);

  const loadLogs = async () => {
    setLoading(true);
    try {
      const res = await api.get<LiquidLog[]>(`/logs/liquid/${today()}`);
      setLogs(res.data);
    } finally {
      setLoading(false);
    }
  };

  const handleAdd = async (type: string, ml: number) => {
    await api.post('/logs/liquid', { liquid_type: type, amount_ml: ml, date: today() });
    loadLogs();
  };

  const handleDelete = async (id: number) => {
    await api.delete(`/logs/liquid/${id}`);
    loadLogs();
  };

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-gray-900">Hydration Tracker</h1>
      <div className="card">
        {loading ? (
          <div className="flex justify-center py-10"><LoadingSpinner /></div>
        ) : (
          <LiquidTracker logs={logs} onAdd={handleAdd} onDelete={handleDelete} />
        )}
      </div>

      {/* Tips */}
      <div className="card bg-blue-50 border-blue-100">
        <h3 className="font-semibold text-blue-800 mb-2">💧 Hydration Tips</h3>
        <ul className="text-sm text-blue-700 space-y-1 list-disc list-inside">
          <li>Aim for 2–3 litres of water per day</li>
          <li>Drink a glass of water first thing in the morning</li>
          <li>Coffee and tea count but also act as mild diuretics</li>
          <li>Your urine should be pale yellow — that's a good hydration sign</li>
        </ul>
      </div>
    </div>
  );
}
