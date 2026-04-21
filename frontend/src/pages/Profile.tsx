import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { useNavigate } from 'react-router-dom';
import { User, Eye, EyeOff, Check, LogOut, Settings } from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';
import api from '../services/api';
import { DIETARY_GOALS } from '../types';

// ── Password change schema ─────────────────────────────────────────────────
const pwSchema = z.object({
  current_password: z.string().min(1, 'Required'),
  new_password: z
    .string()
    .min(8, 'At least 8 characters')
    .regex(/[A-Z]/, 'Must include uppercase')
    .regex(/[0-9]/, 'Must include a number'),
  confirm_password: z.string(),
}).refine((d) => d.new_password === d.confirm_password, {
  message: 'Passwords do not match',
  path: ['confirm_password'],
});
type PwForm = z.infer<typeof pwSchema>;

export default function Profile() {
  const { user, refreshUser, logout } = useAuth();
  const [tab, setTab] = useState<'profile' | 'goals' | 'password'>('profile');
  const navigate = useNavigate();

  const handleLogout = () => {
    logout();
    navigate('/login');
  };

  return (
    <div className="space-y-4 max-w-lg">
      {/* Header */}
      <div className="flex items-center gap-3">
        <div className="w-12 h-12 bg-green-100 rounded-2xl flex items-center justify-center">
          <Settings className="w-6 h-6 text-green-700" />
        </div>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Settings</h1>
          <p className="text-sm text-gray-500">{user?.email}</p>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 bg-white rounded-xl p-1 shadow-sm border border-green-100">
        {([
          { key: 'profile',  label: 'Profile'  },
          { key: 'goals',    label: 'Goals'    },
          { key: 'password', label: 'Password' },
        ] as const).map(({ key, label }) => (
          <button
            key={key}
            onClick={() => setTab(key)}
            className={`flex-1 py-2.5 rounded-lg text-sm font-medium transition-all
              ${tab === key ? 'bg-green-600 text-white' : 'text-gray-600 hover:bg-green-50'}`}
          >
            {label}
          </button>
        ))}
      </div>

      {tab === 'profile'  && <ProfileTab  user={user!} onRefresh={refreshUser} />}
      {tab === 'goals'    && <GoalsTab    user={user!} onRefresh={refreshUser} />}
      {tab === 'password' && <PasswordTab />}

      {/* ── Logout ──────────────────────────────────────────────────────── */}
      <div className="pt-4 border-t border-gray-100">
        <button
          onClick={handleLogout}
          className="w-full flex items-center justify-center gap-2 py-3 px-4 rounded-xl
            bg-red-50 text-red-600 font-semibold hover:bg-red-100
            border border-red-200 transition-colors"
        >
          <LogOut className="w-5 h-5" />
          Sign out
        </button>
        <p className="text-center text-xs text-gray-400 mt-2">
          Signed in as <span className="font-medium">{user?.username}</span>
        </p>
      </div>
    </div>
  );
}

