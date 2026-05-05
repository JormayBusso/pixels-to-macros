"""
Generate a curated recipe JSON for Pixels to Macros.
Focused on:
- European dishes (mostly NW European + Mediterranean)
- Properly categorized (breakfast, lunch, dinner, snack, dessert)
- Diabetic-friendly filtering (low GI, no white rice, no excessive sugar)
- Full macros (cal, protein, carbs, fat, fiber, sugar)
- Images from TheMealDB where possible
- Per-serving nutrition
"""
import json
import os

# Each recipe has full nutrition per serving, proper meal_type, and real images.
# For diabetic goal: low GI carbs, high fiber, moderate portions, no refined grains/sugar.
# "dessert" is a new meal_type we'll add.

recipes = [
    # ═══════════════════════ BREAKFAST ═══════════════════════
    {
        "id": "eu-b-001",
        "name": "Greek Yogurt with Berries & Walnuts",
        "image": "https://www.themealdb.com/images/media/meals/m2bnlm1764436938.jpg",
        "meal_type": "breakfast",
        "goals": ["diabetes", "weight_loss", "maintain"],
        "minutes": 5,
        "servings": 1,
        "tags": ["quick", "high-protein", "low-gi"],
        "ingredients": [
            {"name": "Greek yogurt (full-fat)", "amount": "200g"},
            {"name": "Mixed berries (blueberries, raspberries)", "amount": "80g"},
            {"name": "Walnuts, chopped", "amount": "20g"},
            {"name": "Chia seeds", "amount": "1 tsp"},
            {"name": "Cinnamon", "amount": "pinch"}
        ],
        "steps": [
            "Spoon Greek yogurt into a bowl.",
            "Top with mixed berries and chopped walnuts.",
            "Sprinkle chia seeds and cinnamon on top.",
            "Serve immediately."
        ],
        "source": "Curated",
        "calories": 310,
        "protein_g": 18,
        "carbs_g": 16,
        "fat_g": 21,
        "fiber_g": 4.5,
        "sugar_g": 10
    },
    {
        "id": "eu-b-002",
        "name": "Scrambled Eggs with Smoked Salmon & Avocado",
        "image": "https://www.themealdb.com/images/media/meals/1550441882.jpg",
        "meal_type": "breakfast",
        "goals": ["diabetes", "keto", "muscle", "maintain"],
        "minutes": 10,
        "servings": 1,
        "tags": ["high-protein", "omega-3", "low-carb"],
        "ingredients": [
            {"name": "Eggs", "amount": "3"},
            {"name": "Smoked salmon", "amount": "50g"},
            {"name": "Avocado", "amount": "1/2"},
            {"name": "Butter", "amount": "10g"},
            {"name": "Fresh dill", "amount": "1 tbsp"},
            {"name": "Black pepper", "amount": "to taste"}
        ],
        "steps": [
            "Whisk eggs in a bowl, season with pepper.",
            "Melt butter in a non-stick pan over medium-low heat.",
            "Pour in eggs, gently stir with a spatula forming soft curds.",
            "Remove from heat while still slightly wet.",
            "Plate with torn smoked salmon and sliced avocado.",
            "Garnish with fresh dill."
        ],
        "source": "Curated",
        "calories": 480,
        "protein_g": 32,
        "carbs_g": 4,
        "fat_g": 37,
        "fiber_g": 5,
        "sugar_g": 1
    },
    {
        "id": "eu-b-003",
        "name": "Overnight Oats with Apple & Cinnamon",
        "image": "https://www.themealdb.com/images/media/meals/0jv5gx1661040802.jpg",
        "meal_type": "breakfast",
        "goals": ["diabetes", "weight_loss", "maintain"],
        "minutes": 5,
        "servings": 1,
        "tags": ["meal-prep", "high-fiber", "low-gi"],
        "ingredients": [
            {"name": "Rolled oats", "amount": "40g"},
            {"name": "Unsweetened almond milk", "amount": "150ml"},
            {"name": "Greek yogurt", "amount": "50g"},
            {"name": "Apple, grated", "amount": "1/2"},
            {"name": "Cinnamon", "amount": "1/2 tsp"},
            {"name": "Flaxseeds", "amount": "1 tbsp"},
            {"name": "Almonds, sliced", "amount": "10g"}
        ],
        "steps": [
            "Combine oats, almond milk, yogurt, grated apple, cinnamon, and flaxseeds in a jar.",
            "Stir well, seal, and refrigerate overnight (or at least 4 hours).",
            "In the morning, top with sliced almonds.",
            "Eat cold or warm briefly in the microwave."
        ],
        "source": "Curated",
        "calories": 295,
        "protein_g": 12,
        "carbs_g": 35,
        "fat_g": 12,
        "fiber_g": 7,
        "sugar_g": 12
    },
    {
        "id": "eu-b-004",
        "name": "Spinach & Feta Omelette",
        "image": "https://www.themealdb.com/images/media/meals/ustsqw1468250014.jpg",
        "meal_type": "breakfast",
        "goals": ["diabetes", "keto", "muscle", "maintain"],
        "minutes": 10,
        "servings": 1,
        "tags": ["high-protein", "low-carb", "vegetarian"],
        "ingredients": [
            {"name": "Eggs", "amount": "3"},
            {"name": "Fresh spinach", "amount": "60g"},
            {"name": "Feta cheese, crumbled", "amount": "30g"},
            {"name": "Olive oil", "amount": "1 tsp"},
            {"name": "Cherry tomatoes", "amount": "4"},
            {"name": "Salt & pepper", "amount": "to taste"}
        ],
        "steps": [
            "Heat olive oil in a non-stick pan over medium heat.",
            "Wilt spinach in the pan for 1 minute, set aside.",
            "Whisk eggs with salt and pepper, pour into the same pan.",
            "Cook until edges set, tilt pan to let uncooked egg flow underneath.",
            "Add spinach and feta to one half.",
            "Fold omelette and serve with halved cherry tomatoes."
        ],
        "source": "Curated",
        "calories": 365,
        "protein_g": 25,
        "carbs_g": 4,
        "fat_g": 28,
        "fiber_g": 2,
        "sugar_g": 3
    },
    {
        "id": "eu-b-005",
        "name": "Whole Grain Toast with Avocado & Poached Egg",
        "image": "https://www.themealdb.com/images/media/meals/1550441882.jpg",
        "meal_type": "breakfast",
        "goals": ["diabetes", "maintain", "muscle"],
        "minutes": 12,
        "servings": 1,
        "tags": ["high-fiber", "balanced"],
        "ingredients": [
            {"name": "Whole grain bread (dark rye)", "amount": "1 slice"},
            {"name": "Avocado", "amount": "1/2"},
            {"name": "Egg", "amount": "1"},
            {"name": "Lemon juice", "amount": "1 tsp"},
            {"name": "Chilli flakes", "amount": "pinch"},
            {"name": "Salt & pepper", "amount": "to taste"}
        ],
        "steps": [
            "Toast the bread until crispy.",
            "Mash avocado with lemon juice, salt and pepper.",
            "Bring a small pot of water to a gentle simmer, add a splash of vinegar.",
            "Crack egg into a cup, swirl water, gently slide egg in. Poach 3 minutes.",
            "Spread avocado on toast, top with poached egg.",
            "Sprinkle chilli flakes."
        ],
        "source": "Curated",
        "calories": 320,
        "protein_g": 14,
        "carbs_g": 22,
        "fat_g": 20,
        "fiber_g": 8,
        "sugar_g": 2
    },
    {
        "id": "eu-b-006",
        "name": "Cottage Cheese Pancakes (Sugar-Free)",
        "image": "https://www.themealdb.com/images/media/meals/rwuyqx1511383174.jpg",
        "meal_type": "breakfast",
        "goals": ["diabetes", "muscle", "maintain"],
        "minutes": 15,
        "servings": 2,
        "tags": ["high-protein", "low-sugar"],
        "ingredients": [
            {"name": "Cottage cheese", "amount": "200g"},
            {"name": "Eggs", "amount": "2"},
            {"name": "Oat flour", "amount": "40g"},
            {"name": "Baking powder", "amount": "1/2 tsp"},
            {"name": "Vanilla extract", "amount": "1 tsp"},
            {"name": "Coconut oil (for pan)", "amount": "1 tsp"},
            {"name": "Fresh berries (to serve)", "amount": "60g"}
        ],
        "steps": [
            "Blend cottage cheese, eggs, oat flour, baking powder and vanilla until smooth.",
            "Heat a non-stick pan with coconut oil over medium heat.",
            "Pour small pancakes (~8cm), cook 2 minutes per side until golden.",
            "Serve with fresh berries."
        ],
        "source": "Curated",
        "calories": 245,
        "protein_g": 20,
        "carbs_g": 18,
        "fat_g": 10,
        "fiber_g": 3,
        "sugar_g": 5
    },
    {
        "id": "eu-b-007",
        "name": "Bircher Muesli",
        "image": "https://www.themealdb.com/images/media/meals/0jv5gx1661040802.jpg",
        "meal_type": "breakfast",
        "goals": ["diabetes", "weight_loss", "maintain"],
        "minutes": 5,
        "servings": 1,
        "tags": ["swiss", "high-fiber", "meal-prep"],
        "ingredients": [
            {"name": "Rolled oats", "amount": "40g"},
            {"name": "Natural yogurt", "amount": "100g"},
            {"name": "Grated apple (with skin)", "amount": "1/2"},
            {"name": "Hazelnuts, chopped", "amount": "15g"},
            {"name": "Lemon juice", "amount": "1 tsp"},
            {"name": "Unsweetened almond milk", "amount": "50ml"}
        ],
        "steps": [
            "Mix oats with yogurt, almond milk and lemon juice.",
            "Grate apple directly into the mixture.",
            "Refrigerate overnight.",
            "Top with hazelnuts before serving."
        ],
        "source": "Curated",
        "calories": 305,
        "protein_g": 11,
        "carbs_g": 34,
        "fat_g": 14,
        "fiber_g": 6,
        "sugar_g": 14
    },
    {
        "id": "eu-b-008",
        "name": "Eggs Benedict with Turkey Ham",
        "image": "https://www.themealdb.com/images/media/meals/vwsxry1764113206.jpg",
        "meal_type": "breakfast",
        "goals": ["muscle", "maintain"],
        "minutes": 20,
        "servings": 2,
        "tags": ["brunch", "classic"],
        "ingredients": [
            {"name": "English muffin (wholemeal)", "amount": "2"},
            {"name": "Eggs", "amount": "4"},
            {"name": "Turkey ham slices", "amount": "4"},
            {"name": "Butter", "amount": "60g"},
            {"name": "Egg yolks (for hollandaise)", "amount": "2"},
            {"name": "Lemon juice", "amount": "1 tbsp"},
            {"name": "Chives, chopped", "amount": "1 tbsp"}
        ],
        "steps": [
            "Make hollandaise: whisk egg yolks and lemon juice over a bain-marie, slowly drizzle in melted butter until thick.",
            "Toast muffin halves, place turkey ham on each.",
            "Poach eggs in simmering water for 3 minutes.",
            "Place eggs on ham, spoon hollandaise over.",
            "Garnish with chives."
        ],
        "source": "Curated",
        "calories": 420,
        "protein_g": 24,
        "carbs_g": 20,
        "fat_g": 28,
        "fiber_g": 3,
        "sugar_g": 2
    },

    # ═══════════════════════ LUNCH ═══════════════════════
    {
        "id": "eu-l-001",
        "name": "Mediterranean Grilled Chicken Salad",
        "image": "https://www.themealdb.com/images/media/meals/kos9av1699014767.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "weight_loss", "muscle", "maintain"],
        "minutes": 20,
        "servings": 1,
        "tags": ["high-protein", "low-carb", "mediterranean"],
        "ingredients": [
            {"name": "Chicken breast", "amount": "150g"},
            {"name": "Mixed salad greens", "amount": "100g"},
            {"name": "Cherry tomatoes", "amount": "80g"},
            {"name": "Cucumber", "amount": "1/2"},
            {"name": "Red onion", "amount": "1/4"},
            {"name": "Kalamata olives", "amount": "30g"},
            {"name": "Feta cheese", "amount": "30g"},
            {"name": "Extra virgin olive oil", "amount": "1.5 tbsp"},
            {"name": "Lemon juice", "amount": "1 tbsp"},
            {"name": "Oregano", "amount": "1 tsp"}
        ],
        "steps": [
            "Season chicken with oregano, salt, pepper. Grill 5-6 min per side.",
            "Let chicken rest 3 minutes, then slice.",
            "Toss greens, tomatoes, cucumber, onion and olives in a bowl.",
            "Whisk olive oil and lemon juice, drizzle over salad.",
            "Top with sliced chicken and crumbled feta."
        ],
        "source": "Curated",
        "calories": 440,
        "protein_g": 42,
        "carbs_g": 12,
        "fat_g": 26,
        "fiber_g": 4,
        "sugar_g": 6
    },
    {
        "id": "eu-l-002",
        "name": "Italian Minestrone Soup",
        "image": "https://www.themealdb.com/images/media/meals/rvypwy1503069308.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "weight_loss", "vegan", "maintain"],
        "minutes": 35,
        "servings": 4,
        "tags": ["italian", "high-fiber", "low-gi", "vegetable-rich"],
        "ingredients": [
            {"name": "Olive oil", "amount": "2 tbsp"},
            {"name": "Onion, diced", "amount": "1"},
            {"name": "Carrots, diced", "amount": "2"},
            {"name": "Celery stalks, diced", "amount": "2"},
            {"name": "Zucchini, diced", "amount": "1"},
            {"name": "Canned cannellini beans", "amount": "200g"},
            {"name": "Canned diced tomatoes", "amount": "400g"},
            {"name": "Vegetable stock", "amount": "1L"},
            {"name": "Kale, chopped", "amount": "100g"},
            {"name": "Garlic cloves", "amount": "2"},
            {"name": "Italian herbs", "amount": "1 tbsp"},
            {"name": "Parmesan rind (optional)", "amount": "1 piece"}
        ],
        "steps": [
            "Sauté onion, carrots, celery in olive oil for 5 minutes.",
            "Add garlic, cook 1 minute.",
            "Add tomatoes, stock, beans, zucchini, herbs, and Parmesan rind.",
            "Simmer 20 minutes.",
            "Add kale in the last 5 minutes.",
            "Remove rind, season and serve."
        ],
        "source": "Curated",
        "calories": 185,
        "protein_g": 8,
        "carbs_g": 24,
        "fat_g": 7,
        "fiber_g": 8,
        "sugar_g": 8
    },
    {
        "id": "eu-l-003",
        "name": "Lentil & Roasted Vegetable Bowl",
        "image": "https://www.themealdb.com/images/media/meals/9pndnm1764441752.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "vegan", "weight_loss", "maintain"],
        "minutes": 30,
        "servings": 2,
        "tags": ["high-fiber", "plant-protein", "low-gi"],
        "ingredients": [
            {"name": "Green lentils (cooked)", "amount": "200g"},
            {"name": "Sweet potato, cubed", "amount": "150g"},
            {"name": "Bell pepper, chopped", "amount": "1"},
            {"name": "Red onion, wedged", "amount": "1"},
            {"name": "Olive oil", "amount": "2 tbsp"},
            {"name": "Cumin", "amount": "1 tsp"},
            {"name": "Smoked paprika", "amount": "1/2 tsp"},
            {"name": "Baby spinach", "amount": "60g"},
            {"name": "Tahini", "amount": "1 tbsp"},
            {"name": "Lemon juice", "amount": "1 tbsp"}
        ],
        "steps": [
            "Preheat oven to 200°C. Toss sweet potato, pepper, onion with oil and spices.",
            "Roast for 20 minutes until tender.",
            "Warm lentils, toss with spinach.",
            "Assemble bowls: lentils, roasted veg.",
            "Drizzle with tahini mixed with lemon juice."
        ],
        "source": "Curated",
        "calories": 365,
        "protein_g": 16,
        "carbs_g": 42,
        "fat_g": 14,
        "fiber_g": 12,
        "sugar_g": 10
    },
    {
        "id": "eu-l-004",
        "name": "Tuna Niçoise Salad",
        "image": "https://www.themealdb.com/images/media/meals/yypvst1511304979.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "weight_loss", "maintain", "keto"],
        "minutes": 20,
        "servings": 1,
        "tags": ["french", "omega-3", "low-carb"],
        "ingredients": [
            {"name": "Tuna steak (or canned)", "amount": "150g"},
            {"name": "Green beans", "amount": "80g"},
            {"name": "Hard-boiled egg", "amount": "1"},
            {"name": "Cherry tomatoes", "amount": "6"},
            {"name": "Niçoise olives", "amount": "30g"},
            {"name": "Mixed leaves", "amount": "60g"},
            {"name": "Extra virgin olive oil", "amount": "1 tbsp"},
            {"name": "Dijon mustard", "amount": "1 tsp"},
            {"name": "Red wine vinegar", "amount": "1 tsp"}
        ],
        "steps": [
            "Blanch green beans 3 minutes, cool in ice water.",
            "Sear tuna 2 min per side (or use drained canned).",
            "Arrange leaves, beans, halved tomatoes, olives, halved egg on plate.",
            "Flake tuna on top.",
            "Whisk oil, mustard, vinegar for dressing. Drizzle over."
        ],
        "source": "Curated",
        "calories": 395,
        "protein_g": 40,
        "carbs_g": 10,
        "fat_g": 22,
        "fiber_g": 4,
        "sugar_g": 5
    },
    {
        "id": "eu-l-005",
        "name": "Dutch Erwtensoep (Split Pea Soup)",
        "image": "https://www.themealdb.com/images/media/meals/0jv5gx1661040802.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "muscle", "maintain"],
        "minutes": 90,
        "servings": 6,
        "tags": ["dutch", "high-fiber", "hearty"],
        "ingredients": [
            {"name": "Split peas", "amount": "500g"},
            {"name": "Smoked sausage (rookworst)", "amount": "200g"},
            {"name": "Leek, sliced", "amount": "2"},
            {"name": "Celeriac, diced", "amount": "200g"},
            {"name": "Carrots, diced", "amount": "2"},
            {"name": "Potato (waxy), diced", "amount": "2 small"},
            {"name": "Smoked pork rib", "amount": "200g"},
            {"name": "Water", "amount": "2L"},
            {"name": "Salt & pepper", "amount": "to taste"}
        ],
        "steps": [
            "Rinse split peas. Bring water to boil with peas and pork rib.",
            "Simmer 45 min, skim foam.",
            "Add celeriac, carrots, potato. Cook 25 min more.",
            "Remove rib, shred meat, return to pot.",
            "Add leek in last 10 minutes.",
            "Slice rookworst, add to soup.",
            "Serve thick — spoon should stand up."
        ],
        "source": "Curated",
        "calories": 380,
        "protein_g": 26,
        "carbs_g": 40,
        "fat_g": 12,
        "fiber_g": 14,
        "sugar_g": 6
    },
    {
        "id": "eu-l-006",
        "name": "Caprese Wrap with Pesto",
        "image": "https://www.themealdb.com/images/media/meals/1549542994.jpg",
        "meal_type": "lunch",
        "goals": ["maintain", "muscle"],
        "minutes": 10,
        "servings": 1,
        "tags": ["italian", "quick", "vegetarian"],
        "ingredients": [
            {"name": "Whole grain wrap", "amount": "1 large"},
            {"name": "Fresh mozzarella", "amount": "80g"},
            {"name": "Tomato, sliced", "amount": "1"},
            {"name": "Fresh basil leaves", "amount": "6"},
            {"name": "Pesto", "amount": "1 tbsp"},
            {"name": "Balsamic glaze", "amount": "1 tsp"},
            {"name": "Rocket/arugula", "amount": "30g"}
        ],
        "steps": [
            "Spread pesto over the wrap.",
            "Layer mozzarella slices, tomato, basil and rocket.",
            "Drizzle balsamic glaze.",
            "Roll tightly and slice in half."
        ],
        "source": "Curated",
        "calories": 420,
        "protein_g": 22,
        "carbs_g": 28,
        "fat_g": 24,
        "fiber_g": 4,
        "sugar_g": 5
    },
    {
        "id": "eu-l-007",
        "name": "Smoked Mackerel & Beetroot Salad",
        "image": "https://www.themealdb.com/images/media/meals/yypvst1511304979.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "keto", "maintain"],
        "minutes": 10,
        "servings": 1,
        "tags": ["scandinavian", "omega-3", "low-carb"],
        "ingredients": [
            {"name": "Smoked mackerel fillet", "amount": "120g"},
            {"name": "Cooked beetroot, diced", "amount": "100g"},
            {"name": "Horseradish cream", "amount": "1 tbsp"},
            {"name": "Mixed leaves", "amount": "60g"},
            {"name": "Red onion, thinly sliced", "amount": "1/4"},
            {"name": "Walnuts", "amount": "15g"},
            {"name": "Apple cider vinegar", "amount": "1 tsp"}
        ],
        "steps": [
            "Flake mackerel into large pieces.",
            "Arrange leaves on plate, scatter beetroot and onion.",
            "Top with mackerel and walnuts.",
            "Mix horseradish cream with vinegar, drizzle over."
        ],
        "source": "Curated",
        "calories": 420,
        "protein_g": 28,
        "carbs_g": 14,
        "fat_g": 29,
        "fiber_g": 4,
        "sugar_g": 10
    },
    {
        "id": "eu-l-008",
        "name": "Cauliflower & Leek Soup",
        "image": "https://www.themealdb.com/images/media/meals/7n8su21576061865.jpg",
        "meal_type": "lunch",
        "goals": ["diabetes", "weight_loss", "keto", "vegan"],
        "minutes": 25,
        "servings": 4,
        "tags": ["low-carb", "creamy", "comfort"],
        "ingredients": [
            {"name": "Cauliflower, chopped", "amount": "1 medium"},
            {"name": "Leek, sliced", "amount": "2"},
            {"name": "Garlic", "amount": "2 cloves"},
            {"name": "Olive oil", "amount": "2 tbsp"},
            {"name": "Vegetable stock", "amount": "750ml"},
            {"name": "Nutmeg", "amount": "pinch"},
            {"name": "Salt & pepper", "amount": "to taste"}
        ],
        "steps": [
            "Sauté leek and garlic in olive oil for 3 minutes.",
            "Add cauliflower and stock. Bring to boil.",
            "Simmer 15 minutes until cauliflower is tender.",
            "Blend until smooth. Season with nutmeg, salt, pepper.",
            "Serve with a drizzle of olive oil."
        ],
        "source": "Curated",
        "calories": 130,
        "protein_g": 5,
        "carbs_g": 12,
        "fat_g": 7,
        "fiber_g": 4,
        "sugar_g": 5
    },

    # ═══════════════════════ DINNER ═══════════════════════
    {
        "id": "eu-d-001",
        "name": "Pan-Seared Salmon with Roasted Vegetables",
        "image": "https://www.themealdb.com/images/media/meals/1548772327.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "keto", "muscle", "maintain"],
        "minutes": 30,
        "servings": 2,
        "tags": ["omega-3", "high-protein", "low-carb"],
        "ingredients": [
            {"name": "Salmon fillets", "amount": "2 × 150g"},
            {"name": "Broccoli florets", "amount": "200g"},
            {"name": "Cherry tomatoes", "amount": "150g"},
            {"name": "Asparagus", "amount": "150g"},
            {"name": "Olive oil", "amount": "2 tbsp"},
            {"name": "Lemon", "amount": "1"},
            {"name": "Garlic", "amount": "2 cloves"},
            {"name": "Fresh thyme", "amount": "few sprigs"},
            {"name": "Salt & pepper", "amount": "to taste"}
        ],
        "steps": [
            "Preheat oven to 200°C. Toss vegetables with 1 tbsp oil, garlic, thyme. Roast 20 min.",
            "Pat salmon dry, season with salt and pepper.",
            "Heat remaining oil in an oven-safe pan. Sear salmon skin-side down 4 min.",
            "Flip, cook 2 more minutes.",
            "Squeeze lemon over salmon, serve with roasted veg."
        ],
        "source": "Curated",
        "calories": 420,
        "protein_g": 38,
        "carbs_g": 12,
        "fat_g": 25,
        "fiber_g": 5,
        "sugar_g": 5
    },
    {
        "id": "eu-d-002",
        "name": "Chicken Thigh with Ratatouille",
        "image": "https://www.themealdb.com/images/media/meals/wrpwuu1511786491.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "weight_loss", "maintain"],
        "minutes": 45,
        "servings": 4,
        "tags": ["french", "mediterranean", "low-gi"],
        "ingredients": [
            {"name": "Chicken thighs (skin-on)", "amount": "4"},
            {"name": "Zucchini", "amount": "2"},
            {"name": "Eggplant", "amount": "1"},
            {"name": "Bell peppers (mixed)", "amount": "2"},
            {"name": "Onion", "amount": "1"},
            {"name": "Canned tomatoes", "amount": "400g"},
            {"name": "Garlic", "amount": "3 cloves"},
            {"name": "Herbes de Provence", "amount": "2 tsp"},
            {"name": "Olive oil", "amount": "3 tbsp"}
        ],
        "steps": [
            "Season chicken with herbs, salt, pepper. Sear skin-side down 5 min.",
            "Flip, cook 3 min. Remove and set aside.",
            "Dice all vegetables. Sauté onion and garlic 3 min in same pan.",
            "Add eggplant, peppers, zucchini. Cook 5 min.",
            "Add canned tomatoes and herbs. Nestle chicken in.",
            "Cover, simmer 25 min until chicken is cooked through."
        ],
        "source": "Curated",
        "calories": 380,
        "protein_g": 32,
        "carbs_g": 16,
        "fat_g": 22,
        "fiber_g": 6,
        "sugar_g": 10
    },
    {
        "id": "eu-d-003",
        "name": "Beef Stew with Root Vegetables",
        "image": "https://www.themealdb.com/images/media/meals/svprys1511176755.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "muscle", "maintain"],
        "minutes": 120,
        "servings": 6,
        "tags": ["comfort", "high-protein", "low-gi"],
        "ingredients": [
            {"name": "Beef chuck, cubed", "amount": "800g"},
            {"name": "Carrots", "amount": "3"},
            {"name": "Parsnips", "amount": "2"},
            {"name": "Celery", "amount": "2 stalks"},
            {"name": "Onion", "amount": "2"},
            {"name": "Garlic", "amount": "3 cloves"},
            {"name": "Beef stock", "amount": "500ml"},
            {"name": "Red wine", "amount": "200ml"},
            {"name": "Tomato paste", "amount": "2 tbsp"},
            {"name": "Bay leaves", "amount": "2"},
            {"name": "Thyme", "amount": "3 sprigs"},
            {"name": "Olive oil", "amount": "2 tbsp"}
        ],
        "steps": [
            "Brown beef in batches in a hot Dutch oven with oil. Set aside.",
            "Sauté onion, garlic 3 min. Add tomato paste, cook 1 min.",
            "Deglaze with red wine, scrape bottom.",
            "Return beef, add stock, bay leaves, thyme.",
            "Bring to simmer, cover, cook 1 hour.",
            "Add carrots, parsnips, celery. Cook 40 min more until tender.",
            "Season and serve."
        ],
        "source": "Curated",
        "calories": 380,
        "protein_g": 36,
        "carbs_g": 18,
        "fat_g": 16,
        "fiber_g": 5,
        "sugar_g": 8
    },
    {
        "id": "eu-d-004",
        "name": "Baked Cod with Herb Crust & Green Beans",
        "image": "https://www.themealdb.com/images/media/meals/vuxgtm1764112923.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "weight_loss", "maintain"],
        "minutes": 25,
        "servings": 2,
        "tags": ["low-calorie", "high-protein", "lean"],
        "ingredients": [
            {"name": "Cod fillets", "amount": "2 × 160g"},
            {"name": "Wholemeal breadcrumbs", "amount": "30g"},
            {"name": "Parsley, chopped", "amount": "2 tbsp"},
            {"name": "Lemon zest", "amount": "1 lemon"},
            {"name": "Garlic, minced", "amount": "1 clove"},
            {"name": "Olive oil", "amount": "1 tbsp"},
            {"name": "Green beans", "amount": "200g"},
            {"name": "Butter", "amount": "10g"}
        ],
        "steps": [
            "Preheat oven to 200°C.",
            "Mix breadcrumbs, parsley, lemon zest, garlic and oil.",
            "Place cod on a baking tray, press herb crust on top.",
            "Bake 12-15 minutes until fish flakes.",
            "Blanch green beans, toss with butter.",
            "Serve cod on beans with a lemon wedge."
        ],
        "source": "Curated",
        "calories": 290,
        "protein_g": 36,
        "carbs_g": 12,
        "fat_g": 11,
        "fiber_g": 4,
        "sugar_g": 3
    },
    {
        "id": "eu-d-005",
        "name": "Turkey Meatballs in Tomato Sauce",
        "image": "https://www.themealdb.com/images/media/meals/8rfd4q1764112993.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "weight_loss", "muscle", "maintain"],
        "minutes": 35,
        "servings": 4,
        "tags": ["lean", "high-protein", "family"],
        "ingredients": [
            {"name": "Turkey mince", "amount": "500g"},
            {"name": "Egg", "amount": "1"},
            {"name": "Oat flour", "amount": "30g"},
            {"name": "Garlic", "amount": "2 cloves"},
            {"name": "Onion, grated", "amount": "1/2"},
            {"name": "Canned tomatoes", "amount": "400g"},
            {"name": "Basil", "amount": "fresh handful"},
            {"name": "Olive oil", "amount": "1 tbsp"},
            {"name": "Courgette (zucchini) noodles", "amount": "400g"}
        ],
        "steps": [
            "Mix turkey, egg, oat flour, garlic, onion, salt, pepper. Form 16 balls.",
            "Brown meatballs in olive oil, 3 min per side.",
            "Add canned tomatoes, simmer 15 min.",
            "Spiralize courgettes or buy pre-made.",
            "Serve meatballs and sauce over courgette noodles, top with basil."
        ],
        "source": "Curated",
        "calories": 310,
        "protein_g": 34,
        "carbs_g": 14,
        "fat_g": 13,
        "fiber_g": 4,
        "sugar_g": 7
    },
    {
        "id": "eu-d-006",
        "name": "Grilled Lamb Chops with Mint & Quinoa",
        "image": "https://www.themealdb.com/images/media/meals/1525876468.jpg",
        "meal_type": "dinner",
        "goals": ["muscle", "maintain"],
        "minutes": 30,
        "servings": 2,
        "tags": ["high-protein", "mediterranean"],
        "ingredients": [
            {"name": "Lamb chops", "amount": "4 (≈400g)"},
            {"name": "Quinoa", "amount": "120g dry"},
            {"name": "Fresh mint", "amount": "large handful"},
            {"name": "Cucumber", "amount": "1/2"},
            {"name": "Cherry tomatoes", "amount": "100g"},
            {"name": "Lemon juice", "amount": "2 tbsp"},
            {"name": "Olive oil", "amount": "2 tbsp"},
            {"name": "Garlic", "amount": "2 cloves"}
        ],
        "steps": [
            "Cook quinoa according to package. Cool slightly.",
            "Rub lamb with garlic, oil, salt, pepper. Grill 3-4 min per side (medium).",
            "Rest lamb 5 minutes.",
            "Toss quinoa with diced cucumber, tomatoes, mint, lemon juice, oil.",
            "Serve lamb chops over quinoa salad."
        ],
        "source": "Curated",
        "calories": 520,
        "protein_g": 40,
        "carbs_g": 32,
        "fat_g": 24,
        "fiber_g": 5,
        "sugar_g": 4
    },
    {
        "id": "eu-d-007",
        "name": "Stuffed Bell Peppers (Low Carb)",
        "image": "https://www.themealdb.com/images/media/meals/c7lyxv1764441697.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "weight_loss", "keto", "maintain"],
        "minutes": 40,
        "servings": 4,
        "tags": ["low-carb", "high-protein", "family"],
        "ingredients": [
            {"name": "Bell peppers (large)", "amount": "4"},
            {"name": "Lean minced beef", "amount": "400g"},
            {"name": "Cauliflower rice", "amount": "200g"},
            {"name": "Onion, diced", "amount": "1"},
            {"name": "Garlic", "amount": "2 cloves"},
            {"name": "Canned tomatoes", "amount": "200g"},
            {"name": "Mozzarella, grated", "amount": "80g"},
            {"name": "Italian herbs", "amount": "1 tbsp"},
            {"name": "Olive oil", "amount": "1 tbsp"}
        ],
        "steps": [
            "Preheat oven to 190°C. Cut tops off peppers, remove seeds.",
            "Brown mince with onion and garlic. Add cauliflower rice.",
            "Stir in tomatoes and herbs, cook 5 min.",
            "Stuff peppers with mixture, place in baking dish.",
            "Top with mozzarella.",
            "Bake 25 minutes until peppers are tender and cheese is golden."
        ],
        "source": "Curated",
        "calories": 320,
        "protein_g": 30,
        "carbs_g": 14,
        "fat_g": 16,
        "fiber_g": 5,
        "sugar_g": 8
    },
    {
        "id": "eu-d-008",
        "name": "Mushroom Risotto (with Cauliflower Rice)",
        "image": "https://www.themealdb.com/images/media/meals/2x7mk71514264681.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "keto", "maintain"],
        "minutes": 25,
        "servings": 2,
        "tags": ["italian", "low-carb", "vegetarian"],
        "ingredients": [
            {"name": "Cauliflower rice", "amount": "400g"},
            {"name": "Mixed mushrooms, sliced", "amount": "250g"},
            {"name": "Onion, finely diced", "amount": "1"},
            {"name": "Garlic", "amount": "2 cloves"},
            {"name": "Vegetable stock", "amount": "200ml"},
            {"name": "Parmesan, grated", "amount": "40g"},
            {"name": "Butter", "amount": "20g"},
            {"name": "Fresh thyme", "amount": "2 sprigs"},
            {"name": "White wine", "amount": "50ml"}
        ],
        "steps": [
            "Sauté mushrooms in butter until golden. Set aside.",
            "Cook onion and garlic in same pan 3 min.",
            "Add cauliflower rice, stir 2 min.",
            "Pour in wine and stock, cook 5 min until absorbed.",
            "Stir in mushrooms and Parmesan.",
            "Serve with fresh thyme."
        ],
        "source": "Curated",
        "calories": 260,
        "protein_g": 14,
        "carbs_g": 16,
        "fat_g": 16,
        "fiber_g": 5,
        "sugar_g": 6
    },
    {
        "id": "eu-d-009",
        "name": "Provençal Roasted Chicken",
        "image": "https://www.themealdb.com/images/media/meals/qysyss1511558054.jpg",
        "meal_type": "dinner",
        "goals": ["diabetes", "muscle", "maintain", "keto"],
        "minutes": 60,
        "servings": 4,
        "tags": ["french", "one-pan", "roast"],
        "ingredients": [
            {"name": "Whole chicken (or 4 leg portions)", "amount": "1.5kg"},
            {"name": "New potatoes (optional)", "amount": "400g"},
            {"name": "Olives", "amount": "80g"},
            {"name": "Cherry tomatoes (vine)", "amount": "200g"},
            {"name": "Garlic bulb", "amount": "1"},
            {"name": "Lemon", "amount": "1"},
            {"name": "Herbes de Provence", "amount": "2 tbsp"},
            {"name": "Olive oil", "amount": "3 tbsp"}
        ],
        "steps": [
            "Preheat oven to 200°C.",
            "Rub chicken with herbs, salt, pepper, and oil. Stuff with lemon and garlic.",
            "Arrange potatoes, olives, tomatoes around chicken in roasting tin.",
            "Roast 50-60 min until juices run clear.",
            "Rest 10 minutes before carving."
        ],
        "source": "Curated",
        "calories": 420,
        "protein_g": 38,
        "carbs_g": 18,
        "fat_g": 22,
        "fiber_g": 3,
        "sugar_g": 4
    },
    {
        "id": "eu-d-010",
        "name": "Spaghetti Bolognese (Whole Wheat)",
        "image": "https://www.themealdb.com/images/media/meals/sutysw1468247559.jpg",
        "meal_type": "dinner",
        "goals": ["muscle", "maintain"],
        "minutes": 45,
        "servings": 4,
        "tags": ["italian", "family", "classic"],
        "ingredients": [
            {"name": "Whole wheat spaghetti", "amount": "320g"},
            {"name": "Lean beef mince", "amount": "400g"},
            {"name": "Onion", "amount": "1"},
            {"name": "Carrots", "amount": "2"},
            {"name": "Celery", "amount": "1 stalk"},
            {"name": "Garlic", "amount": "3 cloves"},
            {"name": "Canned tomatoes", "amount": "400g"},
            {"name": "Tomato paste", "amount": "2 tbsp"},
            {"name": "Red wine", "amount": "100ml"},
            {"name": "Italian herbs", "amount": "1 tbsp"},
            {"name": "Parmesan", "amount": "30g"}
        ],
        "steps": [
            "Finely dice onion, carrots, celery (soffritto). Sauté 5 min.",
            "Add mince, brown well. Add garlic.",
            "Stir in tomato paste, cook 2 min.",
            "Add wine, let reduce. Then add canned tomatoes and herbs.",
            "Simmer 30 min on low heat.",
            "Cook pasta al dente. Toss with sauce.",
            "Serve with grated Parmesan."
        ],
        "source": "Curated",
        "calories": 480,
        "protein_g": 32,
        "carbs_g": 52,
        "fat_g": 14,
        "fiber_g": 8,
        "sugar_g": 8
    },

    # ═══════════════════════ SNACKS ═══════════════════════
    {
        "id": "eu-s-001",
        "name": "Hummus with Veggie Sticks",
        "image": "https://www.themealdb.com/images/media/meals/vlrppq1764113063.jpg",
        "meal_type": "snack",
        "goals": ["diabetes", "vegan", "weight_loss", "maintain"],
        "minutes": 5,
        "servings": 2,
        "tags": ["quick", "high-fiber", "plant-based"],
        "ingredients": [
            {"name": "Hummus", "amount": "100g"},
            {"name": "Carrots, sticks", "amount": "1"},
            {"name": "Cucumber, sticks", "amount": "1/2"},
            {"name": "Bell pepper, sliced", "amount": "1"},
            {"name": "Cherry tomatoes", "amount": "6"}
        ],
        "steps": [
            "Scoop hummus into a bowl.",
            "Cut vegetables into sticks.",
            "Arrange around the hummus for dipping."
        ],
        "source": "Curated",
        "calories": 180,
        "protein_g": 7,
        "carbs_g": 18,
        "fat_g": 9,
        "fiber_g": 6,
        "sugar_g": 6
    },
    {
        "id": "eu-s-002",
        "name": "Boiled Eggs with Everything Seasoning",
        "image": "https://www.themealdb.com/images/media/meals/1550441882.jpg",
        "meal_type": "snack",
        "goals": ["diabetes", "keto", "muscle", "maintain"],
        "minutes": 12,
        "servings": 1,
        "tags": ["high-protein", "quick", "portable"],
        "ingredients": [
            {"name": "Eggs", "amount": "2"},
            {"name": "Everything bagel seasoning", "amount": "1 tsp"},
            {"name": "Hot sauce (optional)", "amount": "dash"}
        ],
        "steps": [
            "Bring water to boil. Lower eggs in, cook 7 minutes for jammy or 10 for hard.",
            "Cool in ice water, peel.",
            "Sprinkle with seasoning. Add hot sauce if desired."
        ],
        "source": "Curated",
        "calories": 155,
        "protein_g": 13,
        "carbs_g": 1,
        "fat_g": 11,
        "fiber_g": 0,
        "sugar_g": 1
    },
    {
        "id": "eu-s-003",
        "name": "Apple Slices with Almond Butter",
        "image": "https://www.themealdb.com/images/media/meals/adxcbq1619787919.jpg",
        "meal_type": "snack",
        "goals": ["diabetes", "maintain"],
        "minutes": 3,
        "servings": 1,
        "tags": ["quick", "balanced", "natural"],
        "ingredients": [
            {"name": "Apple (Granny Smith)", "amount": "1"},
            {"name": "Almond butter (no added sugar)", "amount": "1 tbsp"},
            {"name": "Cinnamon", "amount": "pinch"}
        ],
        "steps": [
            "Slice apple into wedges.",
            "Serve with almond butter for dipping.",
            "Sprinkle cinnamon on top."
        ],
        "source": "Curated",
        "calories": 190,
        "protein_g": 4,
        "carbs_g": 22,
        "fat_g": 10,
        "fiber_g": 5,
        "sugar_g": 15
    },
    {
        "id": "eu-s-004",
        "name": "Mixed Nuts & Dark Chocolate",
        "image": "https://www.themealdb.com/images/media/meals/adxcbq1619787919.jpg",
        "meal_type": "snack",
        "goals": ["diabetes", "keto", "maintain"],
        "minutes": 2,
        "servings": 1,
        "tags": ["portable", "satisfying", "healthy-fat"],
        "ingredients": [
            {"name": "Mixed nuts (unsalted)", "amount": "30g"},
            {"name": "Dark chocolate (85%+)", "amount": "15g"}
        ],
        "steps": [
            "Portion nuts and chocolate into a small container.",
            "Enjoy as an afternoon snack."
        ],
        "source": "Curated",
        "calories": 240,
        "protein_g": 6,
        "carbs_g": 10,
        "fat_g": 20,
        "fiber_g": 4,
        "sugar_g": 4
    },
    {
        "id": "eu-s-005",
        "name": "Cottage Cheese with Cucumber & Dill",
        "image": "https://www.themealdb.com/images/media/meals/m2bnlm1764436938.jpg",
        "meal_type": "snack",
        "goals": ["diabetes", "weight_loss", "muscle", "maintain"],
        "minutes": 3,
        "servings": 1,
        "tags": ["high-protein", "low-carb"],
        "ingredients": [
            {"name": "Cottage cheese", "amount": "150g"},
            {"name": "Cucumber, diced", "amount": "1/4"},
            {"name": "Fresh dill", "amount": "1 tbsp"},
            {"name": "Black pepper", "amount": "pinch"},
            {"name": "Pumpkin seeds", "amount": "1 tbsp"}
        ],
        "steps": [
            "Spoon cottage cheese into a bowl.",
            "Top with diced cucumber, dill, pumpkin seeds.",
            "Season with pepper."
        ],
        "source": "Curated",
        "calories": 165,
        "protein_g": 18,
        "carbs_g": 5,
        "fat_g": 8,
        "fiber_g": 1,
        "sugar_g": 3
    },
    {
        "id": "eu-s-006",
        "name": "Oat & Seed Energy Balls",
        "image": "https://www.themealdb.com/images/media/meals/0jv5gx1661040802.jpg",
        "meal_type": "snack",
        "goals": ["maintain", "muscle"],
        "minutes": 15,
        "servings": 12,
        "tags": ["meal-prep", "portable", "no-bake"],
        "ingredients": [
            {"name": "Rolled oats", "amount": "100g"},
            {"name": "Peanut butter", "amount": "80g"},
            {"name": "Honey", "amount": "2 tbsp"},
            {"name": "Dark chocolate chips", "amount": "30g"},
            {"name": "Chia seeds", "amount": "1 tbsp"},
            {"name": "Flaxseeds", "amount": "1 tbsp"},
            {"name": "Vanilla extract", "amount": "1 tsp"}
        ],
        "steps": [
            "Mix all ingredients in a bowl until combined.",
            "Refrigerate 30 minutes to firm up.",
            "Roll into 12 balls (≈ golf ball size).",
            "Store in fridge up to 1 week."
        ],
        "source": "Curated",
        "calories": 115,
        "protein_g": 4,
        "carbs_g": 12,
        "fat_g": 6,
        "fiber_g": 2,
        "sugar_g": 5
    },

    # ═══════════════════════ DESSERT ═══════════════════════
    {
        "id": "eu-ds-001",
        "name": "Greek Yogurt Panna Cotta with Berry Coulis",
        "image": "https://www.themealdb.com/images/media/meals/m2bnlm1764436938.jpg",
        "meal_type": "dessert",
        "goals": ["diabetes", "maintain"],
        "minutes": 15,
        "servings": 4,
        "tags": ["low-sugar", "elegant", "make-ahead"],
        "ingredients": [
            {"name": "Greek yogurt", "amount": "400g"},
            {"name": "Heavy cream", "amount": "100ml"},
            {"name": "Gelatin sheets", "amount": "3"},
            {"name": "Vanilla extract", "amount": "1 tsp"},
            {"name": "Erythritol (or Stevia)", "amount": "2 tbsp"},
            {"name": "Mixed berries (for coulis)", "amount": "150g"},
            {"name": "Lemon juice", "amount": "1 tbsp"}
        ],
        "steps": [
            "Soak gelatin in cold water 5 min.",
            "Warm cream gently (don't boil), dissolve drained gelatin in it.",
            "Stir in yogurt, vanilla, sweetener until smooth.",
            "Pour into 4 ramekins, chill at least 4 hours.",
            "Simmer berries with lemon juice until broken down. Cool.",
            "Serve panna cotta topped with berry coulis."
        ],
        "source": "Curated",
        "calories": 170,
        "protein_g": 10,
        "carbs_g": 10,
        "fat_g": 10,
        "fiber_g": 2,
        "sugar_g": 7
    },
    {
        "id": "eu-ds-002",
        "name": "Dark Chocolate Avocado Mousse",
        "image": "https://www.themealdb.com/images/media/meals/adxcbq1619787919.jpg",
        "meal_type": "dessert",
        "goals": ["diabetes", "keto", "vegan"],
        "minutes": 10,
        "servings": 2,
        "tags": ["no-bake", "healthy-fat", "low-sugar"],
        "ingredients": [
            {"name": "Ripe avocado", "amount": "1 large"},
            {"name": "Cocoa powder (unsweetened)", "amount": "30g"},
            {"name": "Almond milk", "amount": "3 tbsp"},
            {"name": "Vanilla extract", "amount": "1 tsp"},
            {"name": "Erythritol", "amount": "2 tbsp"},
            {"name": "Pinch of salt", "amount": "1"}
        ],
        "steps": [
            "Blend all ingredients in a food processor until silky smooth.",
            "Taste and adjust sweetness.",
            "Divide into 2 glasses, chill 30 min.",
            "Serve with fresh raspberries if desired."
        ],
        "source": "Curated",
        "calories": 210,
        "protein_g": 4,
        "carbs_g": 12,
        "fat_g": 17,
        "fiber_g": 8,
        "sugar_g": 2
    },
    {
        "id": "eu-ds-003",
        "name": "Baked Cinnamon Apples with Walnuts",
        "image": "https://www.themealdb.com/images/media/meals/adxcbq1619787919.jpg",
        "meal_type": "dessert",
        "goals": ["diabetes", "maintain"],
        "minutes": 30,
        "servings": 2,
        "tags": ["warm", "comforting", "low-sugar"],
        "ingredients": [
            {"name": "Apples (Granny Smith)", "amount": "2"},
            {"name": "Walnuts, chopped", "amount": "30g"},
            {"name": "Cinnamon", "amount": "1 tsp"},
            {"name": "Butter", "amount": "10g"},
            {"name": "Greek yogurt (to serve)", "amount": "60g"},
            {"name": "Nutmeg", "amount": "pinch"}
        ],
        "steps": [
            "Preheat oven to 180°C.",
            "Core apples, score skin around middle.",
            "Fill centres with walnuts, cinnamon, and butter.",
            "Bake 25 minutes until soft.",
            "Serve warm with a dollop of Greek yogurt."
        ],
        "source": "Curated",
        "calories": 195,
        "protein_g": 5,
        "carbs_g": 22,
        "fat_g": 11,
        "fiber_g": 4,
        "sugar_g": 16
    },
]


# Save
out_path = os.path.join(os.path.dirname(__file__), '..', 'assets', 'recipes.json')
with open(out_path, 'w') as f:
    json.dump(recipes, f, indent=2, ensure_ascii=False)

print(f"Wrote {len(recipes)} recipes to {os.path.abspath(out_path)}")
by_type = {}
for r in recipes:
    t = r['meal_type']
    by_type[t] = by_type.get(t, 0) + 1
print(f"By type: {by_type}")
dia_count = sum(1 for r in recipes if 'diabetes' in r.get('goals', []))
print(f"Diabetes-tagged: {dia_count}")
