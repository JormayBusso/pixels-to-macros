import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer, Legend } from 'recharts';
import type { NutrientValue } from '../types';

interface DonutChartProps {
  totals: Record<string, NutrientValue>;
  calorieTarget?: number;
}

const MACRO_CONFIG = [
  { key: 'carbohydrates', label: 'Carbs',   color: '#22c55e', kcalPer: 4 },
  { key: 'protein',       label: 'Protein', color: '#3b82f6', kcalPer: 4 },
  { key: 'fat',           label: 'Fat',     color: '#f59e0b', kcalPer: 9 },
];

function getNutrientVal(totals: Record<string, NutrientValue>, key: string): number {
  return totals[key]?.value ?? 0;
}

export default function DonutChart({ totals, calorieTarget }: DonutChartProps) {
  const data = MACRO_CONFIG.map(({ key, label, color, kcalPer }) => ({
    name: label,
    value: Math.round(getNutrientVal(totals, key) * kcalPer),
    grams: Math.round(getNutrientVal(totals, key)),
    color,
  })).filter((d) => d.value > 0);

  const totalKcal = Math.round(getNutrientVal(totals, 'calories'));

  if (data.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center h-48 text-gray-400 gap-2">
        <span className="text-4xl">🍽️</span>
        <p className="text-sm">No food logged yet today</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col items-center">
      <div className="relative w-full" style={{ height: 220 }}>
        <ResponsiveContainer>
          <PieChart>
            <Pie
              data={data}
              cx="50%"
              cy="50%"
              innerRadius={65}
              outerRadius={95}
              paddingAngle={3}
              dataKey="value"
            >
              {data.map((entry, i) => (
                <Cell key={i} fill={entry.color} stroke="none" />
              ))}
            </Pie>
            <Tooltip
              formatter={(value: number, name: string) => [`${value} kcal`, name]}
              contentStyle={{ borderRadius: 12, border: 'none', boxShadow: '0 4px 20px rgba(0,0,0,.1)' }}
            />
          </PieChart>
        </ResponsiveContainer>
        {/* Centre label */}
        <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
          <span className="text-2xl font-bold text-gray-900">{totalKcal}</span>
          <span className="text-xs text-gray-500">kcal</span>
          {calorieTarget && (
            <span className="text-xs text-gray-400">/ {calorieTarget}</span>
          )}
        </div>
      </div>

      {/* Legend */}
      <div className="flex gap-4 flex-wrap justify-center mt-1">
        {data.map((d) => (
          <div key={d.name} className="flex items-center gap-1.5">
            <span className="w-3 h-3 rounded-full" style={{ backgroundColor: d.color }} />
            <span className="text-sm text-gray-600">
              {d.name} <span className="font-semibold text-gray-800">{d.grams}g</span>
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
