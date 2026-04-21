// Shared TypeScript types for NutriLens

export interface User {
  id: number;
  email: string;
  username: string;
  dietary_goal: string | null;
  caloric_target: number | null;
  gamification_icon: string;
}

export interface NutrientValue {
  value: number;
  unit: string;
}

export interface FoodLog {
  id: number;
  date: string;
  food_name: string;
  matched_food: string | null;
  fdc_id: number | null;
  weight_g: number;
  meal_type: string;
  nutrients: Record<string, NutrientValue>;
}

export interface LiquidLog {
  id: number;
  date: string;
  liquid_type: string;
  amount_ml: number;
  created_at: string;
}

export interface VitaminStatus {
  key: string;
  name: string;
  current: number;
  rdv: number;
  unit: string;
  percentage: number;
  status: 'sufficient' | 'low' | 'deficient';
}

export interface StreakInfo {
  current_streak: number;
  plant_level: number;
  plant_health: 'thriving' | 'growing' | 'alive' | 'wilting';
}

export interface DailySummary {
  date: string;
  food_logs: FoodLog[];
  liquid_logs: LiquidLog[];
  totals: Record<string, NutrientValue>;
  total_water_ml: number;
  total_liquid_ml: number;
  vitamin_status: VitaminStatus[];
  suggestions: string[];
  goal_met: boolean;
  caloric_target: number;
  streak: StreakInfo;
}

export interface BarcodeProduct {
  barcode: string;
  product_name: string;
  brand: string;
  serving_size_g: number;
  nutrients_per_100g: Record<string, number>;
  image_url: string;
}

export interface GroceryItem {
  item: string;
  reason: string;
  category: string;
  priority: 'high' | 'medium' | 'low';
}

export interface HistoryEntry {
  date: string;
  calories: number;
  protein: number;
  carbohydrates: number;
  fat: number;
  goal_met: boolean;
}

export const DIETARY_GOALS = [
  { value: 'balanced',      label: 'Balanced',         description: 'General healthy eating',          icon: '⚖️' },
  { value: 'muscle_growth', label: 'Muscle Growth',    description: 'High protein for building muscle', icon: '💪' },
  { value: 'weight_loss',   label: 'Weight Loss',      description: 'Calorie deficit for fat loss',     icon: '🎯' },
  { value: 'low_carb',      label: 'Low Carb',         description: 'Reduced carbohydrate intake',      icon: '🥩' },
  { value: 'keto',          label: 'Ketogenic',        description: 'Very low carb, high fat',          icon: '🥑' },
  { value: 'diabetic',      label: 'Diabetic Friendly', description: 'Blood sugar management',          icon: '🩺' },
  { value: 'vegan',         label: 'Vegan',            description: 'Plant-based nutrition',            icon: '🌱' },
  { value: 'mediterranean', label: 'Mediterranean',    description: 'Heart-healthy diet',               icon: '🫒' },
] as const;

export const MEAL_TYPES   = ['breakfast', 'lunch', 'dinner', 'snack', 'other'] as const;
export const LIQUID_TYPES = ['water', 'coffee', 'tea', 'juice', 'milk', 'soda', 'smoothie', 'sports_drink', 'other'] as const;

export const MEAL_COLORS: Record<string, string> = {
  breakfast: 'bg-amber-100 text-amber-700',
  lunch:     'bg-blue-100 text-blue-700',
  dinner:    'bg-purple-100 text-purple-700',
  snack:     'bg-green-100 text-green-700',
  other:     'bg-gray-100 text-gray-600',
};
