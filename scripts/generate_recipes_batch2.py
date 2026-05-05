"""
Extended recipe set for Pixels to Macros - Batch 2.
More European, diabetic-appropriate meals. Appends to the main list.
"""
import json
import os

# Load existing
base_path = os.path.join(os.path.dirname(__file__), '..', 'assets', 'recipes.json')
with open(base_path, 'r') as f:
    recipes = json.load(f)

# ═══════════════════════ MORE BREAKFAST ═══════════════════════
extra = [
    {
        "id": "eu-b-009",
        "name": "Shakshuka (Eggs in Spiced Tomato)",
        "image": "https://www.themealdb.com/images/media/meals/g373701551450225.jpg",
        "meal_type": "breakfast",
        "goals": ["diabetes", "weight_loss", "maintain"],
        "minutes": 20,
        "servings": 2,
        "tags": ["mediterranean", "spiced", "one-pan"],
        "ingredients": [
            {"name": "Eggs", "amount": "4"},
            {"name": "Canned tomatoes", "amount": "400g"},
            {"name": "Red pepper, diced", "amount": "1"},
            {"name": "Onion, diced", "amount": "1"},
            {"name": "Garlic", "amount": "2 cloves"},
            {"name": "Cumin", "amount": "1 tsp"},
            {"name": "Smoked paprika", "amount": "1 tsp"},
            {"name": "Fresh parsley", "amount": "handful"},
            {"name": "Olive oil", "amount": "1 tbsp"},
            {"name": "Feta (optional)", "amount": "30g"}
        ],
        "steps": [
            "Sauté onion and pepper in olive oil 5 min.",
            "Add garlic, cumin, paprika. Cook 1 min.",
            "Pour in tomatoes, simmer 8 min until thickened.",
            "Make 4 wells, crack eggs in. Cover, cook 5-6 min.",
            "Top with parsley and crumbled feta."
        ],
        "source": "Curated",
        "calories": 280,
        "protein_g": 18,
        "carbs_g": 16,
        "fat_g": 16,
        "fiber_g": 4,
        "sugar_g": 8
    },
    {
        "id": "eu-b-010",
        "name": "Smørrebrød (Danish Open Sandwich)",
        "image": "https://www.themealdb.com/images/media/meals/1550441882.jpg",
        "meal_type": "breakfast",
        "goals": ["maintain", "muscle"],
        "minutes": 10,
        "servings": 1,
        "tags": ["danish", "scandinavian", "traditional"],
        "ingredients": [
            {"name": "Dense rye bread", "amount": "2 slices"},
            {"name": "Butter", "amount": "10g"},
            {"name": "Smoked salmon", "amount": "60g"},
            {"name": "Hard-boiled egg", "amount": "1"},
            {"name": "Dill", "amount": "fresh sprigs"},
            {"name": "Capers", "amount": "1 tsp"},
            {"name": "Lemon juice", "amount": "squeeze"}
        ],
        "steps": [
            "Butter rye bread generously.",
            "Layer smoked salmon on one slice.",
            "Top with sliced egg, capers, and dill.",
            "Squeeze lemon juice over. Serve open-faced."
        ],
        "source": "Curated",
        "calories": 340,
        "protein_g": 22,
        "carbs_g": 24,
        "fat_g": 18,
        "fiber_g": 5,
        "sugar_g": 2
    },
    {
        "id": "eu-b-011",
        "name": "Turkish Eggs (Çılbır)",
        "image": "https://www.themealdb.com/images/media/meals/g373701551450225.jpg",
        "meal_type": "breakfast",
        "goals": ["diabetes", "keto", "maintain"],
        "minutes": 12,
        "servings": 1,
        "tags": ["mediterranean", "probiotic", "low-carb"],
        "ingredients": [
            {"name": "Eggs", "amount": "2"},
            {"name": "Greek yogurt", "amount": "150g"},
            {"name": "Butter", "amount": "15g"},
            {"name": "Garlic", "amount": "1 clove"},
            {"name": "Aleppo pepper (or paprika)", "amount": "1 tsp"},
            {"name": "Fresh dill", "amount": "1 tbsp"},
            {"name": "White vinegar", "amount": "1 tbsp"}
        ],
        "steps": [
            "Warm yogurt gently, mix with crushed garlic and dill.",
            "Poach eggs in water with vinegar for 3 min.",
            "Melt butter, stir in Aleppo pepper.",
            "Spread yogurt on plate, place eggs on top.",
            "Drizzle spiced butter over eggs."
        ],
        "source": "Curated",
        "calories": 340,
        "protein_g": 20,
        "carbs_g": 6,
        "fat_g": 26,
        "fiber_g": 0,
        "sugar_g": 4
    },
    {
        "id": "eu-b-012",
        "name": "Protein Smoothie Bowl",
        "image": "https://www.themealdb.com/images/media/meals/0jv5gx1661040802.jpg",
        "meal_type": "breakfast",
        "goals": ["muscle", "maintain"],
        "minutes": 5,
        "servings": 1,
        "tags": ["quick", "post-workout", "high-protein"],
        "ingredients": [
            {"name": "Frozen berries", "amount": "120g"},
            {"name": "Banana (frozen)", "amount": "1/2"},
            {"name": "Protein powder (vanilla)", "amount": "30g"},
            {"name": "Greek yogurt", "amount": "100g"},
            {"name": "Almond milk", "amount": "50ml"},
            {"name": "Granola (sugar-free)", "amount": "20g"},
            {"name": "Chia seeds", "amount": "1 tsp"}
        ],
        "steps": [
            "Blend berries, banana, protein powder, yogurt, and milk until thick.",
            "Pour into bowl.",
            "Top with granola and chia seeds."
        ],
        "source": "Curated",
        "calories": 380,
        "protein_g": 32,
        "carbs_g": 38,
        "fat_g": 10,
        "fiber_g": 7,
        "sugar_g": 18
    },

    # ═══════════════════════ MORE LUNCH ═══════════════════════
    {
        "id": "eu-l-009",
        "name": "Greek Quinoa Bowl with Chickpeas",
        "image": "https://www.themealdb.com/images/media/meals/kos9av1699014767.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "vegan", "maintain"],
        "minutes": 25,
        "servings": 2,
        "tags": ["mediterranean", "plant-protein", "high-fiber"],
        "ingredients": [
            {"name": "Quinoa", "amount": "120g dry"},
            {"name": "Chickpeas (canned)", "amount": "200g"},
            {"name": "Cherry tomatoes", "amount": "100g"},
            {"name": "Cucumber", "amount": "1/2"},
            {"name": "Red onion", "amount": "1/4"},
            {"name": "Kalamata olives", "amount": "40g"},
            {"name": "Extra virgin olive oil", "amount": "2 tbsp"},
            {"name": "Lemon juice", "amount": "2 tbsp"},
            {"name": "Fresh parsley", "amount": "handful"},
            {"name": "Sumac", "amount": "1 tsp"}
        ],
        "steps": [
            "Cook quinoa per package. Cool slightly.",
            "Drain and rinse chickpeas.",
            "Dice cucumber, halve tomatoes, slice onion.",
            "Toss everything with olive oil, lemon juice, sumac.",
            "Top with parsley."
        ],
        "source": "Curated",
        "calories": 380,
        "protein_g": 14,
        "carbs_g": 42,
        "fat_g": 18,
        "fiber_g": 10,
        "sugar_g": 5
    },
    {
        "id": "eu-l-010",
        "name": "Tuscan White Bean Soup",
        "image": "https://www.themealdb.com/images/media/meals/rvypwy1503069308.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "vegan", "weight_loss", "maintain"],
        "minutes": 30,
        "servings": 4,
        "tags": ["italian", "comfort", "high-fiber"],
        "ingredients": [
            {"name": "Cannellini beans", "amount": "400g (canned)"},
            {"name": "Kale, chopped", "amount": "100g"},
            {"name": "Onion", "amount": "1"},
            {"name": "Celery", "amount": "2 stalks"},
            {"name": "Carrots", "amount": "2"},
            {"name": "Garlic", "amount": "3 cloves"},
            {"name": "Vegetable stock", "amount": "800ml"},
            {"name": "Rosemary", "amount": "2 sprigs"},
            {"name": "Olive oil", "amount": "2 tbsp"},
            {"name": "Crushed red pepper", "amount": "pinch"}
        ],
        "steps": [
            "Sauté onion, celery, carrots in oil 5 min.",
            "Add garlic and rosemary 1 min.",
            "Add beans (with liquid) and stock. Simmer 15 min.",
            "Blend half for creaminess, stir back in.",
            "Add kale, cook 5 min. Season and drizzle oil."
        ],
        "source": "Curated",
        "calories": 195,
        "protein_g": 10,
        "carbs_g": 26,
        "fat_g": 6,
        "fiber_g": 9,
        "sugar_g": 4
    },
    {
        "id": "eu-l-011",
        "name": "Grilled Halloumi & Roasted Vegetable Salad",
        "image": "https://www.themealdb.com/images/media/meals/kos9av1699014767.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "maintain"],
        "minutes": 20,
        "servings": 2,
        "tags": ["mediterranean", "vegetarian", "high-protein"],
        "ingredients": [
            {"name": "Halloumi", "amount": "200g"},
            {"name": "Zucchini", "amount": "1"},
            {"name": "Red pepper", "amount": "1"},
            {"name": "Red onion", "amount": "1"},
            {"name": "Olive oil", "amount": "2 tbsp"},
            {"name": "Mixed leaves", "amount": "80g"},
            {"name": "Pomegranate seeds", "amount": "2 tbsp"},
            {"name": "Balsamic glaze", "amount": "1 tbsp"},
            {"name": "Pine nuts", "amount": "15g"}
        ],
        "steps": [
            "Slice zucchini, pepper and onion. Grill or roast 10 min.",
            "Slice halloumi, grill 2 min per side.",
            "Arrange leaves, top with veg and halloumi.",
            "Scatter pine nuts and pomegranate seeds.",
            "Drizzle balsamic glaze and olive oil."
        ],
        "source": "Curated",
        "calories": 410,
        "protein_g": 22,
        "carbs_g": 16,
        "fat_g": 30,
        "fiber_g": 4,
        "sugar_g": 8
    },
    {
        "id": "eu-l-012",
        "name": "Spanish Gazpacho",
        "image": "https://www.themealdb.com/images/media/meals/rvypwy1503069308.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "vegan", "weight_loss"],
        "minutes": 10,
        "servings": 4,
        "tags": ["spanish", "cold-soup", "raw", "summer"],
        "ingredients": [
            {"name": "Ripe tomatoes", "amount": "800g"},
            {"name": "Cucumber", "amount": "1"},
            {"name": "Red pepper", "amount": "1"},
            {"name": "Garlic", "amount": "1 clove"},
            {"name": "Stale bread (optional)", "amount": "30g"},
            {"name": "Extra virgin olive oil", "amount": "3 tbsp"},
            {"name": "Sherry vinegar", "amount": "2 tbsp"},
            {"name": "Salt", "amount": "to taste"}
        ],
        "steps": [
            "Roughly chop tomatoes, cucumber, pepper.",
            "Blend all ingredients until smooth.",
            "Season with salt and more vinegar if needed.",
            "Chill at least 1 hour.",
            "Serve with diced vegetables and a drizzle of oil."
        ],
        "source": "Curated",
        "calories": 120,
        "protein_g": 3,
        "carbs_g": 12,
        "fat_g": 7,
        "fiber_g": 3,
        "sugar_g": 8
    },
    {
        "id": "eu-l-013",
        "name": "Salmon & Avocado Poke Bowl",
        "image": "https://www.themealdb.com/images/media/meals/1548772327.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "muscle", "maintain", "keto"],
        "minutes": 15,
        "servings": 1,
        "tags": ["omega-3", "fresh", "low-carb"],
        "ingredients": [
            {"name": "Fresh salmon (sashimi-grade)", "amount": "120g"},
            {"name": "Avocado", "amount": "1/2"},
            {"name": "Edamame", "amount": "50g"},
            {"name": "Cucumber", "amount": "1/4"},
            {"name": "Spring onion", "amount": "1"},
            {"name": "Sesame seeds", "amount": "1 tsp"},
            {"name": "Soy sauce (low sodium)", "amount": "1 tbsp"},
            {"name": "Sesame oil", "amount": "1 tsp"},
            {"name": "Cauliflower rice (cooked)", "amount": "100g"}
        ],
        "steps": [
            "Cube salmon, marinate 5 min in soy and sesame oil.",
            "Prepare cauliflower rice base in a bowl.",
            "Arrange salmon, sliced avocado, edamame, cucumber on top.",
            "Top with spring onion and sesame seeds."
        ],
        "source": "Curated",
        "calories": 410,
        "protein_g": 32,
        "carbs_g": 12,
        "fat_g": 28,
        "fiber_g": 7,
        "sugar_g": 3
    },
    {
        "id": "eu-l-014",
        "name": "Broccoli & Stilton Soup",
        "image": "https://www.themealdb.com/images/media/meals/7n8su21576061865.jpg",
        "meal_type": "lunch",
        "goals": ["keto", "maintain"],
        "minutes": 25,
        "servings": 4,
        "tags": ["british", "comfort", "creamy"],
        "ingredients": [
            {"name": "Broccoli", "amount": "500g"},
            {"name": "Stilton cheese", "amount": "100g"},
            {"name": "Onion", "amount": "1"},
            {"name": "Garlic", "amount": "2 cloves"},
            {"name": "Vegetable stock", "amount": "600ml"},
            {"name": "Butter", "amount": "20g"},
            {"name": "Nutmeg", "amount": "pinch"}
        ],
        "steps": [
            "Sauté onion and garlic in butter 3 min.",
            "Add broccoli and stock. Simmer 12 min.",
            "Blend until smooth.",
            "Stir in crumbled Stilton off heat until melted.",
            "Season with nutmeg and pepper."
        ],
        "source": "Curated",
        "calories": 195,
        "protein_g": 12,
        "carbs_g": 8,
        "fat_g": 13,
        "fiber_g": 4,
        "sugar_g": 3
    },

    # ═══════════════════════ MORE DINNER ═══════════════════════
    {
        "id": "eu-d-011",
        "name": "Mediterranean Sea Bass en Papillote",
        "image": "https://www.themealdb.com/images/media/meals/vuxgtm1764112923.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "weight_loss", "maintain"],
        "minutes": 25,
        "servings": 2,
        "tags": ["french", "elegant", "lean"],
        "ingredients": [
            {"name": "Sea bass fillets", "amount": "2 × 150g"},
            {"name": "Cherry tomatoes", "amount": "100g"},
            {"name": "Olives (green)", "amount": "30g"},
            {"name": "Capers", "amount": "1 tbsp"},
            {"name": "Fresh basil", "amount": "handful"},
            {"name": "Lemon slices", "amount": "4"},
            {"name": "White wine", "amount": "2 tbsp"},
            {"name": "Olive oil", "amount": "1 tbsp"}
        ],
        "steps": [
            "Preheat oven to 200°C.",
            "Place each fillet on parchment paper.",
            "Top with tomatoes, olives, capers, lemon, basil.",
            "Drizzle wine and oil. Seal parchment into parcels.",
            "Bake 15-18 min. Serve in paper."
        ],
        "source": "Curated",
        "calories": 280,
        "protein_g": 34,
        "carbs_g": 6,
        "fat_g": 13,
        "fiber_g": 2,
        "sugar_g": 3
    },
    {
        "id": "eu-d-012",
        "name": "Coq au Vin (Lighter Version)",
        "image": "https://www.themealdb.com/images/media/meals/qysyss1511558054.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "maintain"],
        "minutes": 75,
        "servings": 4,
        "tags": ["french", "classic", "braised"],
        "ingredients": [
            {"name": "Chicken thighs (skinless)", "amount": "8"},
            {"name": "Mushrooms", "amount": "200g"},
            {"name": "Pearl onions", "amount": "150g"},
            {"name": "Bacon lardons", "amount": "100g"},
            {"name": "Red wine", "amount": "300ml"},
            {"name": "Chicken stock", "amount": "200ml"},
            {"name": "Garlic", "amount": "3 cloves"},
            {"name": "Thyme & bay leaves", "amount": "3 sprigs + 2 leaves"},
            {"name": "Tomato paste", "amount": "1 tbsp"},
            {"name": "Olive oil", "amount": "1 tbsp"}
        ],
        "steps": [
            "Brown chicken in oil, set aside.",
            "Cook lardons until crispy. Add pearl onions and mushrooms.",
            "Add garlic and tomato paste, cook 1 min.",
            "Pour in wine and stock, add herbs.",
            "Return chicken, cover, simmer 50 min.",
            "Season and serve over steamed green beans."
        ],
        "source": "Curated",
        "calories": 360,
        "protein_g": 36,
        "carbs_g": 10,
        "fat_g": 16,
        "fiber_g": 2,
        "sugar_g": 4
    },
    {
        "id": "eu-d-013",
        "name": "Lemon Herb Roasted Chicken Breast",
        "image": "https://www.themealdb.com/images/media/meals/qysyss1511558054.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "weight_loss", "muscle", "maintain", "keto"],
        "minutes": 30,
        "servings": 2,
        "tags": ["simple", "high-protein", "lean"],
        "ingredients": [
            {"name": "Chicken breasts", "amount": "2 × 180g"},
            {"name": "Lemon", "amount": "1"},
            {"name": "Fresh rosemary", "amount": "2 sprigs"},
            {"name": "Garlic", "amount": "3 cloves"},
            {"name": "Olive oil", "amount": "1 tbsp"},
            {"name": "Green beans", "amount": "200g"},
            {"name": "Cherry tomatoes", "amount": "100g"}
        ],
        "steps": [
            "Preheat oven to 200°C.",
            "Slash chicken, stuff with lemon slices, garlic, rosemary.",
            "Drizzle oil, season well.",
            "Roast 22-25 min until cooked through.",
            "Serve with steamed green beans and roasted tomatoes."
        ],
        "source": "Curated",
        "calories": 310,
        "protein_g": 42,
        "carbs_g": 8,
        "fat_g": 12,
        "fiber_g": 4,
        "sugar_g": 4
    },
    {
        "id": "eu-d-014",
        "name": "Moussaka (Low-Carb)",
        "image": "https://www.themealdb.com/images/media/meals/ctg8jd1585563097.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "keto", "maintain"],
        "minutes": 60,
        "servings": 6,
        "tags": ["greek", "comfort", "low-carb"],
        "ingredients": [
            {"name": "Eggplant", "amount": "3 large"},
            {"name": "Lamb mince", "amount": "500g"},
            {"name": "Onion", "amount": "1"},
            {"name": "Garlic", "amount": "3 cloves"},
            {"name": "Canned tomatoes", "amount": "400g"},
            {"name": "Cinnamon", "amount": "1/2 tsp"},
            {"name": "Greek yogurt", "amount": "200g"},
            {"name": "Egg", "amount": "1"},
            {"name": "Parmesan", "amount": "40g"},
            {"name": "Olive oil", "amount": "3 tbsp"}
        ],
        "steps": [
            "Slice eggplant, brush with oil. Grill until golden.",
            "Brown lamb with onion and garlic.",
            "Add tomatoes and cinnamon, simmer 15 min.",
            "Layer eggplant and meat sauce in a baking dish.",
            "Mix yogurt, egg, Parmesan for topping. Spread on top.",
            "Bake at 180°C for 30 min until golden."
        ],
        "source": "Curated",
        "calories": 340,
        "protein_g": 24,
        "carbs_g": 14,
        "fat_g": 22,
        "fiber_g": 6,
        "sugar_g": 8
    },
    {
        "id": "eu-d-015",
        "name": "Herb-Crusted Pork Tenderloin",
        "image": "https://www.themealdb.com/images/media/meals/1525876468.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "muscle", "maintain"],
        "minutes": 35,
        "servings": 4,
        "tags": ["lean", "high-protein", "roast"],
        "ingredients": [
            {"name": "Pork tenderloin", "amount": "500g"},
            {"name": "Dijon mustard", "amount": "2 tbsp"},
            {"name": "Fresh herbs (rosemary, thyme)", "amount": "3 tbsp chopped"},
            {"name": "Garlic", "amount": "2 cloves"},
            {"name": "Olive oil", "amount": "1 tbsp"},
            {"name": "Sweet potato, cubed", "amount": "300g"},
            {"name": "Tenderstem broccoli", "amount": "200g"}
        ],
        "steps": [
            "Preheat oven to 200°C.",
            "Coat pork with mustard, press herbs and garlic onto surface.",
            "Sear in hot pan 2 min per side.",
            "Roast 20-25 min until internal temp reaches 63°C.",
            "Rest 5 min, slice. Serve with roasted sweet potato and broccoli."
        ],
        "source": "Curated",
        "calories": 320,
        "protein_g": 36,
        "carbs_g": 20,
        "fat_g": 10,
        "fiber_g": 5,
        "sugar_g": 6
    },
    {
        "id": "eu-d-016",
        "name": "Shrimp Scampi with Zucchini Noodles",
        "image": "https://www.themealdb.com/images/media/meals/1548772327.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "keto", "weight_loss", "maintain"],
        "minutes": 15,
        "servings": 2,
        "tags": ["quick", "low-carb", "seafood"],
        "ingredients": [
            {"name": "Large shrimp (peeled)", "amount": "300g"},
            {"name": "Zucchini", "amount": "3 medium"},
            {"name": "Garlic", "amount": "4 cloves"},
            {"name": "Butter", "amount": "20g"},
            {"name": "White wine", "amount": "60ml"},
            {"name": "Lemon juice", "amount": "2 tbsp"},
            {"name": "Red pepper flakes", "amount": "pinch"},
            {"name": "Fresh parsley", "amount": "2 tbsp"}
        ],
        "steps": [
            "Spiralize zucchini into noodles.",
            "Melt butter, sauté garlic 30 seconds.",
            "Add shrimp, cook 2 min per side.",
            "Add wine, lemon, pepper flakes. Reduce 2 min.",
            "Toss in zucchini noodles for 1 min.",
            "Serve with parsley."
        ],
        "source": "Curated",
        "calories": 280,
        "protein_g": 34,
        "carbs_g": 10,
        "fat_g": 12,
        "fiber_g": 3,
        "sugar_g": 6
    },
    {
        "id": "eu-d-017",
        "name": "Dutch Stamppot with Sausage",
        "image": "https://www.themealdb.com/images/media/meals/svprys1511176755.jpg",
        "meal_type": "dinner",
        "goals": ["maintain", "muscle"],
        "minutes": 30,
        "servings": 4,
        "tags": ["dutch", "comfort", "winter"],
        "ingredients": [
            {"name": "Potatoes", "amount": "800g"},
            {"name": "Kale or endive", "amount": "400g"},
            {"name": "Smoked sausage (rookworst)", "amount": "300g"},
            {"name": "Butter", "amount": "30g"},
            {"name": "Milk", "amount": "100ml"},
            {"name": "Gravy (jus)", "amount": "200ml"},
            {"name": "Mustard", "amount": "to serve"}
        ],
        "steps": [
            "Boil potatoes until tender.",
            "Shred kale and blanch 3 min (or use raw endive).",
            "Mash potatoes with butter and milk.",
            "Fold in kale/endive.",
            "Heat sausage in simmering water.",
            "Serve stamppot with sliced sausage, gravy, and mustard."
        ],
        "source": "Curated",
        "calories": 480,
        "protein_g": 20,
        "carbs_g": 42,
        "fat_g": 26,
        "fiber_g": 6,
        "sugar_g": 4
    },
    {
        "id": "eu-d-018",
        "name": "Vegetable Curry with Cauliflower Rice",
        "image": "https://www.themealdb.com/images/media/meals/9pndnm1764441752.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "vegan", "weight_loss", "keto"],
        "minutes": 30,
        "servings": 4,
        "tags": ["low-carb", "spiced", "plant-based"],
        "ingredients": [
            {"name": "Cauliflower rice", "amount": "400g"},
            {"name": "Chickpeas", "amount": "200g"},
            {"name": "Spinach", "amount": "100g"},
            {"name": "Coconut milk (light)", "amount": "200ml"},
            {"name": "Curry paste", "amount": "2 tbsp"},
            {"name": "Onion", "amount": "1"},
            {"name": "Garlic & ginger", "amount": "2 cloves + 1 inch"},
            {"name": "Cherry tomatoes", "amount": "150g"},
            {"name": "Coriander", "amount": "fresh handful"}
        ],
        "steps": [
            "Sauté onion, garlic, ginger 3 min.",
            "Add curry paste, cook 1 min.",
            "Add coconut milk, tomatoes, chickpeas. Simmer 15 min.",
            "Stir in spinach until wilted.",
            "Serve over cauliflower rice with fresh coriander."
        ],
        "source": "Curated",
        "calories": 240,
        "protein_g": 10,
        "carbs_g": 22,
        "fat_g": 13,
        "fiber_g": 8,
        "sugar_g": 6
    },
    {
        "id": "eu-d-019",
        "name": "Chicken Souvlaki with Tzatziki",
        "image": "https://www.themealdb.com/images/media/meals/kos9av1699014767.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "muscle", "maintain"],
        "minutes": 25,
        "servings": 4,
        "tags": ["greek", "grilled", "high-protein"],
        "ingredients": [
            {"name": "Chicken thigh (boneless)", "amount": "600g"},
            {"name": "Greek yogurt", "amount": "200g"},
            {"name": "Cucumber", "amount": "1/2"},
            {"name": "Garlic", "amount": "2 cloves"},
            {"name": "Lemon juice", "amount": "2 tbsp"},
            {"name": "Olive oil", "amount": "2 tbsp"},
            {"name": "Oregano", "amount": "2 tsp"},
            {"name": "Cherry tomatoes", "amount": "100g"},
            {"name": "Red onion", "amount": "1/2"}
        ],
        "steps": [
            "Cut chicken into cubes, marinate in oil, lemon, oregano 10 min.",
            "Thread onto skewers. Grill 10-12 min.",
            "Make tzatziki: grate cucumber, mix with yogurt, garlic, salt.",
            "Serve skewers with tzatziki, tomato, and onion salad."
        ],
        "source": "Curated",
        "calories": 340,
        "protein_g": 38,
        "carbs_g": 8,
        "fat_g": 17,
        "fiber_g": 2,
        "sugar_g": 5
    },
    {
        "id": "eu-d-020",
        "name": "One-Pan Tuscan White Fish",
        "image": "https://www.themealdb.com/images/media/meals/vuxgtm1764112923.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "weight_loss", "maintain"],
        "minutes": 20,
        "servings": 2,
        "tags": ["italian", "one-pan", "lean"],
        "ingredients": [
            {"name": "White fish fillets (hake/cod)", "amount": "2 × 150g"},
            {"name": "Sun-dried tomatoes", "amount": "40g"},
            {"name": "Spinach", "amount": "100g"},
            {"name": "Garlic", "amount": "2 cloves"},
            {"name": "Cannellini beans", "amount": "150g"},
            {"name": "Chicken stock", "amount": "100ml"},
            {"name": "Heavy cream", "amount": "50ml"},
            {"name": "Parmesan", "amount": "20g"},
            {"name": "Italian herbs", "amount": "1 tsp"}
        ],
        "steps": [
            "Season fish, sear 3 min per side. Set aside.",
            "In same pan, sauté garlic and sun-dried tomatoes.",
            "Add beans, stock, cream, herbs. Simmer 5 min.",
            "Add spinach, cook until wilted.",
            "Return fish to pan 2 min. Serve with Parmesan."
        ],
        "source": "Curated",
        "calories": 340,
        "protein_g": 38,
        "carbs_g": 18,
        "fat_g": 12,
        "fiber_g": 5,
        "sugar_g": 4
    },

    # ═══════════════════════ MORE SNACKS ═══════════════════════
    {
        "id": "eu-s-007",
        "name": "Caprese Skewers",
        "image": "https://www.themealdb.com/images/media/meals/1549542994.jpg",
        "meal_type": "snack",
        "goals": ["diabetes", "keto", "maintain"],
        "minutes": 5,
        "servings": 2,
        "tags": ["italian", "quick", "elegant"],
        "ingredients": [
            {"name": "Mini mozzarella balls", "amount": "100g"},
            {"name": "Cherry tomatoes", "amount": "8"},
            {"name": "Fresh basil leaves", "amount": "8"},
            {"name": "Balsamic glaze", "amount": "1 tbsp"},
            {"name": "Olive oil", "amount": "1 tsp"}
        ],
        "steps": [
            "Thread mozzarella, basil, tomato onto cocktail sticks.",
            "Arrange on plate, drizzle with balsamic and olive oil."
        ],
        "source": "Curated",
        "calories": 165,
        "protein_g": 12,
        "carbs_g": 4,
        "fat_g": 12,
        "fiber_g": 1,
        "sugar_g": 3
    },
    {
        "id": "eu-s-008",
        "name": "Ricotta & Honey on Rye Crispbread",
        "image": "https://www.themealdb.com/images/media/meals/m2bnlm1764436938.jpg",
        "meal_type": "snack",
        "goals": ["maintain"],
        "minutes": 3,
        "servings": 1,
        "tags": ["quick", "scandinavian"],
        "ingredients": [
            {"name": "Rye crispbread", "amount": "2"},
            {"name": "Ricotta", "amount": "60g"},
            {"name": "Honey", "amount": "1 tsp"},
            {"name": "Walnuts, chopped", "amount": "10g"},
            {"name": "Sea salt flakes", "amount": "pinch"}
        ],
        "steps": [
            "Spread ricotta on crispbreads.",
            "Drizzle honey, scatter walnuts.",
            "Finish with salt flakes."
        ],
        "source": "Curated",
        "calories": 195,
        "protein_g": 8,
        "carbs_g": 22,
        "fat_g": 9,
        "fiber_g": 3,
        "sugar_g": 8
    },
    {
        "id": "eu-s-009",
        "name": "Edamame with Sea Salt",
        "image": "https://www.themealdb.com/images/media/meals/vlrppq1764113063.jpg",
        "meal_type": "snack",
        "goals": ["diabetes", "vegan", "weight_loss", "maintain"],
        "minutes": 5,
        "servings": 2,
        "tags": ["plant-protein", "quick"],
        "ingredients": [
            {"name": "Frozen edamame (in pods)", "amount": "200g"},
            {"name": "Sea salt", "amount": "1/2 tsp"},
            {"name": "Chilli flakes (optional)", "amount": "pinch"}
        ],
        "steps": [
            "Boil edamame 3-4 minutes.",
            "Drain, toss with salt and chilli.",
            "Serve warm."
        ],
        "source": "Curated",
        "calories": 120,
        "protein_g": 11,
        "carbs_g": 8,
        "fat_g": 5,
        "fiber_g": 4,
        "sugar_g": 2
    },
    {
        "id": "eu-s-010",
        "name": "Smoked Salmon Cucumber Bites",
        "image": "https://www.themealdb.com/images/media/meals/1550441882.jpg",
        "meal_type": "snack",
        "goals": ["diabetes", "keto", "maintain"],
        "minutes": 5,
        "servings": 2,
        "tags": ["low-carb", "elegant", "omega-3"],
        "ingredients": [
            {"name": "Cucumber", "amount": "1"},
            {"name": "Smoked salmon", "amount": "80g"},
            {"name": "Cream cheese", "amount": "40g"},
            {"name": "Dill", "amount": "1 tbsp"},
            {"name": "Capers", "amount": "1 tsp"},
            {"name": "Black pepper", "amount": "to taste"}
        ],
        "steps": [
            "Slice cucumber into thick rounds.",
            "Spread cream cheese on each.",
            "Top with folded salmon, dill, and capers."
        ],
        "source": "Curated",
        "calories": 160,
        "protein_g": 14,
        "carbs_g": 4,
        "fat_g": 10,
        "fiber_g": 1,
        "sugar_g": 2
    },

    # ═══════════════════════ MORE DESSERTS ═══════════════════════
    {
        "id": "eu-ds-004",
        "name": "Chia Seed Pudding with Mango",
        "image": "https://www.themealdb.com/images/media/meals/0jv5gx1661040802.jpg",
        "meal_type": "dessert",
        "goals": ["diabetes", "vegan", "maintain"],
        "minutes": 5,
        "servings": 2,
        "tags": ["make-ahead", "high-fiber", "low-sugar"],
        "ingredients": [
            {"name": "Chia seeds", "amount": "40g"},
            {"name": "Coconut milk", "amount": "250ml"},
            {"name": "Vanilla extract", "amount": "1 tsp"},
            {"name": "Fresh mango, diced", "amount": "100g"},
            {"name": "Coconut flakes", "amount": "1 tbsp"}
        ],
        "steps": [
            "Mix chia seeds, coconut milk, and vanilla.",
            "Refrigerate at least 4 hours or overnight.",
            "Top with mango and coconut flakes."
        ],
        "source": "Curated",
        "calories": 210,
        "protein_g": 5,
        "carbs_g": 18,
        "fat_g": 14,
        "fiber_g": 9,
        "sugar_g": 10
    },
    {
        "id": "eu-ds-005",
        "name": "Grilled Peaches with Mascarpone",
        "image": "https://www.themealdb.com/images/media/meals/adxcbq1619787919.jpg",
        "meal_type": "dessert",
        "goals": ["diabetes", "maintain"],
        "minutes": 10,
        "servings": 2,
        "tags": ["italian", "summer", "elegant"],
        "ingredients": [
            {"name": "Peaches (ripe)", "amount": "2"},
            {"name": "Mascarpone", "amount": "60g"},
            {"name": "Honey", "amount": "1 tsp"},
            {"name": "Pistachios, chopped", "amount": "15g"},
            {"name": "Fresh mint", "amount": "few leaves"}
        ],
        "steps": [
            "Halve and pit peaches.",
            "Grill cut-side down 3-4 min until charred.",
            "Fill centres with mascarpone.",
            "Drizzle honey, scatter pistachios and mint."
        ],
        "source": "Curated",
        "calories": 185,
        "protein_g": 4,
        "carbs_g": 16,
        "fat_g": 12,
        "fiber_g": 2,
        "sugar_g": 14
    },
    {
        "id": "eu-ds-006",
        "name": "Protein Tiramisu (Sugar-Free)",
        "image": "https://www.themealdb.com/images/media/meals/adxcbq1619787919.jpg",
        "meal_type": "dessert",
        "goals": ["diabetes", "muscle", "maintain"],
        "minutes": 15,
        "servings": 4,
        "tags": ["italian", "high-protein", "make-ahead"],
        "ingredients": [
            {"name": "Quark (or Greek yogurt)", "amount": "400g"},
            {"name": "Mascarpone", "amount": "100g"},
            {"name": "Espresso (cooled)", "amount": "150ml"},
            {"name": "Erythritol", "amount": "3 tbsp"},
            {"name": "Vanilla protein powder", "amount": "30g"},
            {"name": "Cocoa powder", "amount": "2 tbsp"},
            {"name": "Ladyfinger biscuits (reduced sugar)", "amount": "8"}
        ],
        "steps": [
            "Mix quark, mascarpone, protein powder, and sweetener until smooth.",
            "Briefly dip ladyfingers in espresso.",
            "Layer: biscuits, cream, biscuits, cream.",
            "Dust with cocoa powder.",
            "Chill at least 3 hours."
        ],
        "source": "Curated",
        "calories": 220,
        "protein_g": 18,
        "carbs_g": 14,
        "fat_g": 10,
        "fiber_g": 1,
        "sugar_g": 5
    },
    {
        "id": "eu-ds-007",
        "name": "Mixed Berry Crumble (Oat Topping)",
        "image": "https://www.themealdb.com/images/media/meals/adxcbq1619787919.jpg",
        "meal_type": "dessert",
        "goals": ["diabetes", "maintain"],
        "minutes": 30,
        "servings": 4,
        "tags": ["british", "warm", "high-fiber"],
        "ingredients": [
            {"name": "Mixed berries (frozen ok)", "amount": "400g"},
            {"name": "Rolled oats", "amount": "80g"},
            {"name": "Almond flour", "amount": "40g"},
            {"name": "Butter (cold, cubed)", "amount": "40g"},
            {"name": "Erythritol", "amount": "2 tbsp"},
            {"name": "Cinnamon", "amount": "1/2 tsp"},
            {"name": "Vanilla extract", "amount": "1 tsp"}
        ],
        "steps": [
            "Preheat oven to 180°C.",
            "Toss berries with vanilla, place in baking dish.",
            "Rub butter into oats, almond flour, sweetener, cinnamon.",
            "Scatter crumble on berries.",
            "Bake 25 min until golden. Serve with a spoon of yogurt."
        ],
        "source": "Curated",
        "calories": 195,
        "protein_g": 5,
        "carbs_g": 20,
        "fat_g": 11,
        "fiber_g": 6,
        "sugar_g": 8
    },

    # ═══════════════════════ EXTRA VARIETY ═══════════════════════
    {
        "id": "eu-d-021",
        "name": "Swedish Meatballs with Lingonberry",
        "image": "https://www.themealdb.com/images/media/meals/8rfd4q1764112993.jpg",
        "meal_type": "dinner",
        "goals": ["maintain", "muscle"],
        "minutes": 40,
        "servings": 4,
        "tags": ["swedish", "comfort", "classic"],
        "ingredients": [
            {"name": "Mixed mince (beef/pork)", "amount": "500g"},
            {"name": "Breadcrumbs", "amount": "40g"},
            {"name": "Egg", "amount": "1"},
            {"name": "Onion, grated", "amount": "1/2"},
            {"name": "Allspice", "amount": "1/2 tsp"},
            {"name": "Butter", "amount": "30g"},
            {"name": "Cream", "amount": "150ml"},
            {"name": "Beef stock", "amount": "200ml"},
            {"name": "Lingonberry jam", "amount": "4 tbsp"}
        ],
        "steps": [
            "Mix mince, breadcrumbs, egg, onion, allspice. Roll into small balls.",
            "Brown meatballs in butter in batches.",
            "Remove balls. Add stock to pan, scrape up bits.",
            "Add cream, simmer until sauce thickens.",
            "Return meatballs, warm through.",
            "Serve with lingonberry jam on the side."
        ],
        "source": "Curated",
        "calories": 420,
        "protein_g": 30,
        "carbs_g": 16,
        "fat_g": 26,
        "fiber_g": 1,
        "sugar_g": 8
    },
    {
        "id": "eu-d-022",
        "name": "Spanish Chicken with Chorizo & Peppers",
        "image": "https://www.themealdb.com/images/media/meals/wrpwuu1511786491.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "maintain"],
        "minutes": 40,
        "servings": 4,
        "tags": ["spanish", "one-pan", "mediterranean"],
        "ingredients": [
            {"name": "Chicken thighs", "amount": "4"},
            {"name": "Chorizo, sliced", "amount": "100g"},
            {"name": "Bell peppers (mixed)", "amount": "2"},
            {"name": "Onion", "amount": "1"},
            {"name": "Garlic", "amount": "3 cloves"},
            {"name": "Canned tomatoes", "amount": "400g"},
            {"name": "Smoked paprika", "amount": "2 tsp"},
            {"name": "Olive oil", "amount": "1 tbsp"},
            {"name": "Fresh parsley", "amount": "handful"}
        ],
        "steps": [
            "Brown chicken and chorizo in oil. Set aside.",
            "Sauté peppers, onion, garlic 5 min.",
            "Add tomatoes and paprika. Return chicken and chorizo.",
            "Cover, simmer 25 min until chicken is done.",
            "Top with parsley. Serve with green salad."
        ],
        "source": "Curated",
        "calories": 380,
        "protein_g": 34,
        "carbs_g": 12,
        "fat_g": 22,
        "fiber_g": 3,
        "sugar_g": 7
    },
    {
        "id": "eu-l-015",
        "name": "French Salade Lyonnaise",
        "image": "https://www.themealdb.com/images/media/meals/yypvst1511304979.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "keto", "maintain"],
        "minutes": 20,
        "servings": 2,
        "tags": ["french", "classic", "bistro"],
        "ingredients": [
            {"name": "Frisée lettuce", "amount": "150g"},
            {"name": "Bacon lardons", "amount": "100g"},
            {"name": "Eggs", "amount": "2"},
            {"name": "Shallot", "amount": "1"},
            {"name": "Red wine vinegar", "amount": "2 tbsp"},
            {"name": "Dijon mustard", "amount": "1 tsp"},
            {"name": "Olive oil", "amount": "1 tbsp"},
            {"name": "Croutons (wholemeal)", "amount": "30g"}
        ],
        "steps": [
            "Fry lardons until crispy, keep fat in pan.",
            "Poach eggs in simmering water 3 min.",
            "Whisk vinegar, mustard, oil with bacon fat for warm dressing.",
            "Toss frisée with dressing and lardons.",
            "Top each plate with a poached egg and croutons."
        ],
        "source": "Curated",
        "calories": 340,
        "protein_g": 20,
        "carbs_g": 10,
        "fat_g": 25,
        "fiber_g": 2,
        "sugar_g": 2
    },
    {
        "id": "eu-b-013",
        "name": "Full English (Healthier Version)",
        "image": "https://www.themealdb.com/images/media/meals/vwsxry1764113206.jpg",
        "meal_type": "breakfast",
        "goals": ["muscle", "maintain"],
        "minutes": 20,
        "servings": 1,
        "tags": ["british", "hearty", "weekend"],
        "ingredients": [
            {"name": "Eggs", "amount": "2"},
            {"name": "Turkey bacon", "amount": "2 rashers"},
            {"name": "Cherry tomatoes", "amount": "6"},
            {"name": "Mushrooms", "amount": "80g"},
            {"name": "Baked beans (reduced sugar)", "amount": "80g"},
            {"name": "Whole grain toast", "amount": "1 slice"},
            {"name": "Olive oil spray", "amount": "for cooking"}
        ],
        "steps": [
            "Grill turkey bacon and halved tomatoes 4 min.",
            "Fry mushrooms in a little oil 3 min.",
            "Scramble or fry eggs.",
            "Warm beans.",
            "Toast bread. Plate everything up."
        ],
        "source": "Curated",
        "calories": 410,
        "protein_g": 30,
        "carbs_g": 28,
        "fat_g": 20,
        "fiber_g": 6,
        "sugar_g": 8
    },
    {
        "id": "eu-d-023",
        "name": "Italian Chicken Cacciatore",
        "image": "https://www.themealdb.com/images/media/meals/wrpwuu1511786491.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "maintain", "weight_loss"],
        "minutes": 50,
        "servings": 4,
        "tags": ["italian", "braised", "one-pot"],
        "ingredients": [
            {"name": "Chicken thighs", "amount": "8"},
            {"name": "Canned tomatoes", "amount": "400g"},
            {"name": "Bell pepper", "amount": "1"},
            {"name": "Onion", "amount": "1"},
            {"name": "Mushrooms", "amount": "150g"},
            {"name": "Olives", "amount": "50g"},
            {"name": "Garlic", "amount": "3 cloves"},
            {"name": "White wine", "amount": "100ml"},
            {"name": "Italian herbs", "amount": "2 tsp"},
            {"name": "Olive oil", "amount": "1 tbsp"}
        ],
        "steps": [
            "Brown chicken in oil, set aside.",
            "Sauté onion, pepper, mushrooms 5 min.",
            "Add garlic, wine, deglaze.",
            "Add tomatoes, herbs, olives. Return chicken.",
            "Cover, simmer 35 min until chicken falls off bone."
        ],
        "source": "Curated",
        "calories": 350,
        "protein_g": 34,
        "carbs_g": 10,
        "fat_g": 18,
        "fiber_g": 3,
        "sugar_g": 6
    },
    {
        "id": "eu-l-016",
        "name": "Waldorf Salad",
        "image": "https://www.themealdb.com/images/media/meals/yypvst1511304979.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "maintain"],
        "minutes": 10,
        "servings": 2,
        "tags": ["classic", "quick", "crunchy"],
        "ingredients": [
            {"name": "Green apple", "amount": "1"},
            {"name": "Celery", "amount": "2 stalks"},
            {"name": "Walnuts", "amount": "40g"},
            {"name": "Grapes (halved)", "amount": "80g"},
            {"name": "Greek yogurt", "amount": "60g"},
            {"name": "Lemon juice", "amount": "1 tbsp"},
            {"name": "Mixed leaves", "amount": "60g"},
            {"name": "Grilled chicken (optional)", "amount": "100g"}
        ],
        "steps": [
            "Dice apple and celery. Halve grapes.",
            "Toast walnuts lightly.",
            "Mix yogurt with lemon juice for dressing.",
            "Toss all together. Serve on mixed leaves.",
            "Add grilled chicken if desired."
        ],
        "source": "Curated",
        "calories": 280,
        "protein_g": 18,
        "carbs_g": 20,
        "fat_g": 15,
        "fiber_g": 4,
        "sugar_g": 14
    },
    {
        "id": "eu-d-024",
        "name": "Grilled Tuna Steak with Salsa Verde",
        "image": "https://www.themealdb.com/images/media/meals/1548772327.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "keto", "muscle", "maintain"],
        "minutes": 15,
        "servings": 2,
        "tags": ["italian", "quick", "omega-3"],
        "ingredients": [
            {"name": "Tuna steaks", "amount": "2 × 150g"},
            {"name": "Fresh parsley", "amount": "large bunch"},
            {"name": "Capers", "amount": "1 tbsp"},
            {"name": "Anchovy fillets", "amount": "2"},
            {"name": "Garlic", "amount": "1 clove"},
            {"name": "Extra virgin olive oil", "amount": "3 tbsp"},
            {"name": "Red wine vinegar", "amount": "1 tbsp"},
            {"name": "Rocket salad", "amount": "60g"}
        ],
        "steps": [
            "Make salsa verde: blitz parsley, capers, anchovy, garlic, oil, vinegar.",
            "Season tuna, brush with oil.",
            "Grill 2 min per side (for medium-rare).",
            "Serve with generous salsa verde and rocket."
        ],
        "source": "Curated",
        "calories": 350,
        "protein_g": 40,
        "carbs_g": 2,
        "fat_g": 20,
        "fiber_g": 1,
        "sugar_g": 0
    },
    {
        "id": "eu-d-025",
        "name": "Lamb Tagine with Vegetables",
        "image": "https://www.themealdb.com/images/media/meals/svprys1511176755.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "maintain"],
        "minutes": 90,
        "servings": 6,
        "tags": ["moroccan-inspired", "slow-cooked", "spiced"],
        "ingredients": [
            {"name": "Lamb shoulder, cubed", "amount": "600g"},
            {"name": "Butternut squash", "amount": "300g"},
            {"name": "Chickpeas (canned)", "amount": "200g"},
            {"name": "Onion", "amount": "2"},
            {"name": "Garlic & ginger", "amount": "3 cloves + 1 inch"},
            {"name": "Canned tomatoes", "amount": "400g"},
            {"name": "Ras el hanout", "amount": "2 tbsp"},
            {"name": "Dried apricots", "amount": "50g"},
            {"name": "Fresh coriander", "amount": "handful"},
            {"name": "Olive oil", "amount": "2 tbsp"}
        ],
        "steps": [
            "Brown lamb in batches in oil.",
            "Sauté onion, garlic, ginger 3 min.",
            "Add ras el hanout, cook 1 min.",
            "Add tomatoes, squash, chickpeas, apricots, lamb. Cover with water.",
            "Simmer covered 1 hour until lamb is tender.",
            "Serve with coriander and cauliflower couscous."
        ],
        "source": "Curated",
        "calories": 380,
        "protein_g": 28,
        "carbs_g": 26,
        "fat_g": 18,
        "fiber_g": 7,
        "sugar_g": 12
    },
]

recipes.extend(extra)

# Save
with open(base_path, 'w') as f:
    json.dump(recipes, f, indent=2, ensure_ascii=False)

print(f"Total recipes: {len(recipes)}")
by_type = {}
for r in recipes:
    t = r['meal_type']
    by_type[t] = by_type.get(t, 0) + 1
print(f"By type: {by_type}")
all_have_cals = all(r.get('calories', 0) > 0 for r in recipes)
all_have_images = all(r.get('image') for r in recipes)
print(f"All have calories: {all_have_cals}")
print(f"All have images: {all_have_images}")
dia_count = sum(1 for r in recipes if 'diabetes' in r.get('goals', []))
print(f"Diabetes-tagged: {dia_count}/{len(recipes)}")
