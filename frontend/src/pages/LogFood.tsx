import { useEffect, useRef, useState } from 'react';
import { Camera, Edit3, Barcode, Upload, RotateCcw, Plus, Check, Search } from 'lucide-react';
import api from '../services/api';
import LoadingSpinner from '../components/LoadingSpinner';
import { getFoodIcon } from '../utils/foodIcons';
import { MEAL_TYPES } from '../types';
import type { BarcodeProduct } from '../types';

type Tab = 'camera' | 'manual' | 'barcode';

interface AnalyzedItem {
  name: string;
  weight_g: number;
  matched_food: string;
  nutrients: Record<string, { value: number; unit: string }>;
}

export default function LogFood() {
  const [tab, setTab] = useState<Tab>('camera');

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold text-gray-900">Log Food</h1>

      {/* Tabs */}
      <div className="flex gap-1 bg-white rounded-xl p-1 shadow-sm border border-green-100">
        {([
          { key: 'camera', label: 'Camera AI', Icon: Camera },
          { key: 'manual', label: 'Manual',    Icon: Edit3   },
          { key: 'barcode', label: 'Barcode',  Icon: Barcode },
        ] as const).map(({ key, label, Icon }) => (
          <button
            key={key}
            onClick={() => setTab(key)}
            className={`flex-1 flex items-center justify-center gap-1.5 py-2.5 rounded-lg text-sm font-medium transition-all
              ${tab === key ? 'bg-green-600 text-white shadow-sm' : 'text-gray-600 hover:bg-green-50'}`}
          >
            <Icon className="w-4 h-4" /> {label}
          </button>
        ))}
      </div>

      {tab === 'camera' && <CameraTab />}
      {tab === 'manual' && <ManualTab />}
      {tab === 'barcode' && <BarcodeTab />}
    </div>
  );
}

