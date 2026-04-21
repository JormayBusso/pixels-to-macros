interface LoadingSpinnerProps {
  size?: 'sm' | 'md' | 'lg';
  label?: string;
}

const SIZE_MAP = { sm: 'w-5 h-5', md: 'w-8 h-8', lg: 'w-14 h-14' };

export default function LoadingSpinner({ size = 'md', label }: LoadingSpinnerProps) {
  return (
    <div className="flex flex-col items-center gap-3">
      <div
        className={`${SIZE_MAP[size]} border-4 border-green-200 border-t-green-600 rounded-full animate-spin`}
        role="status"
        aria-label="Loading"
      />
      {label && <p className="text-sm text-gray-500 animate-pulse">{label}</p>}
    </div>
  );
}
