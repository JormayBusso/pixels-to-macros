import type { VitaminStatus } from '../types';

interface VitaminTrackerProps {
  vitamins: VitaminStatus[];
}

const STATUS_COLORS = {
  sufficient: 'bg-green-500',
  low:        'bg-amber-400',
  deficient:  'bg-red-400',
};

const STATUS_BADGES = {
  sufficient: 'badge-success',
  low:        'badge-warning',
  deficient:  'badge-danger',
};

export default function VitaminTracker({ vitamins }: VitaminTrackerProps) {
  const deficientCount = vitamins.filter((v) => v.status === 'deficient').length;
  const lowCount       = vitamins.filter((v) => v.status === 'low').length;

  return (
    <div className="space-y-3">
      {/* Summary row */}
      {(deficientCount > 0 || lowCount > 0) && (
        <div className="flex gap-2 flex-wrap mb-1">
          {deficientCount > 0 && (
            <span className="badge-danger">
              ⚠️ {deficientCount} deficient
            </span>
          )}
          {lowCount > 0 && (
            <span className="badge-warning">
              📉 {lowCount} low
            </span>
          )}
          {deficientCount === 0 && lowCount === 0 && (
            <span className="badge-success">✓ All vitamins on track!</span>
          )}
        </div>
      )}

      {vitamins.map((v) => (
        <div key={v.key}>
          <div className="flex justify-between items-center mb-1">
            <span className="text-sm font-medium text-gray-700">{v.name}</span>
            <div className="flex items-center gap-2">
              <span className="text-xs text-gray-500">
                {v.current}{v.unit} / {v.rdv}{v.unit}
              </span>
              <span className={STATUS_BADGES[v.status]}>{v.percentage}%</span>
            </div>
          </div>
          <div className="progress-bar">
            <div
              className={`progress-fill ${STATUS_COLORS[v.status]}`}
              style={{ width: `${v.percentage}%` }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}
