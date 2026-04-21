import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Leaf, ChevronRight, Target } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import api from '../services/api';
import { DIETARY_GOALS } from '../types';

export default function Onboarding() {
  const { refreshUser } = useAuth();
  const navigate         = useNavigate();
  const [step, setStep]  = useState<1 | 2>(1);
  const [goal, setGoal]  = useState('');
  const [calories, setCalories] = useState('');
  const [saving, setSaving]     = useState(false);
  const [error, setError]       = useState('');

  const handleFinish = async () => {
    if (!goal) { setError('Please choose a dietary goal'); return; }
    setError('');
    setSaving(true);
    try {
      const cal = calories ? parseInt(calories, 10) : null;
      if (cal !== null && (cal < 500 || cal > 10_000)) {
        setError('Calorie target must be between 500 and 10 000');
        setSaving(false);
        return;
      }
      await api.put('/users/goals', { dietary_goal: goal, caloric_target: cal });
      await refreshUser();
      navigate('/dashboard');
    } catch (err: any) {
      setError(err.response?.data?.detail ?? 'Something went wrong');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-green-50 to-green-100 flex items-center justify-center p-4">
      <div className="w-full max-w-lg">
        {/* Header */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-green-600 rounded-2xl mb-4 shadow-lg">
            <Leaf className="w-9 h-9 text-white" />
          </div>
          <h1 className="text-2xl font-bold text-gray-900">Set up your profile</h1>
          <p className="text-gray-500 mt-1 text-sm">Step {step} of 2</p>
          {/* Progress bar */}
          <div className="w-40 mx-auto mt-3 h-1.5 bg-green-100 rounded-full overflow-hidden">
            <div
              className="h-full bg-green-500 rounded-full transition-all duration-500"
              style={{ width: step === 1 ? '50%' : '100%' }}
            />
          </div>
        </div>

        <div className="card shadow-lg">
          {/* Step 1: Goal selection */}
          {step === 1 && (
            <>
              <h2 className="text-xl font-bold text-gray-900 mb-1">What's your dietary goal?</h2>
              <p className="text-sm text-gray-500 mb-5">
                This helps us tailor your nutrition recommendations.
              </p>
              <div className="grid grid-cols-2 gap-3">
                {DIETARY_GOALS.map(({ value, label, description, icon }) => (
                  <button
                    key={value}
                    onClick={() => setGoal(value)}
                    className={`rounded-xl border-2 p-3 text-left transition-all
                      ${goal === value
                        ? 'border-green-500 bg-green-50'
                        : 'border-gray-200 hover:border-green-300 hover:bg-green-50'
                      }`}
                  >
                    <span className="text-2xl">{icon}</span>
                    <p className="text-sm font-semibold text-gray-800 mt-1">{label}</p>
                    <p className="text-xs text-gray-500 mt-0.5">{description}</p>
                  </button>
                ))}
              </div>
              {error && <p className="text-red-500 text-sm mt-3">{error}</p>}
              <button
                onClick={() => { if (!goal) { setError('Please choose a goal'); return; } setError(''); setStep(2); }}
                className="btn-primary w-full mt-5 flex items-center justify-center gap-2"
              >
                Continue <ChevronRight className="w-4 h-4" />
              </button>
            </>
          )}

          {/* Step 2: Calorie target */}
          {step === 2 && (
            <>
              <h2 className="text-xl font-bold text-gray-900 mb-1">Daily calorie target</h2>
              <p className="text-sm text-gray-500 mb-5">
                This is optional — we'll calculate a sensible default for your goal if you skip it.
              </p>
              <div className="bg-green-50 rounded-xl p-4 mb-5">
                <div className="flex items-center gap-2 mb-1">
                  <Target className="w-4 h-4 text-green-600" />
                  <span className="text-sm font-medium text-green-700">
                    Your goal: {DIETARY_GOALS.find((g) => g.value === goal)?.label}
                  </span>
                </div>
              </div>
              <div>
                <label className="label">Daily calories (kcal) — optional</label>
                <input
                  type="number"
                  min={500}
                  max={10000}
                  value={calories}
                  onChange={(e) => setCalories(e.target.value)}
                  className="input-field"
                  placeholder="e.g. 2000"
                />
                <p className="text-xs text-gray-400 mt-1">Leave blank to use smart defaults (500–10 000 kcal)</p>
              </div>
              {error && <p className="text-red-500 text-sm mt-3">{error}</p>}
              <div className="flex gap-3 mt-5">
                <button onClick={() => setStep(1)} className="btn-secondary flex-1">Back</button>
                <button onClick={handleFinish} disabled={saving} className="btn-primary flex-1">
                  {saving ? 'Saving…' : 'Get started!'}
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
