/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        green: {
          50:  '#f0fdf4',
          100: '#dcfce7',
          200: '#bbf7d0',
          300: '#86efac',
          400: '#4ade80',
          500: '#22c55e',
          600: '#16a34a',
          700: '#15803d',
          800: '#166534',
          900: '#14532d',
        },
      },
      fontFamily: {
        sans: ['Inter', 'system-ui', 'sans-serif'],
      },
      animation: {
        'spin-slow': 'spin 2s linear infinite',
        'pulse-gentle': 'pulse 3s ease-in-out infinite',
        'sway': 'sway 3s ease-in-out infinite',
        'grow': 'grow 0.5s ease-out forwards',
        'wilt': 'wilt 1s ease-in-out forwards',
      },
      keyframes: {
        sway: {
          '0%, 100%': { transform: 'rotate(-2deg)' },
          '50%':       { transform: 'rotate(2deg)' },
        },
        grow: {
          from: { transform: 'scaleY(0)', transformOrigin: 'bottom' },
          to:   { transform: 'scaleY(1)', transformOrigin: 'bottom' },
        },
        wilt: {
          '0%, 100%': { transform: 'rotate(0deg)' },
          '50%':       { transform: 'rotate(15deg)' },
        },
      },
    },
  },
  plugins: [],
}
