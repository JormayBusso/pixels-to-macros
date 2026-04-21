import { motion } from 'framer-motion';
import type { StreakInfo } from '../types';

interface PlantWidgetProps {
  streak: StreakInfo;
  icon?: string;
}

// SVG plant paths for each growth level
function PlantSVG({ level, health }: { level: number; health: string }) {
  const baseColor  = health === 'thriving' ? '#15803d' : health === 'growing' ? '#16a34a' : health === 'alive' ? '#22c55e' : '#94a3b8';
  const leafColor  = health === 'thriving' ? '#22c55e' : health === 'growing' ? '#4ade80' : health === 'alive' ? '#86efac' : '#cbd5e1';
  const wilt       = health === 'wilting';

  return (
    <svg viewBox="0 0 80 100" className="w-full h-full">
      {/* Pot */}
      <rect x="25" y="82" width="30" height="18" rx="4" fill="#d97706" />
      <rect x="22" y="80" width="36" height="6" rx="3" fill="#b45309" />
      {/* Soil */}
      <ellipse cx="40" cy="83" rx="14" ry="4" fill="#78350f" />

      {/* Stem */}
      <motion.path
        d={`M40 80 Q${wilt ? '42' : '38'} ${80 - level * 6} 40 ${80 - level * 7}`}
        stroke={baseColor}
        strokeWidth="3"
        fill="none"
        strokeLinecap="round"
        animate={wilt ? { rotate: [0, 8, 0] } : {}}
        transition={{ repeat: Infinity, duration: 3 }}
      />

      {/* Leaves based on level */}
      {level >= 1 && (
        <motion.ellipse
          cx={wilt ? 52 : 30} cy={80 - level * 5}
          rx="10" ry="6"
          fill={leafColor}
          style={{ transformOrigin: '40px 80px' }}
          animate={{ rotate: wilt ? [0, 5, 0] : [-3, 3, -3] }}
          transition={{ repeat: Infinity, duration: 3 }}
        />
      )}
      {level >= 2 && (
        <motion.ellipse
          cx={wilt ? 28 : 52} cy={80 - level * 6}
          rx="10" ry="6"
          fill={leafColor}
          animate={{ rotate: wilt ? [0, -5, 0] : [3, -3, 3] }}
          transition={{ repeat: Infinity, duration: 3, delay: 0.5 }}
        />
      )}
      {level >= 4 && (
        <motion.ellipse
          cx={wilt ? 50 : 28} cy={80 - level * 7 + 4}
          rx="12" ry="7"
          fill={leafColor}
          animate={{ rotate: wilt ? [0, 5, 0] : [-2, 2, -2] }}
          transition={{ repeat: Infinity, duration: 2.5, delay: 0.3 }}
        />
      )}
      {level >= 6 && (
        <motion.ellipse
          cx={wilt ? 30 : 54} cy={80 - level * 7 + 6}
          rx="12" ry="7"
          fill={leafColor}
          animate={{ rotate: [3, -3, 3] }}
          transition={{ repeat: Infinity, duration: 2.5, delay: 0.8 }}
        />
      )}
      {level >= 8 && (
        <>
          <motion.ellipse
            cx="36" cy={80 - level * 7 + 10}
            rx="14" ry="8"
            fill={leafColor}
            animate={{ rotate: [-2, 2, -2] }}
            transition={{ repeat: Infinity, duration: 3 }}
          />
          <motion.ellipse
            cx="46" cy={80 - level * 7 + 12}
            rx="14" ry="8"
            fill={leafColor}
            animate={{ rotate: [2, -2, 2] }}
            transition={{ repeat: Infinity, duration: 3, delay: 0.4 }}
          />
        </>
      )}
      {/* Flower at top for thriving */}
      {level >= 9 && (
        <motion.g
          animate={{ scale: [1, 1.1, 1] }}
          transition={{ repeat: Infinity, duration: 2 }}
        >
          <circle cx="40" cy={80 - level * 7 - 4} r="6" fill="#fbbf24" />
          <circle cx="40" cy={80 - level * 7 - 4} r="3" fill="#f59e0b" />
        </motion.g>
      )}
    </svg>
  );
}

const HEALTH_LABEL: Record<string, { text: string; color: string }> = {
  thriving: { text: '🌟 Thriving!',  color: 'text-green-700' },
  growing:  { text: '📈 Growing',    color: 'text-green-600' },
  alive:    { text: '🌱 Alive',      color: 'text-green-500' },
  wilting:  { text: '😢 Wilting...',  color: 'text-amber-500' },
};

export default function PlantWidget({ streak }: PlantWidgetProps) {
  const { current_streak, plant_level, plant_health } = streak;
  const { text, color } = HEALTH_LABEL[plant_health] ?? HEALTH_LABEL.alive;

  return (
    <div className="flex flex-col items-center gap-2">
      <div className="w-28 h-36">
        <PlantSVG level={plant_level} health={plant_health} />
      </div>
      <p className={`text-sm font-semibold ${color}`}>{text}</p>
      <p className="text-xs text-gray-500">
        {current_streak > 0
          ? `${current_streak}-day streak 🔥`
          : 'Hit your goal to start growing!'}
      </p>
    </div>
  );
}
