import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuth } from './contexts/AuthContext';
import Layout from './components/Layout';
import LoadingSpinner from './components/LoadingSpinner';

import Login      from './pages/Login';
import Register   from './pages/Register';
import Onboarding from './pages/Onboarding';
import Dashboard  from './pages/Dashboard';
import LogFood    from './pages/LogFood';
import LogLiquid  from './pages/LogLiquid';
import Analytics  from './pages/Analytics';
import GroceryList from './pages/GroceryList';
import Profile    from './pages/Profile';

function PrivateRoute({ children }: { children: React.ReactNode }) {
  const { token, isLoading } = useAuth();
  if (isLoading) return <div className="min-h-screen flex items-center justify-center"><LoadingSpinner size="lg" /></div>;
  return token ? <>{children}</> : <Navigate to="/login" replace />;
}

function PublicRoute({ children }: { children: React.ReactNode }) {
  const { token, isLoading } = useAuth();
  if (isLoading) return <div className="min-h-screen flex items-center justify-center"><LoadingSpinner size="lg" /></div>;
  return !token ? <>{children}</> : <Navigate to="/dashboard" replace />;
}

export default function App() {
  return (
    <Routes>
      {/* Public routes */}
      <Route path="/login"    element={<PublicRoute><Login /></PublicRoute>} />
      <Route path="/register" element={<PublicRoute><Register /></PublicRoute>} />

      {/* Onboarding (authenticated but goal not yet set) */}
      <Route path="/onboarding" element={<PrivateRoute><Onboarding /></PrivateRoute>} />

      {/* Protected routes inside Layout */}
      <Route element={<PrivateRoute><Layout /></PrivateRoute>}>
        <Route index              element={<Navigate to="/dashboard" replace />} />
        <Route path="/dashboard"  element={<Dashboard />} />
        <Route path="/log-food"   element={<LogFood />} />
        <Route path="/log-liquid" element={<LogLiquid />} />
        <Route path="/analytics"  element={<Analytics />} />
        <Route path="/grocery"    element={<GroceryList />} />
        <Route path="/profile"    element={<Profile />} />
      </Route>

      <Route path="*" element={<Navigate to="/dashboard" replace />} />
    </Routes>
  );
}