// ── Profile Tab ───────────────────────────────────────────────────────────────
function ProfileTab({ user, onRefresh }: { user: any; onRefresh: () => Promise<void> }) {
  const [username, setUsername]   = useState(user.username);
  const [saving, setSaving]       = useState(false);
  const [msg, setMsg]             = useState('');
  const [error, setError]         = useState('');

  const handleSave = async () => {
    setSaving(true); setMsg(''); setError('');
    try {
      await api.put('/users/me', { username });
      await onRefresh();
      setMsg('Profile updated!');
    } catch (e: any) {
      setError(e.response?.data?.detail ?? 'Update failed');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="card space-y-4">
      <div className="flex items-center gap-3">
        <div className="w-14 h-14 bg-green-100 rounded-full flex items-center justify-center">
          <User className="w-8 h-8 text-green-600" />
        </div>
        <div>
          <p className="font-bold text-gray-900">{user.username}</p>
          <p className="text-sm text-gray-500">{user.email}</p>
        </div>
      </div>

      <div>
        <label className="label">Username</label>
        <input
          className="input-field"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
        />
      </div>

      {msg   && <p className="text-green-600 text-sm flex items-center gap-1"><Check className="w-4 h-4" /> {msg}</p>}
      {error && <p className="text-red-500 text-sm">{error}</p>}

      <button onClick={handleSave} disabled={saving} className="btn-primary w-full">
        {saving ? 'Saving…' : 'Save changes'}
      </button>
    </div>
  );
}

// ── Goals Tab ─────────────────────────────────────────────────────────────────
function GoalsTab({ user, onRefresh }: { user: any; onRefresh: () => Promise<void> }) {
  const [goal, setGoal]           = useState(user.dietary_goal ?? 'balanced');
  const [calories, setCalories]   = useState(String(user.caloric_target ?? ''));
  const [saving, setSaving]       = useState(false);
  const [msg, setMsg]             = useState('');
  const [error, setError]         = useState('');

  const handleSave = async () => {
    setSaving(true); setMsg(''); setError('');
    const cal = calories ? parseInt(calories, 10) : null;
    if (cal !== null && (cal < 500 || cal > 10_000)) {
      setError('Calorie target must be 500–10 000');
      setSaving(false);
      return;
    }
    try {
      await api.put('/users/goals', { dietary_goal: goal, caloric_target: cal });
      await onRefresh();
      setMsg('Goals updated!');
    } catch (e: any) {
      setError(e.response?.data?.detail ?? 'Update failed');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="card space-y-4">
      <div>
        <label className="label">Dietary goal</label>
        <div className="grid grid-cols-2 gap-2">
          {DIETARY_GOALS.map(({ value, label, icon }) => (
            <button
              key={value}
              onClick={() => setGoal(value)}
              className={`flex items-center gap-2 p-2.5 rounded-xl border-2 text-left transition-all
                ${goal === value ? 'border-green-500 bg-green-50' : 'border-gray-200 hover:border-green-300'}`}
            >
              <span>{icon}</span>
              <span className="text-sm font-medium text-gray-700">{label}</span>
            </button>
          ))}
        </div>
      </div>

      <div>
        <label className="label">Daily calorie target (kcal) — optional</label>
        <input
          type="number"
          min={500}
          max={10000}
          className="input-field"
          value={calories}
          onChange={(e) => setCalories(e.target.value)}
          placeholder="e.g. 2000"
        />
        <p className="text-xs text-gray-400 mt-1">Leave blank to use smart defaults</p>
      </div>

      {msg   && <p className="text-green-600 text-sm flex items-center gap-1"><Check className="w-4 h-4" /> {msg}</p>}
      {error && <p className="text-red-500 text-sm">{error}</p>}

      <button onClick={handleSave} disabled={saving} className="btn-primary w-full">
        {saving ? 'Saving…' : 'Update goals'}
      </button>
    </div>
  );
}

// ── Password Tab ─────────────────────────────────────────────────────────────
function PasswordTab() {
  const [showPw, setShowPw] = useState(false);
  const [msg, setMsg]       = useState('');
  const [apiErr, setApiErr] = useState('');

  const { register, handleSubmit, reset, formState: { errors, isSubmitting } } = useForm<PwForm>({
    resolver: zodResolver(pwSchema),
  });

  const onSubmit = async (data: PwForm) => {
    setMsg(''); setApiErr('');
    try {
      await api.post('/auth/change-password', {
        current_password: data.current_password,
        new_password: data.new_password,
      });
      setMsg('Password changed successfully!');
      reset();
    } catch (e: any) {
      setApiErr(e.response?.data?.detail ?? 'Failed to change password');
    }
  };

  return (
    <div className="card space-y-4">
      <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
        <div>
          <label className="label">Current password</label>
          <div className="relative">
            <input
              {...register('current_password')}
              type={showPw ? 'text' : 'password'}
              className="input-field pr-10"
              placeholder="••••••••"
            />
            <button
              type="button"
              onClick={() => setShowPw(!showPw)}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600"
            >
              {showPw ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
            </button>
          </div>
          {errors.current_password && <p className="text-red-500 text-xs mt-1">{errors.current_password.message}</p>}
        </div>

        <div>
          <label className="label">New password</label>
          <input {...register('new_password')} type="password" className="input-field" placeholder="••••••••" />
          {errors.new_password && <p className="text-red-500 text-xs mt-1">{errors.new_password.message}</p>}
        </div>

        <div>
          <label className="label">Confirm new password</label>
          <input {...register('confirm_password')} type="password" className="input-field" placeholder="••••••••" />
          {errors.confirm_password && <p className="text-red-500 text-xs mt-1">{errors.confirm_password.message}</p>}
        </div>

        {msg    && <p className="text-green-600 text-sm flex items-center gap-1"><Check className="w-4 h-4" /> {msg}</p>}
        {apiErr && <p className="text-red-500 text-sm">{apiErr}</p>}

        <button type="submit" disabled={isSubmitting} className="btn-primary w-full">
          {isSubmitting ? 'Changing…' : 'Change password'}
        </button>
      </form>
    </div>
  );
}
