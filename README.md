# NutriLens 🌿
### AI-Powered Health & Nutrition Tracking App

A full-stack nutrition tracking app with dual-camera AI food recognition, macro/micronutrient analytics, gamified plant growth, and smart dietary suggestions.

---

## Quick Setup

### Prerequisites
- [UV](https://docs.astral.sh/uv/getting-started/installation/) — fast Python package manager
- [Node.js 18+](https://nodejs.org)

### Backend (UV)
```bash
# Install UV if you haven't already:
# Windows:  powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
# macOS/Linux: curl -LsSf https://astral.sh/uv/install.sh | sh

cd backend
uv sync                        # creates .venv and installs all deps
cp ../.env.example ../.env     # fill in GROQ_API_KEY, SECRET_KEY
uv run uvicorn app.main:app --reload --port 8000
```

### Frontend
```bash
cd frontend
npm install
npm run dev
```

App: http://localhost:5173 | API docs: http://localhost:8000/docs

### Developer tools (linting / pre-commit)
```bash
# Install pre-commit hooks (run once after cloning):
uv run --directory backend pre-commit install

# Run ruff manually:
cd backend
uv run ruff check .
uv run ruff format .
```

---

## Original project description

---

## What Makes This Different

Most food tracking apps use a **single top-down image**, giving only a 2D view. This project uses:
- 📷 **Top view** → identifies food items and their 2D footprint on the plate
- 📷 **Side view** → measures the height/depth of each food portion

Together these produce a **3D volume estimate**, which is converted to grams using food density, then looked up in a nutrition database.

---

## Architecture

```
Frontend (React)  →  Backend (FastAPI / Python)
                        ├── AI Recognition   (OpenAI GPT-4o Vision)
                        ├── Volume Estimator (OpenCV dual-image geometry)
                        └── Nutrition Lookup (USDA FoodData Central API)
```

---

## Prerequisites – What to Download

| Tool | Version | Link |
|------|---------|------|
| Python | 3.11+ | https://www.python.org/downloads/ |
| Node.js | 20 LTS | https://nodejs.org/en/download |
| Git | latest | https://git-scm.com/downloads |
| VS Code | latest | https://code.visualstudio.com/ |

### API Keys (Free)

| Service | Purpose | Signup |
|---------|---------|--------|
| OpenAI | GPT-4o Vision – food recognition | https://platform.openai.com/api-keys |
| USDA FoodData Central | Nutrition database | https://fdc.nal.usda.gov/api-key-signup.html |

> **Cost note**: OpenAI charges per image (~$0.003 per analysis). USDA is completely free.

---

## Installation & Setup

### Step 1 – Clone / open the project

Open a terminal in the project root folder (the folder containing `backend/` and `frontend/`).

---

### Step 2 – Backend Setup

```bash
cd backend

# Create a virtual environment
python -m venv venv

# Activate it (Windows)
venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

#### Configure environment variables

Copy the example file and fill in your API keys:

```bash
copy .env.example .env
```

Open `.env` and add your keys:

```
OPENAI_API_KEY=sk-...your-openai-key...
USDA_API_KEY=...your-usda-key...
```

#### Start the backend server

```bash
uvicorn app.main:app --reload --port 8000
```

The backend will be running at: http://localhost:8000  
Interactive API docs: http://localhost:8000/docs

---

### Step 3 – Frontend Setup

Open a **new terminal** window:

```bash
cd frontend

# Install dependencies
npm install

# Start development server
npm run dev
```

The frontend will be running at: http://localhost:5173

---

## How to Use the App

1. **Open** http://localhost:5173 in your browser
2. **Upload Top View** – take/select a photo of your plate from directly above
3. **Upload Side View** – take/select a photo of your plate from the side
4. *(Optional)* Enter your plate diameter in cm (default: 26 cm)
5. Press **Analyze**
6. Wait ~5-10 seconds for AI processing
7. Review the identified foods and their estimated weights
8. **Adjust** any item: change the weight (grams) or swap the food if the AI got it wrong
9. See the full **nutrition breakdown** (calories, protein, carbs, fats, vitamins, minerals)

---

## Volume Estimation Algorithm

This is the core novelty of the project:

```
1. PLATE DETECTION (top view)
   - OpenCV HoughCircles detects the circular plate
   - Known plate diameter (e.g. 26 cm) provides a pixel-to-cm scale factor

2. FOOD SEGMENTATION (top view)
   - K-means color clustering separates food regions
   - Each food's pixel area → converted to real area in cm²

3. HEIGHT MEASUREMENT (side view)
   - Detect the plate rim as the baseline height reference
   - Find the peak of each food mound above the plate
   - Height in pixels → converted to cm using same scale factor

4. VOLUME CALCULATION
   Volume ≈ food_area_cm² × height_cm × shape_correction_factor (0.6)

5. WEIGHT ESTIMATION
   Weight (g) = Volume (cm³) × food_density (g/cm³)
   e.g. cooked rice ≈ 1.0 g/cm³, chicken breast ≈ 0.7 g/cm³

6. NUTRITION LOOKUP
   Nutrients = (weight_g / 100) × nutrients_per_100g  [from USDA database]
```

---

## Project Structure

```
pixels-to-macros/
├── backend/
│   ├── app/
│   │   ├── main.py                    ← FastAPI app entry point
│   │   ├── routes/
│   │   │   └── food_analysis.py       ← /analyze endpoint
│   │   ├── services/
│   │   │   ├── ai_recognition.py      ← GPT-4o Vision food identification
│   │   │   ├── volume_estimation.py   ← Dual-image 3D volume calculation
│   │   │   └── nutrition_calculator.py← USDA nutrition lookup
│   │   └── models/
│   │       └── schemas.py             ← Pydantic request/response models
│   ├── .env.example
│   └── requirements.txt
├── frontend/
│   ├── src/
│   │   ├── App.jsx                    ← Main app component
│   │   ├── components/
│   │   │   ├── ImageUpload.jsx        ← Drag-and-drop image uploader
│   │   │   ├── NutritionDisplay.jsx   ← Nutrient results panel
│   │   │   ├── FoodAdjustment.jsx     ← Manual edit modal
│   │   │   └── LoadingSpinner.jsx     ← Analysis loading screen
│   │   └── index.css
│   ├── index.html
│   └── package.json
└── README.md                          ← This file
```

---

## VS Code Extensions (Recommended)

Install these from the Extensions panel (`Ctrl+Shift+X`):
- **Python** (Microsoft)
- **Pylance** (Microsoft)
- **ES7+ React/Redux/React-Native snippets**
- **Tailwind CSS IntelliSense**
- **Prettier – Code formatter**
- **Thunder Client** (test API endpoints without leaving VS Code)
