import { motion } from 'framer-motion';
import type { StreakInfo } from '../types';

interface PlantWidgetProps {
  streak: StreakInfo;
  goal?: string | null;
}

// ── Shared health labels ───────────────────────────────────────────────────────
const HEALTH_LABEL: Record<string, { text: string; color: string }> = {
  thriving: { text: '🌟 Thriving!',    color: 'text-green-700' },
  growing:  { text: '📈 Growing',      color: 'text-green-600' },
  alive:    { text: '🌱 Alive',        color: 'text-green-500' },
  wilting:  { text: '😢 Struggling…',  color: 'text-amber-500' },
};

// ══════════════════════════════════════════════════════════════════════════════
// GORILLA — Muscle Growth
// ══════════════════════════════════════════════════════════════════════════════
function GorillaSVG({ level, health }: { level: number; health: string }) {
  const thriving   = health === 'thriving';
  const wilting    = health === 'wilting';
  const scale      = 0.55 + (level / 10) * 0.55;
  const bodyColor  = wilting ? '#9ca3af' : thriving ? '#374151' : '#4b5563';
  const skinColor  = wilting ? '#d1d5db' : thriving ? '#6b7280' : '#9ca3af';
  const eyeGlow    = thriving ? '#22d3ee' : wilting ? '#f87171' : '#e5e7eb';

  return (
    <svg viewBox="0 0 80 100" className="w-full h-full">
      <ellipse cx="40" cy="94" rx={12 * scale} ry="3" fill="#00000022" />
      <motion.g
        style={{ transformOrigin: '40px 70px' }}
        animate={{ scale: [scale, scale * 1.03, scale], y: wilting ? [0, 3, 0] : [0, -2, 0] }}
        transition={{ repeat: Infinity, duration: wilting ? 2 : 3 }}
      >
        <motion.ellipse cx={wilting ? 22 : 18} cy={wilting ? 70 : 65} rx={8} ry={4} fill={bodyColor}
          style={{ transformOrigin: '28px 60px' }}
          animate={{ rotate: wilting ? [0, 15, 0] : thriving ? [-20, 20, -20] : [-10, 10, -10] }}
          transition={{ repeat: Infinity, duration: 1.5 }} />
        <motion.ellipse cx={wilting ? 58 : 62} cy={wilting ? 70 : 65} rx={8} ry={4} fill={bodyColor}
          style={{ transformOrigin: '52px 60px' }}
          animate={{ rotate: wilting ? [0, -15, 0] : thriving ? [20, -20, 20] : [10, -10, 10] }}
          transition={{ repeat: Infinity, duration: 1.5, delay: 0.2 }} />
        <ellipse cx="40" cy="72" rx={wilting ? 12 : thriving ? 18 : 15} ry={wilting ? 14 : thriving ? 20 : 17} fill={bodyColor} />
        <ellipse cx="40" cy="70" rx={wilting ? 7 : thriving ? 11 : 9} ry={wilting ? 8 : thriving ? 12 : 10} fill={skinColor} opacity="0.6" />
        <ellipse cx="40" cy={wilting ? 56 : 52} rx={wilting ? 10 : thriving ? 14 : 12} ry={wilting ? 9 : thriving ? 12 : 11} fill={bodyColor} />
        <rect x={wilting ? 32 : 28} y={wilting ? 48 : 43} width={wilting ? 16 : 24} height="4" rx="2" fill={bodyColor} />
        <ellipse cx="40" cy={wilting ? 56 : 54} rx={wilting ? 7 : 9} ry={wilting ? 6 : 8} fill={skinColor} />
        <circle cx={wilting ? 36 : 35} cy={wilting ? 52 : 50} r="2" fill={eyeGlow} />
        <circle cx={wilting ? 44 : 45} cy={wilting ? 52 : 50} r="2" fill={eyeGlow} />
        <circle cx={wilting ? 36 : 35} cy={wilting ? 52 : 50} r="1" fill="#111827" />
        <circle cx={wilting ? 44 : 45} cy={wilting ? 52 : 50} r="1" fill="#111827" />
        <circle cx="38" cy={wilting ? 57 : 56} r="1.2" fill="#374151" opacity="0.7" />
        <circle cx="42" cy={wilting ? 57 : 56} r="1.2" fill="#374151" opacity="0.7" />
        {thriving
          ? <path d="M35 60 Q40 64 45 60" stroke="#111827" strokeWidth="1.5" fill="none" />
          : wilting
          ? <path d="M35 60 Q40 57 45 60" stroke="#111827" strokeWidth="1.5" fill="none" />
          : <line x1="36" y1="59" x2="44" y2="59" stroke="#111827" strokeWidth="1.5" />}
        {thriving && (
          <>
            <ellipse cx="24" cy="67" rx="5" ry="6" fill={bodyColor} opacity="0.8" />
            <ellipse cx="56" cy="67" rx="5" ry="6" fill={bodyColor} opacity="0.8" />
          </>
        )}
        {thriving && (
          <motion.g animate={{ opacity: [0, 1, 0] }} transition={{ repeat: Infinity, duration: 1.5 }}>
            <text x="12" y="45" fontSize="8" fill="#fbbf24">✦</text>
            <text x="62" y="45" fontSize="8" fill="#fbbf24">✦</text>
          </motion.g>
        )}
      </motion.g>
    </svg>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// PANCREAS — Diabetic / Blood Sugar
// ══════════════════════════════════════════════════════════════════════════════
function PancreasSVG({ level, health }: { level: number; health: string }) {
  const thriving  = health === 'thriving';
  const wilting   = health === 'wilting';
  const mainColor  = wilting ? '#7c2d12' : thriving ? '#f472b6' : '#fb7185';
  const innerColor = wilting ? '#991b1b' : thriving ? '#fda4af' : '#fecdd3';
  const glowColor  = thriving ? '#f9a8d4' : wilting ? '#7f1d1d' : '#fda4af';

  return (
    <svg viewBox="0 0 80 100" className="w-full h-full">
      <rect x="15" y="10" width="50" height="75" rx="12" fill={wilting ? '#fef2f2' : '#f0fdf4'} opacity="0.5" />
      <motion.g
        animate={{ scale: thriving ? [1, 1.04, 1] : wilting ? [1, 0.98, 1] : [1, 1.02, 1] }}
        transition={{ repeat: Infinity, duration: 2 }}
        style={{ transformOrigin: '40px 50px' }}
      >
        <path
          d="M18 48 Q15 36 25 30 Q35 24 45 28 Q58 24 64 34 Q70 44 64 54 Q58 62 48 60 Q38 64 28 58 Q16 54 18 48 Z"
          fill={mainColor}
        />
        <path
          d="M24 46 Q22 38 30 33 Q38 28 46 32 Q56 28 60 36 Q64 44 60 52 Q56 58 48 56 Q38 60 30 54 Q22 52 24 46 Z"
          fill={innerColor} opacity="0.6"
        />
        {!wilting && (
          <>
            <circle cx="35" cy="40" r={thriving ? 4 : 3} fill={glowColor} opacity={thriving ? 0.9 : 0.6} />
            <circle cx="48" cy="37" r={thriving ? 3.5 : 2.5} fill={glowColor} opacity={thriving ? 0.9 : 0.6} />
            <circle cx="42" cy="50" r={thriving ? 3 : 2} fill={glowColor} opacity={thriving ? 0.9 : 0.6} />
            <circle cx="28" cy="46" r={thriving ? 2.5 : 1.5} fill={glowColor} opacity="0.7" />
          </>
        )}
        {wilting && (
          <>
            <path d="M30 38 L33 44 L30 50" stroke="#7f1d1d" strokeWidth="1.5" fill="none" opacity="0.8" />
            <path d="M45 32 L42 40" stroke="#7f1d1d" strokeWidth="1.5" fill="none" opacity="0.8" />
            <path d="M54 44 L50 52" stroke="#7f1d1d" strokeWidth="1.5" fill="none" opacity="0.8" />
          </>
        )}
        <path d="M22 50 Q40 56 60 50" stroke={wilting ? '#7c2d12' : '#fb923c'} strokeWidth="2" fill="none" />
      </motion.g>
      <rect x="20" y="72" width="40" height="6" rx="3" fill="#e5e7eb" />
      <motion.rect x="20" y="72" width={`${(level / 10) * 40}`} height="6" rx="3"
        fill={wilting ? '#ef4444' : thriving ? '#22c55e' : '#f59e0b'}
        animate={{ width: [`${(level / 10) * 38}`, `${(level / 10) * 40}`, `${(level / 10) * 38}`] }}
        transition={{ repeat: Infinity, duration: 2 }} />
      <text x="20" y="88" fontSize="7" fill="#6b7280">Blood sugar</text>
      <text x="50" y="88" fontSize="7" fill={wilting ? '#ef4444' : thriving ? '#22c55e' : '#f59e0b'} fontWeight="bold">
        {wilting ? 'HIGH' : thriving ? 'OK' : 'Fair'}
      </text>
    </svg>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// FLAME — Keto / Low-carb / Fat-burning
// ══════════════════════════════════════════════════════════════════════════════
function FlameSVG({ level, health }: { level: number; health: string }) {
  const thriving = health === 'thriving';
  const wilting  = health === 'wilting';
  const height   = 20 + level * 5;

  return (
    <svg viewBox="0 0 80 100" className="w-full h-full">
      {thriving && (
        <motion.ellipse cx="40" cy={100 - height / 2} rx="22" ry={height / 2 + 5}
          fill="#fde68a" opacity="0.3"
          animate={{ opacity: [0.2, 0.4, 0.2] }}
          transition={{ repeat: Infinity, duration: 1.5 }} />
      )}
      <motion.path
        d={`M40 ${100 - height - 10} C${38 - level} ${100 - height - 5},${28 - level * 0.5} ${100 - height + 15},30 ${100 - height + height * 0.8} Q28 95 40 96 Q52 95 50 ${100 - height + height * 0.8} C${52 + level * 0.5} ${100 - height + 15},${42 + level} ${100 - height - 5},40 ${100 - height - 10} Z`}
        fill={wilting ? '#9ca3af' : thriving ? '#f97316' : '#fb923c'}
        animate={{ scaleX: [1, 1.05, 0.97, 1] }}
        transition={{ repeat: Infinity, duration: 0.8 }}
        style={{ transformOrigin: '40px 80px' }}
      />
      <motion.path
        d={`M40 ${100 - height + 5} C38 ${100 - height + 8},32 ${100 - height + height * 0.6},34 ${100 - height + height * 0.85} Q35 93 40 93 Q45 93 46 ${100 - height + height * 0.85} C48 ${100 - height + height * 0.6},42 ${100 - height + 8},40 ${100 - height + 5} Z`}
        fill={wilting ? '#6b7280' : thriving ? '#fbbf24' : '#fde68a'}
        animate={{ scaleX: [1, 1.08, 0.95, 1] }}
        transition={{ repeat: Infinity, duration: 0.6, delay: 0.1 }}
        style={{ transformOrigin: '40px 82px' }}
      />
      <motion.circle cx="40" cy={96 - height * 0.2} r={wilting ? 3 : thriving ? 6 : 4}
        fill={wilting ? '#e5e7eb' : '#fffbeb'}
        animate={{ r: [thriving ? 5 : 3, thriving ? 7 : 4, thriving ? 5 : 3] }}
        transition={{ repeat: Infinity, duration: 0.5 }} />
      {thriving && (
        <>
          <motion.circle cx="32" cy={100 - height - 5} r="2" fill="#fbbf24"
            animate={{ y: [-5, -15, -25], opacity: [1, 0.5, 0] }}
            transition={{ repeat: Infinity, duration: 1.2 }} />
          <motion.circle cx="48" cy={100 - height - 2} r="1.5" fill="#f97316"
            animate={{ y: [-5, -12, -20], opacity: [1, 0.5, 0] }}
            transition={{ repeat: Infinity, duration: 1.2, delay: 0.4 }} />
        </>
      )}
      <ellipse cx="40" cy="95" rx="12" ry="3" fill={wilting ? '#6b7280' : '#f97316'} opacity="0.4" />
      <text x="20" y="10" fontSize="8" fill={wilting ? '#9ca3af' : '#f97316'}>
        {wilting ? '💤 Slow burn' : thriving ? '🔥 Fat-burn mode!' : '⚡ Burning'}
      </text>
    </svg>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// HEART — Mediterranean / Balanced
// ══════════════════════════════════════════════════════════════════════════════
function HeartSVG({ level, health }: { level: number; health: string }) {
  const thriving = health === 'thriving';
  const wilting  = health === 'wilting';
  const size     = 14 + level * 2;
  const heartColor = wilting ? '#9ca3af' : thriving ? '#ef4444' : '#f87171';
  const pulse      = thriving ? [1, 1.12, 1, 1.08, 1] : wilting ? [1, 0.98, 1] : [1, 1.06, 1];

  return (
    <svg viewBox="0 0 80 100" className="w-full h-full">
      <motion.path
        d={`M8 70 L20 70 L24 58 L28 80 L32 62 L36 70 L72 70`}
        stroke={wilting ? '#9ca3af' : thriving ? '#ef4444' : '#f87171'}
        strokeWidth="2" fill="none" strokeLinecap="round"
        animate={thriving ? { pathLength: [0, 1] } : {}}
        transition={{ repeat: Infinity, duration: 1.5, ease: 'linear' }}
      />
      <motion.g
        style={{ transformOrigin: '40px 42px' }}
        animate={{ scale: pulse }}
        transition={{ repeat: Infinity, duration: thriving ? 0.8 : 2 }}
      >
        <path
          d={`M40 ${50 + size * 0.4} Q${40 - size * 1.1} ${50 - size * 0.3} ${40 - size * 0.9} ${50 - size * 1} Q${40 - size * 0.9} ${50 - size * 1.8} ${40} ${50 - size * 1.2} Q${40 + size * 0.9} ${50 - size * 1.8} ${40 + size * 0.9} ${50 - size * 1} Q${40 + size * 1.1} ${50 - size * 0.3} 40 ${50 + size * 0.4} Z`}
          fill={heartColor}
        />
        <ellipse cx={40 - size * 0.25} cy={50 - size * 0.8}
          rx={size * 0.2} ry={size * 0.35}
          fill="white" opacity="0.35"
          transform={`rotate(-20, ${40 - size * 0.25}, ${50 - size * 0.8})`} />
      </motion.g>
      <text x="28" y="92" fontSize="8" fill={wilting ? '#9ca3af' : thriving ? '#ef4444' : '#f87171'} fontWeight="bold">
        {wilting ? '♥  Weak' : thriving ? '♥  Strong!' : '♥  Steady'}
      </text>
    </svg>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SCALE (PERSON SILHOUETTE) — Weight Loss
// ══════════════════════════════════════════════════════════════════════════════
function ScaleSVG({ level, health }: { level: number; health: string }) {
  const thriving     = health === 'thriving';
  const wilting      = health === 'wilting';
  const bodyRx       = wilting ? 16 : thriving ? 9 : 12;
  const bodyColor    = wilting ? '#fca5a5' : thriving ? '#86efac' : '#d9f99d';
  const outlineColor = wilting ? '#ef4444' : thriving ? '#22c55e' : '#84cc16';

  return (
    <svg viewBox="0 0 80 100" className="w-full h-full">
      <motion.g
        style={{ transformOrigin: '40px 55px' }}
        animate={{ scaleX: [1, wilting ? 1.02 : 0.99, 1] }}
        transition={{ repeat: Infinity, duration: 3 }}
      >
        <circle cx="40" cy="22" r={thriving ? 10 : wilting ? 11 : 10.5} fill={bodyColor} stroke={outlineColor} strokeWidth="1.5" />
        {thriving
          ? <path d="M35 24 Q40 28 45 24" stroke={outlineColor} strokeWidth="1.5" fill="none" />
          : wilting
          ? <path d="M35 26 Q40 22 45 26" stroke={outlineColor} strokeWidth="1.5" fill="none" />
          : <line x1="36" y1="25" x2="44" y2="25" stroke={outlineColor} strokeWidth="1.5" />}
        <circle cx="37" cy="21" r="1.5" fill={outlineColor} />
        <circle cx="43" cy="21" r="1.5" fill={outlineColor} />
        <motion.ellipse cx="40" cy="58" rx={bodyRx} ry={wilting ? 20 : thriving ? 22 : 21}
          fill={bodyColor} stroke={outlineColor} strokeWidth="1.5"
          animate={{ rx: [bodyRx, bodyRx + (wilting ? 1 : -0.5), bodyRx] }}
          transition={{ repeat: Infinity, duration: 3 }} />
        <line x1={40 - bodyRx} y1="50" x2={40 - bodyRx - (wilting ? 6 : 8)} y2="68"
          stroke={outlineColor} strokeWidth="4" strokeLinecap="round" />
        <line x1={40 + bodyRx} y1="50" x2={40 + bodyRx + (wilting ? 6 : 8)} y2="68"
          stroke={outlineColor} strokeWidth="4" strokeLinecap="round" />
        <line x1="35" y1="78" x2="30" y2="95" stroke={outlineColor} strokeWidth="4" strokeLinecap="round" />
        <line x1="45" y1="78" x2="50" y2="95" stroke={outlineColor} strokeWidth="4" strokeLinecap="round" />
      </motion.g>
      <text x="22" y="10" fontSize="8" fill={wilting ? '#ef4444' : thriving ? '#16a34a' : '#65a30d'} fontWeight="bold">
        {wilting ? '⬆ Gaining' : thriving ? '🎯 Goal hit!' : `⬇ -${Math.floor(level * 0.3)} kg`}
      </text>
    </svg>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// SPROUT — Vegan / default plant
// ══════════════════════════════════════════════════════════════════════════════
function SproutSVG({ level, health }: { level: number; health: string }) {
  const baseColor = health === 'thriving' ? '#15803d' : health === 'growing' ? '#16a34a' : health === 'alive' ? '#22c55e' : '#94a3b8';
  const leafColor = health === 'thriving' ? '#22c55e' : health === 'growing' ? '#4ade80' : health === 'alive' ? '#86efac' : '#cbd5e1';
  const wilt      = health === 'wilting';

  return (
    <svg viewBox="0 0 80 100" className="w-full h-full">
      <rect x="25" y="82" width="30" height="18" rx="4" fill="#d97706" />
      <rect x="22" y="80" width="36" height="6" rx="3" fill="#b45309" />
      <ellipse cx="40" cy="83" rx="14" ry="4" fill="#78350f" />
      <motion.path d={`M40 80 Q${wilt ? '42' : '38'} ${80 - level * 6} 40 ${80 - level * 7}`}
        stroke={baseColor} strokeWidth="3" fill="none" strokeLinecap="round"
        animate={wilt ? { rotate: [0, 8, 0] } : {}}
        transition={{ repeat: Infinity, duration: 3 }} />
      {level >= 1 && (
        <motion.ellipse cx={wilt ? 52 : 30} cy={80 - level * 5} rx="10" ry="6" fill={leafColor}
          style={{ transformOrigin: '40px 80px' }}
          animate={{ rotate: wilt ? [0, 5, 0] : [-3, 3, -3] }}
          transition={{ repeat: Infinity, duration: 3 }} />
      )}
      {level >= 2 && (
        <motion.ellipse cx={wilt ? 28 : 52} cy={80 - level * 6} rx="10" ry="6" fill={leafColor}
          animate={{ rotate: wilt ? [0, -5, 0] : [3, -3, 3] }}
          transition={{ repeat: Infinity, duration: 3, delay: 0.5 }} />
      )}
      {level >= 4 && (
        <motion.ellipse cx={wilt ? 50 : 28} cy={80 - level * 7 + 4} rx="12" ry="7" fill={leafColor}
          animate={{ rotate: wilt ? [0, 5, 0] : [-2, 2, -2] }}
          transition={{ repeat: Infinity, duration: 2.5, delay: 0.3 }} />
      )}
      {level >= 6 && (
        <motion.ellipse cx={wilt ? 30 : 54} cy={80 - level * 7 + 6} rx="12" ry="7" fill={leafColor}
          animate={{ rotate: [3, -3, 3] }}
          transition={{ repeat: Infinity, duration: 2.5, delay: 0.8 }} />
      )}
      {level >= 8 && (
        <>
          <motion.ellipse cx="36" cy={80 - level * 7 + 10} rx="14" ry="8" fill={leafColor}
            animate={{ rotate: [-2, 2, -2] }}
            transition={{ repeat: Infinity, duration: 3 }} />
          <motion.ellipse cx="46" cy={80 - level * 7 + 12} rx="14" ry="8" fill={leafColor}
            animate={{ rotate: [2, -2, 2] }}
            transition={{ repeat: Infinity, duration: 3, delay: 0.4 }} />
        </>
      )}
      {level >= 9 && (
        <motion.g animate={{ scale: [1, 1.1, 1] }} transition={{ repeat: Infinity, duration: 2 }}>
          <circle cx="40" cy={80 - level * 7 - 4} r="6" fill="#fbbf24" />
          <circle cx="40" cy={80 - level * 7 - 4} r="3" fill="#f59e0b" />
        </motion.g>
      )}
    </svg>
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// AVATAR SELECTOR
// ══════════════════════════════════════════════════════════════════════════════
const AVATAR_TITLES: Record<string, string> = {
  muscle_growth: '🦍 Your Gorilla',
  diabetic:      '🩺 Your Pancreas',
  keto:          '🔥 Ketone Burn',
  low_carb:      '🔥 Fat Flame',
  weight_loss:   '⚖️ Your Body',
  vegan:         '🌱 Your Plant',
  mediterranean: '❤️ Your Heart',
  balanced:      '🌿 Your Plant',
};

function AvatarSVG({ goal, level, health }: { goal: string; level: number; health: string }) {
  switch (goal) {
    case 'muscle_growth': return <GorillaSVG level={level} health={health} />;
    case 'diabetic':      return <PancreasSVG level={level} health={health} />;
    case 'keto':
    case 'low_carb':      return <FlameSVG level={level} health={health} />;
    case 'weight_loss':   return <ScaleSVG level={level} health={health} />;
    case 'mediterranean': return <HeartSVG level={level} health={health} />;
    default:              return <SproutSVG level={level} health={health} />;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// MAIN EXPORT  (prop name kept as `streak` for backward compatibility)
// ══════════════════════════════════════════════════════════════════════════════
export default function PlantWidget({ streak, goal }: PlantWidgetProps) {
  const { current_streak, plant_level, plant_health } = streak;
  const { text, color } = HEALTH_LABEL[plant_health] ?? HEALTH_LABEL.alive;
  const resolvedGoal = goal ?? 'balanced';
  const title = AVATAR_TITLES[resolvedGoal] ?? '🌿 Your Plant';

  return (
    <div className="flex flex-col items-center gap-2">
      <p className="text-xs font-semibold text-gray-400 uppercase tracking-wide">{title}</p>
      <div className="w-28 h-36">
        <AvatarSVG goal={resolvedGoal} level={plant_level} health={plant_health} />
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
