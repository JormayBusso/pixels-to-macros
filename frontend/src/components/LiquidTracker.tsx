import { Droplets, Plus } from 'lucide-react';
import { useState } from 'react';
import { getLiquidIcon } from '../utils/foodIcons';
import type { LiquidLog } from '../types';

interface LiquidTrackerProps {
  logs: LiquidLog[];
  onAdd: (type: string, ml: number) => void;
  onDelete: (id: number) => void;
}

const QUICK_BUTTONS = [
  { label: '200 ml', ml: 200, type: 'water' },
  { label: '330 ml', ml: 330, type: 'water' },
  { label: '500 ml', ml: 500, type: 'water' },
  { label: '750 ml', ml: 750, type: 'water' },
];

const LIQUID_TYPES = ['water', 'coffee', 'tea', 'juice', 'milk', 'soda', 'smoothie', 'sports_drink', 'other'];

const DAILY_WATER_GOAL = 2000; // ml

export default function LiquidTracker({ logs, onAdd, onDelete }: LiquidTrackerProps) {
  const [customMl, setCustomMl]   = useState('');
  const [customType, setCustomType] = useState('water');

  const totalWater  = logs.filter((l) => l.liquid_type === 'water').reduce((s, l) => s + l.amount_ml, 0);
  const totalLiquid = logs.reduce((s, l) => s + l.amount_ml, 0);
  const waterPct    = Math.min(100, Math.round((totalWater / DAILY_WATER_GOAL) * 100));

  const handleCustomAdd = () => {
    const ml = parseFloat(customMl);
    if (!ml || ml <= 0 || ml > 10_000) return;
    onAdd(customType, ml);
    setCustomMl('');
  };

  return (
    <div className="space-y-4">
      {/* Water progress */}
      <div>
        <div className="flex justify-between text-sm mb-1">
          <span className="font-medium text-gray-700">💧 Water intake</span>
          <span className="text-blue-600 font-semibold">{Math.round(totalWater)} / {DAILY_WATER_GOAL} ml</span>
        </div>
        <div className="progress-bar">
          <div className="progress-fill bg-blue-400" style={{ width: `${waterPct}%` }} />
        </div>
        <p className="text-xs text-gray-400 mt-1">
          Total liquid today: {Math.round(totalLiquid)} ml
        </p>
      </div>

      {/* Quick add buttons */}
      <div className="flex gap-2 flex-wrap">
        {QUICK_BUTTONS.map(({ label, ml, type }) => (
          <button
            key={label}
            onClick={() => onAdd(type, ml)}
            className="btn-secondary text-sm py-1.5 px-3"
          >
            💧 {label}
          </button>
        ))}
      </div>

      {/* Custom add */}
      <div className="flex gap-2">
        <select
          value={customType}
          onChange={(e) => setCustomType(e.target.value)}
          className="input-field flex-1 text-sm"
        >
          {LIQUID_TYPES.map((t) => (
            <option key={t} value={t}>{getLiquidIcon(t)} {t.replace('_', ' ')}</option>
          ))}
        </select>
        <input
          type="number"
          min="1"
          max="10000"
          placeholder="ml"
          value={customMl}
          onChange={(e) => setCustomMl(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleCustomAdd()}
          className="input-field w-24 text-sm"
        />
        <button onClick={handleCustomAdd} className="btn-primary py-2 px-3">
          <Plus className="w-4 h-4" />
        </button>
      </div>

      {/* Log list */}
      {logs.length > 0 && (
        <div className="space-y-1.5 max-h-40 overflow-y-auto">
          {logs.map((log) => (
            <div
              key={log.id}
              className="flex items-center justify-between bg-blue-50 rounded-lg px-3 py-2"
            >
              <span className="text-sm">
                {getLiquidIcon(log.liquid_type)} {log.liquid_type.replace('_', ' ')}
              </span>
              <div className="flex items-center gap-2">
                <span className="text-sm font-semibold text-blue-700">{log.amount_ml} ml</span>
                <button
                  onClick={() => onDelete(log.id)}
                  className="text-gray-300 hover:text-red-400 transition-colors text-xs"
                >
                  ✕
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
