import { useEffect, useState } from 'react';
import { ShoppingCart, RefreshCw } from 'lucide-react';
import api from '../services/api';
import type { GroceryItem } from '../types';
import LoadingSpinner from '../components/LoadingSpinner';

const PRIORITY_BADGE: Record<string, string> = {
  high:   'badge-danger',
  medium: 'badge-warning',
  low:    'badge-success',
};

const CATEGORY_ICONS: Record<string, string> = {
  'Produce':              '🥦',
  'Meat & Fish':          '🍗',
  'Dairy':                '🥛',
  'Dairy & Eggs':         '🥚',
  'Protein Alternatives': '🫘',
  'Legumes':              '🫘',
  'Nuts & Seeds':         '🥜',
  'Grains':               '🌾',
  'Oils':                 '🫙',
  'Pantry':               '🛒',
};

export default function GroceryList() {
  const [items, setItems]       = useState<GroceryItem[]>([]);
  const [checked, setChecked]   = useState<Set<string>>(new Set());
  const [period, setPeriod]     = useState<{ start: string; end: string } | null>(null);
  const [loading, setLoading]   = useState(true);

  useEffect(() => {
    loadList();
  }, []);

  const loadList = async () => {
    setLoading(true);
    try {
      const res = await api.get('/grocery/list');
      setItems(res.data.grocery_list);
      setPeriod(res.data.period);
      setChecked(new Set());
    } finally {
      setLoading(false);
    }
  };

  const toggleItem = (item: string) => {
    setChecked((prev) => {
      const next = new Set(prev);
      if (next.has(item)) next.delete(item);
      else next.add(item);
      return next;
    });
  };

  // Group items by category
  const grouped = items.reduce<Record<string, GroceryItem[]>>((acc, item) => {
    if (!acc[item.category]) acc[item.category] = [];
    acc[item.category].push(item);
    return acc;
  }, {});

  const remaining = items.filter((i) => !checked.has(i.item)).length;

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Smart Grocery List</h1>
          {period && (
            <p className="text-sm text-gray-500 mt-0.5">
              Based on your nutrition from {period.start} to {period.end}
            </p>
          )}
        </div>
        <button onClick={loadList} className="btn-secondary text-sm flex items-center gap-1.5">
          <RefreshCw className="w-4 h-4" /> Refresh
        </button>
      </div>

      {loading ? (
        <div className="flex justify-center py-16"><LoadingSpinner size="lg" /></div>
      ) : items.length === 0 ? (
        <div className="card text-center py-12 text-gray-400">
          <ShoppingCart className="w-12 h-12 mx-auto mb-3 text-gray-200" />
          <p className="font-medium">No grocery recommendations yet</p>
          <p className="text-sm mt-1">Log your meals for a week to get personalized suggestions</p>
        </div>
      ) : (
        <>
          {/* Progress */}
          <div className="card">
            <div className="flex justify-between items-center mb-2">
              <span className="text-sm font-medium text-gray-700">Shopping progress</span>
              <span className="text-sm text-green-600 font-semibold">
                {items.length - remaining} / {items.length} items
              </span>
            </div>
            <div className="progress-bar">
              <div
                className="progress-fill bg-green-500"
                style={{ width: `${((items.length - remaining) / items.length) * 100}%` }}
              />
            </div>
          </div>

          {/* Grouped list */}
          {Object.entries(grouped).map(([category, categoryItems]) => (
            <div key={category} className="card">
              <h2 className="font-bold text-gray-800 mb-3 flex items-center gap-2">
                <span>{CATEGORY_ICONS[category] ?? '🛒'}</span>
                {category}
              </h2>
              <div className="space-y-2">
                {categoryItems.map((item) => {
                  const isChecked = checked.has(item.item);
                  return (
                    <div
                      key={item.item}
                      onClick={() => toggleItem(item.item)}
                      className={`flex items-center gap-3 p-3 rounded-xl cursor-pointer transition-all
                        ${isChecked ? 'bg-green-50 opacity-60' : 'bg-gray-50 hover:bg-green-50'}`}
                    >
                      <div className={`w-5 h-5 rounded border-2 flex items-center justify-center shrink-0 transition-all
                        ${isChecked ? 'bg-green-500 border-green-500' : 'border-gray-300'}`}>
                        {isChecked && <span className="text-white text-xs">✓</span>}
                      </div>
                      <div className="flex-1 min-w-0">
                        <p className={`text-sm font-medium ${isChecked ? 'line-through text-gray-400' : 'text-gray-800'}`}>
                          {item.item}
                        </p>
                        <p className="text-xs text-gray-400 truncate">{item.reason}</p>
                      </div>
                      <span className={PRIORITY_BADGE[item.priority]}>{item.priority}</span>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </>
      )}
    </div>
  );
}
