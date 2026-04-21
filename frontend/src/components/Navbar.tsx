import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import {
  LayoutDashboard, Camera, Droplets, BarChart3,
  ShoppingCart, User, Leaf, Menu, X,
} from 'lucide-react';
import { useState } from 'react';

const NAV_ITEMS = [
  { to: '/dashboard',  label: 'Dashboard',  Icon: LayoutDashboard },
  { to: '/log-food',   label: 'Log Food',   Icon: Camera          },
  { to: '/log-liquid', label: 'Hydration',  Icon: Droplets        },
  { to: '/analytics',  label: 'Analytics',  Icon: BarChart3       },
  { to: '/grocery',    label: 'Grocery',    Icon: ShoppingCart    },
];

export default function Navbar() {
  const { user } = useAuth();
  const location = useLocation();
  const [open, setOpen] = useState(false);

  return (
    <header className="bg-white border-b border-green-100 sticky top-0 z-40 shadow-sm">
      <div className="max-w-5xl mx-auto px-4 h-16 flex items-center justify-between">
        {/* Logo */}
        <Link to="/dashboard" className="flex items-center gap-2 font-bold text-green-700 text-xl">
          <div className="w-8 h-8 bg-green-600 rounded-xl flex items-center justify-center">
            <Leaf className="w-5 h-5 text-white" />
          </div>
          NutriLens
        </Link>

        {/* Desktop nav */}
        <nav className="hidden md:flex items-center gap-1">
          {NAV_ITEMS.map(({ to, label, Icon }) => {
            const active = location.pathname === to;
            return (
              <Link
                key={to}
                to={to}
                className={`flex items-center gap-1.5 px-3 py-2 rounded-lg text-sm font-medium transition-colors
                  ${active
                    ? 'bg-green-600 text-white'
                    : 'text-gray-600 hover:bg-green-50 hover:text-green-700'
                  }`}
              >
                <Icon className="w-4 h-4" />
                {label}
              </Link>
            );
          })}
        </nav>

        {/* Right: profile */}
        <div className="flex items-center gap-2">
          <Link
            to="/profile"
            className={`flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-medium transition-colors
              ${location.pathname === '/profile'
                ? 'bg-green-600 text-white'
                : 'text-gray-600 hover:bg-green-50 hover:text-green-700'
              }`}
          >
            <div className="w-7 h-7 bg-green-100 rounded-full flex items-center justify-center">
              <User className="w-4 h-4 text-green-700" />
            </div>
            <span className="hidden md:inline">{user?.username}</span>
          </Link>

          {/* Mobile menu toggle */}
          <button
            className="md:hidden p-2 rounded-lg text-gray-600 hover:bg-green-50"
            onClick={() => setOpen(!open)}
          >
            {open ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
          </button>
        </div>
      </div>

      {/* Mobile drawer */}
      {open && (
        <div className="md:hidden bg-white border-t border-green-100 px-4 py-3 space-y-1">
          {NAV_ITEMS.map(({ to, label, Icon }) => {
            const active = location.pathname === to;
            return (
              <Link
                key={to}
                to={to}
                onClick={() => setOpen(false)}
                className={`flex items-center gap-2 px-3 py-2.5 rounded-lg text-sm font-medium
                  ${active ? 'bg-green-600 text-white' : 'text-gray-700 hover:bg-green-50'}`}
              >
                <Icon className="w-4 h-4" />
                {label}
              </Link>
            );
          })}
        </div>
      )}
    </header>
  );
}
