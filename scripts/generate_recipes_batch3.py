"""Batch 3 - More variety for each category."""
import json, os

base_path = os.path.join(os.path.dirname(__file__), '..', 'assets', 'recipes.json')
with open(base_path, 'r') as f:
    recipes = json.load(f)

extra = [
    # More breakfast
    {
        "id": "eu-b-014", "name": "Chia Pudding with Coconut & Berries",
        "image": "https://www.themealdb.com/images/media/meals/0jv5gx1661040802.jpg",
        "meal_type": "breakfast", "goals": ["diabetes", "vegan", "maintain"],
        "minutes": 5, "servings": 1,
        "tags": ["make-ahead", "high-fiber", "low-gi"],
        "ingredients": [
            {"name": "Chia seeds", "amount": "30g"},
            {"name": "Coconut milk", "amount": "200ml"},
            {"name": "Vanilla extract", "amount": "1/2 tsp"},
            {"name": "Fresh berries", "amount": "80g"},
            {"name": "Coconut flakes", "amount": "1 tbsp"}
        ],
        "steps": ["Mix chia, coconut milk, vanilla. Refrigerate overnight.", "Top with berries and coconut."],
        "source": "Curated", "calories": 260, "protein_g": 6, "carbs_g": 14, "fat_g": 20, "fiber_g": 12, "sugar_g": 5
    },
    {
        "id": "eu-b-015", "name": "Avocado & Black Bean Toast",
        "image": "https://www.themealdb.com/images/media/meals/1550441882.jpg",
        "meal_type": "breakfast", "goals": ["diabetes", "vegan", "maintain"],
        "minutes": 8, "servings": 1,
        "tags": ["high-fiber", "plant-protein"],
        "ingredients": [
            {"name": "Sourdough bread", "amount": "2 slices"},
            {"name": "Avocado", "amount": "1/2"},
            {"name": "Black beans (canned)", "amount": "80g"},
            {"name": "Lime juice", "amount": "1 tsp"},
            {"name": "Chilli flakes", "amount": "pinch"},
            {"name": "Cherry tomatoes", "amount": "4"}
        ],
        "steps": ["Toast bread.", "Mash avocado with lime, salt.", "Warm and lightly mash beans.", "Spread on toast, top with tomatoes and chilli."],
        "source": "Curated", "calories": 340, "protein_g": 12, "carbs_g": 36, "fat_g": 16, "fiber_g": 12, "sugar_g": 4
    },

    # More lunch
    {
        "id": "eu-l-017", "name": "Norwegian Open-Faced Shrimp Sandwich",
        "image": "https://www.themealdb.com/images/media/meals/1550441882.jpg",
        "meal_type": "lunch", "goals": ["diabetes", "maintain"],
        "minutes": 10, "servings": 1,
        "tags": ["scandinavian", "seafood", "light"],
        "ingredients": [
            {"name": "Rye bread", "amount": "2 slices"},
            {"name": "Cooked shrimp", "amount": "100g"},
            {"name": "Mayonnaise (light)", "amount": "1 tbsp"},
            {"name": "Lemon juice", "amount": "1 tsp"},
            {"name": "Dill", "amount": "fresh sprigs"},
            {"name": "Hard-boiled egg", "amount": "1"},
            {"name": "Lettuce", "amount": "few leaves"}
        ],
        "steps": ["Place lettuce on bread.", "Mix mayo with lemon.", "Pile shrimp on top.", "Garnish with egg slices and dill."],
        "source": "Curated", "calories": 310, "protein_g": 24, "carbs_g": 26, "fat_g": 12, "fiber_g": 4, "sugar_g": 3
    },
    {
        "id": "eu-l-018", "name": "Italian Bean & Tuna Salad",
        "image": "https://www.themealdb.com/images/media/meals/yypvst1511304979.jpg",
        "meal_type": "lunch", "goals": ["diabetes", "weight_loss", "maintain"],
        "minutes": 8, "servings": 2,
        "tags": ["italian", "quick", "high-protein"],
        "ingredients": [
            {"name": "Canned tuna (in olive oil)", "amount": "160g"},
            {"name": "Cannellini beans", "amount": "200g"},
            {"name": "Red onion", "amount": "1/4"},
            {"name": "Cherry tomatoes", "amount": "100g"},
            {"name": "Fresh parsley", "amount": "handful"},
            {"name": "Lemon juice", "amount": "2 tbsp"},
            {"name": "Extra virgin olive oil", "amount": "1 tbsp"}
        ],
        "steps": ["Drain beans, halve tomatoes, slice onion thinly.", "Flake tuna.", "Toss all with lemon juice, oil, parsley.", "Season and serve."],
        "source": "Curated", "calories": 290, "protein_g": 26, "carbs_g": 20, "fat_g": 12, "fiber_g": 7, "sugar_g": 3
    },

    # More dinner
    {
        "id": "eu-d-026", "name": "Pork Schnitzel with Lemon & Capers",
        "image": "https://www.themealdb.com/images/media/meals/1525876468.jpg",
        "meal_type": "dinner", "goals": ["maintain", "muscle"],
        "minutes": 20, "servings": 2,
        "tags": ["austrian", "classic", "crispy"],
        "ingredients": [
            {"name": "Pork loin (thin cutlets)", "amount": "2 × 150g"},
            {"name": "Wholemeal breadcrumbs", "amount": "60g"},
            {"name": "Egg", "amount": "1"},
            {"name": "Flour", "amount": "30g"},
            {"name": "Butter", "amount": "30g"},
            {"name": "Lemon wedges", "amount": "2"},
            {"name": "Capers", "amount": "1 tbsp"},
            {"name": "Mixed salad", "amount": "100g"}
        ],
        "steps": ["Pound pork thin. Coat in flour, egg, breadcrumbs.", "Fry in butter 3 min per side until golden.", "Serve with lemon, capers, and salad."],
        "source": "Curated", "calories": 420, "protein_g": 38, "carbs_g": 22, "fat_g": 20, "fiber_g": 3, "sugar_g": 2
    },
    {
        "id": "eu-d-027", "name": "Greek Baked Fish with Tomatoes & Herbs",
        "image": "https://www.themealdb.com/images/media/meals/vuxgtm1764112923.jpg",
        "meal_type": "dinner", "goals": ["diabetes", "weight_loss", "maintain"],
        "minutes": 35, "servings": 4,
        "tags": ["greek", "one-pan", "low-calorie"],
        "ingredients": [
            {"name": "White fish fillets", "amount": "4 × 150g"},
            {"name": "Canned tomatoes", "amount": "400g"},
            {"name": "Onion, sliced", "amount": "1"},
            {"name": "Garlic", "amount": "3 cloves"},
            {"name": "Olives", "amount": "50g"},
            {"name": "Oregano", "amount": "2 tsp"},
            {"name": "Olive oil", "amount": "2 tbsp"},
            {"name": "Feta", "amount": "60g"},
            {"name": "Fresh parsley", "amount": "handful"}
        ],
        "steps": ["Preheat oven to 190°C.", "Sauté onion and garlic 3 min.", "Add tomatoes, oregano, olives. Simmer 10 min.", "Pour sauce into baking dish, nestle fish in.", "Bake 15 min. Top with feta and parsley."],
        "source": "Curated", "calories": 290, "protein_g": 36, "carbs_g": 10, "fat_g": 12, "fiber_g": 3, "sugar_g": 6
    },
    {
        "id": "eu-d-028", "name": "Aubergine Parmigiana",
        "image": "https://www.themealdb.com/images/media/meals/ctg8jd1585563097.jpg",
        "meal_type": "dinner", "goals": ["diabetes", "maintain"],
        "minutes": 50, "servings": 4,
        "tags": ["italian", "vegetarian", "comfort"],
        "ingredients": [
            {"name": "Aubergines", "amount": "3 large"},
            {"name": "Mozzarella", "amount": "200g"},
            {"name": "Parmesan", "amount": "60g"},
            {"name": "Canned tomatoes", "amount": "400g"},
            {"name": "Garlic", "amount": "2 cloves"},
            {"name": "Fresh basil", "amount": "bunch"},
            {"name": "Olive oil", "amount": "3 tbsp"}
        ],
        "steps": ["Slice aubergines, brush with oil, grill until golden.", "Make sauce: simmer tomatoes, garlic, basil 15 min.", "Layer: sauce, aubergine, mozzarella. Repeat.", "Top with Parmesan.", "Bake at 190°C for 25 min."],
        "source": "Curated", "calories": 310, "protein_g": 18, "carbs_g": 14, "fat_g": 20, "fiber_g": 7, "sugar_g": 8
    },
    {
        "id": "eu-d-029", "name": "Duck Breast with Cherry Sauce",
        "image": "https://www.themealdb.com/images/media/meals/1525876468.jpg",
        "meal_type": "dinner", "goals": ["maintain"],
        "minutes": 30, "servings": 2,
        "tags": ["french", "elegant", "date-night"],
        "ingredients": [
            {"name": "Duck breasts", "amount": "2"},
            {"name": "Cherries (fresh or frozen)", "amount": "150g"},
            {"name": "Red wine", "amount": "100ml"},
            {"name": "Balsamic vinegar", "amount": "1 tbsp"},
            {"name": "Butter", "amount": "15g"},
            {"name": "Thyme", "amount": "2 sprigs"},
            {"name": "Green beans", "amount": "200g"}
        ],
        "steps": ["Score duck skin. Season. Place skin-down in cold pan, cook 8 min.", "Flip, cook 4 min for medium. Rest 5 min.", "In same pan, add cherries, wine, balsamic. Reduce 5 min.", "Stir in butter and thyme.", "Slice duck, serve with cherry sauce and steamed beans."],
        "source": "Curated", "calories": 440, "protein_g": 32, "carbs_g": 16, "fat_g": 26, "fiber_g": 3, "sugar_g": 12
    },
    {
        "id": "eu-d-030", "name": "Zucchini Lasagne (No Pasta)",
        "image": "https://www.themealdb.com/images/media/meals/ctg8jd1585563097.jpg",
        "meal_type": "dinner", "goals": ["diabetes", "keto", "weight_loss"],
        "minutes": 55, "servings": 6,
        "tags": ["italian", "low-carb", "family"],
        "ingredients": [
            {"name": "Zucchini", "amount": "4 large"},
            {"name": "Lean beef mince", "amount": "500g"},
            {"name": "Ricotta", "amount": "250g"},
            {"name": "Mozzarella", "amount": "150g"},
            {"name": "Canned tomatoes", "amount": "400g"},
            {"name": "Garlic", "amount": "3 cloves"},
            {"name": "Italian herbs", "amount": "2 tsp"},
            {"name": "Egg", "amount": "1"},
            {"name": "Spinach", "amount": "100g"}
        ],
        "steps": ["Slice zucchini lengthways, salt and pat dry.", "Brown mince, add garlic, tomatoes, herbs. Simmer 15 min.", "Mix ricotta, egg, spinach.", "Layer: sauce, zucchini, ricotta mix. Repeat 3 times.", "Top with mozzarella. Bake 30 min at 180°C."],
        "source": "Curated", "calories": 310, "protein_g": 30, "carbs_g": 10, "fat_g": 16, "fiber_g": 3, "sugar_g": 6
    },

    # More snacks
    {
        "id": "eu-s-011", "name": "Greek Yogurt Dip with Seeds",
        "image": "https://www.themealdb.com/images/media/meals/vlrppq1764113063.jpg",
        "meal_type": "snack", "goals": ["diabetes", "maintain"],
        "minutes": 3, "servings": 2,
        "tags": ["quick", "high-protein", "probiotic"],
        "ingredients": [
            {"name": "Greek yogurt", "amount": "200g"},
            {"name": "Pumpkin seeds", "amount": "20g"},
            {"name": "Sunflower seeds", "amount": "10g"},
            {"name": "Honey", "amount": "1 tsp"},
            {"name": "Cinnamon", "amount": "pinch"}
        ],
        "steps": ["Spoon yogurt into bowls.", "Top with seeds, honey, cinnamon."],
        "source": "Curated", "calories": 180, "protein_g": 14, "carbs_g": 10, "fat_g": 10, "fiber_g": 2, "sugar_g": 7
    },
    {
        "id": "eu-s-012", "name": "Celery with Peanut Butter & Raisins",
        "image": "https://www.themealdb.com/images/media/meals/vlrppq1764113063.jpg",
        "meal_type": "snack", "goals": ["maintain"],
        "minutes": 3, "servings": 1,
        "tags": ["quick", "classic", "kids-friendly"],
        "ingredients": [
            {"name": "Celery stalks", "amount": "3"},
            {"name": "Peanut butter", "amount": "2 tbsp"},
            {"name": "Raisins", "amount": "1 tbsp"}
        ],
        "steps": ["Wash and trim celery.", "Fill grooves with peanut butter.", "Top with raisins."],
        "source": "Curated", "calories": 210, "protein_g": 7, "carbs_g": 14, "fat_g": 15, "fiber_g": 3, "sugar_g": 10
    },
    {
        "id": "eu-s-013", "name": "Baked Kale Chips",
        "image": "https://www.themealdb.com/images/media/meals/vlrppq1764113063.jpg",
        "meal_type": "snack", "goals": ["diabetes", "vegan", "keto", "weight_loss"],
        "minutes": 15, "servings": 2,
        "tags": ["crispy", "low-calorie", "superfood"],
        "ingredients": [
            {"name": "Kale, stems removed", "amount": "200g"},
            {"name": "Olive oil", "amount": "1 tbsp"},
            {"name": "Sea salt", "amount": "1/2 tsp"},
            {"name": "Nutritional yeast (optional)", "amount": "1 tbsp"}
        ],
        "steps": ["Preheat oven to 150°C.", "Tear kale into pieces, toss with oil and salt.", "Spread on baking sheet single layer.", "Bake 12-15 min until crispy. Sprinkle yeast."],
        "source": "Curated", "calories": 85, "protein_g": 4, "carbs_g": 6, "fat_g": 6, "fiber_g": 3, "sugar_g": 1
    },

    # More desserts
    {
        "id": "eu-ds-008", "name": "Lemon Posset (Sugar-Free)",
        "image": "https://www.themealdb.com/images/media/meals/adxcbq1619787919.jpg",
        "meal_type": "dessert", "goals": ["diabetes", "keto"],
        "minutes": 10, "servings": 4,
        "tags": ["british", "elegant", "no-bake"],
        "ingredients": [
            {"name": "Heavy cream", "amount": "400ml"},
            {"name": "Lemon juice", "amount": "60ml"},
            {"name": "Lemon zest", "amount": "2 lemons"},
            {"name": "Erythritol", "amount": "3 tbsp"},
            {"name": "Fresh berries (to serve)", "amount": "80g"}
        ],
        "steps": ["Heat cream with sweetener until simmering.", "Remove from heat, whisk in lemon juice and zest.", "Pour into glasses, chill at least 3 hours.", "Serve with fresh berries."],
        "source": "Curated", "calories": 250, "protein_g": 2, "carbs_g": 4, "fat_g": 26, "fiber_g": 0, "sugar_g": 2
    },
    {
        "id": "eu-ds-009", "name": "Frozen Yogurt Bark",
        "image": "https://www.themealdb.com/images/media/meals/m2bnlm1764436938.jpg",
        "meal_type": "dessert", "goals": ["diabetes", "maintain"],
        "minutes": 5, "servings": 6,
        "tags": ["frozen", "kids-friendly", "make-ahead"],
        "ingredients": [
            {"name": "Greek yogurt", "amount": "400g"},
            {"name": "Mixed berries", "amount": "100g"},
            {"name": "Dark chocolate chips", "amount": "20g"},
            {"name": "Pistachios, chopped", "amount": "20g"},
            {"name": "Honey", "amount": "1 tbsp"}
        ],
        "steps": ["Spread yogurt on a parchment-lined tray.", "Scatter berries, chocolate, pistachios.", "Drizzle honey.", "Freeze 3+ hours. Break into pieces."],
        "source": "Curated", "calories": 110, "protein_g": 7, "carbs_g": 10, "fat_g": 5, "fiber_g": 1, "sugar_g": 7
    },
]

recipes.extend(extra)

with open(base_path, 'w') as f:
    json.dump(recipes, f, indent=2, ensure_ascii=False)

print(f"Total recipes: {len(recipes)}")
by_type = {}
for r in recipes:
    t = r['meal_type']
    by_type[t] = by_type.get(t, 0) + 1
print(f"By type: {by_type}")
dia_count = sum(1 for r in recipes if 'diabetes' in r.get('goals', []))
print(f"Diabetes-tagged: {dia_count}/{len(recipes)}")