// ── Camera Tab ────────────────────────────────────────────────────────────────
function CameraTab() {
  const [step, setStep]         = useState<'capture' | 'review'>('capture');
  const [captureStep, setCaptureStep] = useState<'top' | 'side'>('top');
  const [topImg, setTopImg]     = useState<string | null>(null);
  const [sideImg, setSideImg]   = useState<string | null>(null);
  const [stream, setStream]     = useState<MediaStream | null>(null);
  const [analyzing, setAnalyzing] = useState(false);
  const [items, setItems]       = useState<AnalyzedItem[]>([]);
  const [mealType, setMealType] = useState('other');
  const [saved, setSaved]       = useState(false);
  const [error, setError]       = useState('');
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    startCamera();
    return () => { stream?.getTracks().forEach((t) => t.stop()); };
  }, []);

  const startCamera = async () => {
    try {
      const s = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
      setStream(s);
      if (videoRef.current) videoRef.current.srcObject = s;
    } catch {
      setError('Camera access denied. Please allow camera permissions.');
    }
  };

  const capturePhoto = () => {
    if (!videoRef.current || !canvasRef.current) return;
    const v = videoRef.current;
    const c = canvasRef.current;
    c.width  = v.videoWidth;
    c.height = v.videoHeight;
    c.getContext('2d')!.drawImage(v, 0, 0);
    const data = c.toDataURL('image/jpeg', 0.85);

    if (captureStep === 'top') {
      setTopImg(data);
      setCaptureStep('side');
    } else {
      setSideImg(data);
      stream?.getTracks().forEach((t) => t.stop());
      analyzeImages(topImg!, data);
    }
  };

  const analyzeImages = async (top: string, side: string) => {
    setAnalyzing(true);
    setStep('review');
    try {
      const topBlob  = await (await fetch(top)).blob();
      const sideBlob = await (await fetch(side)).blob();
      const form = new FormData();
      form.append('top_image',  new File([topBlob],  'top.jpg',  { type: 'image/jpeg' }));
      form.append('side_image', new File([sideBlob], 'side.jpg', { type: 'image/jpeg' }));
      form.append('plate_diameter_cm', '26');
      const res = await api.post('/analyze', form);
      setItems(res.data.items.map((i: any) => ({
        name: i.name,
        weight_g: i.weight_g,
        matched_food: i.matched_food,
        nutrients: i.nutrients,
      })));
    } catch (e: any) {
      setError(e.response?.data?.detail ?? 'Analysis failed. Please retake the photos.');
      setStep('capture');
    } finally {
      setAnalyzing(false);
    }
  };

  const handleRetake = () => {
    setTopImg(null); setSideImg(null);
    setCaptureStep('top'); setStep('capture');
    setItems([]); setError('');
    startCamera();
  };

  const handleSave = async () => {
    for (const item of items) {
      await api.post('/logs/food', {
        food_name: item.name,
        weight_g: item.weight_g,
        meal_type: mealType,
        nutrients: item.nutrients,
      });
    }
    setSaved(true);
  };

  if (step === 'capture' && !analyzing) {
    return (
      <div className="card space-y-4">
        <div className="flex items-center gap-2 mb-2">
          <div className={`w-7 h-7 rounded-full flex items-center justify-center text-sm font-bold ${captureStep === 'top' ? 'bg-green-600 text-white' : 'bg-green-100 text-green-600'}`}>1</div>
          <div className="flex-1 h-1 bg-green-100 rounded-full">
            <div className={`h-full bg-green-500 rounded-full transition-all ${captureStep === 'side' ? 'w-full' : 'w-0'}`} />
          </div>
          <div className={`w-7 h-7 rounded-full flex items-center justify-center text-sm font-bold ${captureStep === 'side' ? 'bg-green-600 text-white' : 'bg-gray-200 text-gray-500'}`}>2</div>
        </div>
        <p className="text-sm text-gray-600 text-center">
          {captureStep === 'top'
            ? '📸 Top-down view — position your plate in the circle'
            : '📸 Side view — hold your phone at plate rim height'}
        </p>

        {error && <p className="text-red-500 text-sm text-center">{error}</p>}

        {/* Camera preview */}
        <div className="relative rounded-2xl overflow-hidden bg-black aspect-[4/3]">
          <video ref={videoRef} autoPlay playsInline muted className="w-full h-full object-cover" />
          {/* Alignment guide */}
          <div className="camera-overlay">
            <div className="plate-guide" />
          </div>
          <div className="absolute bottom-3 left-0 right-0 text-center">
            <span className="bg-black/50 text-white text-xs rounded-full px-3 py-1">
              {captureStep === 'top' ? 'Step 1: Top-down' : 'Step 2: Side angle'}
            </span>
          </div>
        </div>
        <canvas ref={canvasRef} className="hidden" />

        <div className="flex gap-3">
          {topImg && (
            <button onClick={handleRetake} className="btn-secondary flex items-center gap-1.5">
              <RotateCcw className="w-4 h-4" /> Retake
            </button>
          )}
          <button onClick={capturePhoto} className="btn-primary flex-1 flex items-center justify-center gap-2">
            <Camera className="w-5 h-5" />
            {captureStep === 'top' ? 'Capture top view' : 'Capture side view'}
          </button>
        </div>

        {topImg && (
          <div className="flex gap-2 items-center text-xs text-gray-400">
            <div className="w-10 h-10 rounded-lg overflow-hidden">
              <img src={topImg} className="w-full h-full object-cover" alt="top" />
            </div>
            <span>Top view captured ✓</span>
          </div>
        )}
      </div>
    );
  }

  if (analyzing) {
    return (
      <div className="card flex flex-col items-center justify-center py-16 gap-4">
        <LoadingSpinner size="lg" />
        <p className="text-gray-600 font-medium">Analyzing your meal with AI…</p>
        <p className="text-gray-400 text-sm">Identifying foods and estimating portions</p>
      </div>
    );
  }

  // Review step
  if (saved) {
    return (
      <div className="card flex flex-col items-center py-12 gap-3">
        <div className="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center">
          <Check className="w-8 h-8 text-green-600" />
        </div>
        <h3 className="text-lg font-bold text-gray-900">Meal logged!</h3>
        <button onClick={handleRetake} className="btn-secondary">Log another meal</button>
      </div>
    );
  }

  return (
    <div className="card space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="font-bold text-gray-900">Review & Edit</h3>
        <button onClick={handleRetake} className="btn-ghost text-sm flex items-center gap-1">
          <RotateCcw className="w-3.5 h-3.5" /> Retake
        </button>
      </div>

      {/* Captured images preview */}
      <div className="flex gap-2">
        {topImg  && <img src={topImg}  alt="top"  className="w-20 h-16 object-cover rounded-xl" />}
        {sideImg && <img src={sideImg} alt="side" className="w-20 h-16 object-cover rounded-xl" />}
      </div>

      {/* Editable items */}
      <div className="space-y-2">
        {items.map((item, idx) => (
          <div key={idx} className="bg-gray-50 rounded-xl p-3 flex items-center gap-3">
            <span className="text-2xl">{getFoodIcon(item.name)}</span>
            <div className="flex-1 space-y-1">
              <input
                className="input-field text-sm py-1.5"
                value={item.name}
                onChange={(e) => {
                  const copy = [...items];
                  copy[idx] = { ...copy[idx], name: e.target.value };
                  setItems(copy);
                }}
              />
              <div className="flex items-center gap-2">
                <input
                  type="number"
                  min="1"
                  className="input-field w-20 text-sm py-1"
                  value={item.weight_g}
                  onChange={(e) => {
                    const copy = [...items];
                    copy[idx] = { ...copy[idx], weight_g: parseFloat(e.target.value) || 0 };
                    setItems(copy);
                  }}
                />
                <span className="text-sm text-gray-500">g</span>
                <span className="text-xs text-gray-400">
                  {Math.round(item.nutrients?.calories?.value ?? 0)} kcal
                </span>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Meal type */}
      <div>
        <label className="label">Meal type</label>
        <select value={mealType} onChange={(e) => setMealType(e.target.value)} className="input-field">
          {MEAL_TYPES.map((m) => <option key={m} value={m}>{m}</option>)}
        </select>
      </div>

      <button onClick={handleSave} className="btn-primary w-full flex items-center justify-center gap-2">
        <Check className="w-4 h-4" /> Save to food log
      </button>
    </div>
  );
}

// ── Manual Tab ────────────────────────────────────────────────────────────────
function ManualTab() {
  const [query, setQuery]     = useState('');
  const [weight, setWeight]   = useState('');
  const [mealType, setMealType] = useState('other');
  const [saving, setSaving]   = useState(false);
  const [saved, setSaved]     = useState(false);
  const [error, setError]     = useState('');

  const handleAdd = async () => {
    if (!query.trim()) { setError('Enter a food name'); return; }
    const w = parseFloat(weight);
    if (!w || w <= 0) { setError('Enter a valid weight in grams'); return; }
    if (w > 10_000)   { setError('Weight cannot exceed 10 000 g'); return; }
    setError('');
    setSaving(true);
    try {
      await api.post('/logs/food', { food_name: query.trim(), weight_g: w, meal_type: mealType });
      setSaved(true);
      setQuery(''); setWeight('');
    } catch (e: any) {
      setError(e.response?.data?.detail ?? 'Failed to add food');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="card space-y-4">
      {saved && (
        <div className="bg-green-50 border border-green-200 rounded-xl p-3 text-sm text-green-700 flex items-center gap-2">
          <Check className="w-4 h-4" /> Food logged successfully!
        </div>
      )}
      <div>
        <label className="label">Food name</label>
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            className="input-field pl-9"
            value={query}
            onChange={(e) => { setQuery(e.target.value); setSaved(false); }}
            placeholder="e.g. grilled chicken breast, brown rice…"
          />
        </div>
      </div>
      <div>
        <label className="label">Weight (grams)</label>
        <input
          type="number"
          min="1"
          max="10000"
          className="input-field"
          value={weight}
          onChange={(e) => setWeight(e.target.value)}
          placeholder="e.g. 150"
        />
      </div>
      <div>
        <label className="label">Meal type</label>
        <select value={mealType} onChange={(e) => setMealType(e.target.value)} className="input-field">
          {MEAL_TYPES.map((m) => <option key={m} value={m}>{m}</option>)}
        </select>
      </div>
      {error && <p className="text-red-500 text-sm">{error}</p>}
      <button onClick={handleAdd} disabled={saving} className="btn-primary w-full flex items-center justify-center gap-2">
        {saving ? <LoadingSpinner size="sm" /> : <Plus className="w-4 h-4" />}
        {saving ? 'Adding…' : 'Add to food log'}
      </button>
    </div>
  );
}

// ── Barcode Tab ────────────────────────────────────────────────────────────────
function BarcodeTab() {
  const [barcode, setBarcode]   = useState('');
  const [product, setProduct]   = useState<BarcodeProduct | null>(null);
  const [weight, setWeight]     = useState('');
  const [mealType, setMealType] = useState('other');
  const [loading, setLoading]   = useState(false);
  const [saved, setSaved]       = useState(false);
  const [error, setError]       = useState('');

  const handleLookup = async () => {
    if (!barcode.match(/^\d{8,14}$/)) { setError('Enter a valid barcode (8–14 digits)'); return; }
    setError(''); setLoading(true); setProduct(null);
    try {
      const res = await api.get<BarcodeProduct>(`/barcode/${barcode}`);
      setProduct(res.data);
      setWeight(String(res.data.serving_size_g || ''));
    } catch (e: any) {
      setError(e.response?.data?.detail ?? 'Product not found');
    } finally {
      setLoading(false);
    }
  };

  const handleAdd = async () => {
    if (!product) return;
    const w = parseFloat(weight);
    if (!w || w <= 0) { setError('Enter a valid weight'); return; }

    const ratio = w / 100;
    const nutrients: Record<string, { value: number; unit: string }> = {};
    const units: Record<string, string> = {
      calories: 'kcal', protein: 'g', carbohydrates: 'g', fat: 'g',
      fiber: 'g', sugars: 'g', sodium: 'mg', saturated_fat: 'g',
    };
    for (const [key, val] of Object.entries(product.nutrients_per_100g)) {
      nutrients[key] = { value: (val as number) * ratio, unit: units[key] ?? 'g' };
    }

    await api.post('/logs/food', {
      food_name: product.product_name,
      weight_g: w,
      meal_type: mealType,
      nutrients,
    });
    setSaved(true);
  };

  return (
    <div className="card space-y-4">
      {saved && (
        <div className="bg-green-50 border border-green-200 rounded-xl p-3 text-sm text-green-700 flex items-center gap-2">
          <Check className="w-4 h-4" /> Product logged!
        </div>
      )}

      <div>
        <label className="label">Barcode number</label>
        <div className="flex gap-2">
          <input
            className="input-field flex-1"
            value={barcode}
            onChange={(e) => { setBarcode(e.target.value.replace(/\D/g, '')); setProduct(null); setSaved(false); }}
            placeholder="e.g. 5449000000996"
            maxLength={14}
          />
          <button onClick={handleLookup} disabled={loading} className="btn-primary px-4">
            {loading ? <LoadingSpinner size="sm" /> : <Search className="w-4 h-4" />}
          </button>
        </div>
        <p className="text-xs text-gray-400 mt-1">Powered by Open Food Facts</p>
      </div>

      {error && <p className="text-red-500 text-sm">{error}</p>}

      {product && (
        <div className="space-y-3">
          <div className="bg-green-50 rounded-xl p-3 flex gap-3">
            {product.image_url && (
              <img src={product.image_url} alt={product.product_name} className="w-16 h-16 object-contain rounded-lg" />
            )}
            <div>
              <p className="font-semibold text-gray-900">{product.product_name}</p>
              {product.brand && <p className="text-sm text-gray-500">{product.brand}</p>}
              <div className="text-xs text-gray-500 mt-1 space-x-2">
                <span>🔥 {product.nutrients_per_100g.calories} kcal</span>
                <span>🥩 {product.nutrients_per_100g.protein}g protein</span>
                <span>🍞 {product.nutrients_per_100g.carbohydrates}g carbs</span>
              </div>
            </div>
          </div>
          <div className="flex gap-3">
            <div className="flex-1">
              <label className="label">Amount (g)</label>
              <input
                type="number"
                min="1"
                className="input-field"
                value={weight}
                onChange={(e) => setWeight(e.target.value)}
              />
            </div>
            <div className="flex-1">
              <label className="label">Meal type</label>
              <select value={mealType} onChange={(e) => setMealType(e.target.value)} className="input-field">
                {MEAL_TYPES.map((m) => <option key={m} value={m}>{m}</option>)}
              </select>
            </div>
          </div>
          <button onClick={handleAdd} className="btn-primary w-full flex items-center justify-center gap-2">
            <Plus className="w-4 h-4" /> Add to log
          </button>
        </div>
      )}
    </div>
  );
}
