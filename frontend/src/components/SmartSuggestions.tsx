import { Lightbulb } from 'lucide-react';

interface SmartSuggestionsProps {
  suggestions: string[];
}

export default function SmartSuggestions({ suggestions }: SmartSuggestionsProps) {
  if (!suggestions || suggestions.length === 0) return null;

  return (
    <div className="space-y-2">
      {suggestions.map((s, i) => (
        <div key={i} className="flex gap-3 bg-green-50 border border-green-100 rounded-xl p-3">
          <Lightbulb className="w-4 h-4 text-green-600 mt-0.5 shrink-0" />
          <p className="text-sm text-gray-700">{s}</p>
        </div>
      ))}
    </div>
  );
}
