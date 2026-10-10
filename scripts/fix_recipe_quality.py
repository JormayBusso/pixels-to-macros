#!/usr/bin/env python3
"""
Fix all 3000+ recipes in recipes.json:
1. Remove out-of-place savory ingredients from sweet/dessert recipes
2. Remove random tiny ingredients (<=2g) that don't belong 
3. Convert egg whites/yolks to whole eggs with descriptive amounts
4. Add salt & pepper to savory recipes
5. Add appropriate spices/seasonings to protein-based recipes
6. Fix stevia amounts (0g -> remove, 1g -> keep as pinch)
"""

import json
import copy
import re

INPUT  = '/Users/jormaybusso/pixels-to-macros/assets/recipes.json'
OUTPUT = '/Users/jormaybusso/pixels-to-macros/assets/recipes.json'
BACKUP = '/Users/jormaybusso/pixels-to-macros/assets/recipes_backup_prefixed.json'

with open(INPUT) as f:
    recipes = json.load(f)

print('Loaded', len(recipes), 'recipes')

# ── Categorize recipes ────────────────────────────────────────────────────────

SWEET_KEYWORDS = [
    'cake', 'pudding', 'parfait', 'brownie', 'cookie', 'muffin', 'smoothie',
    'ice cream', 'pancake', 'waffle', 'granola', 'oatmeal', 'mousse', 'dessert',
    'berry', 'chocolate', 'banana bread', 'cheesecake', 'protein shake',
    'chia pudding', 'overnight oats', 'protein bar', 'energy ball', 'yogurt bowl',
    'protein pudding', 'detox smoothie', 'power bowl', 'acai',
]

SAVORY_OUT_OF_PLACE = {
    'garlic', 'onion', 'cumin', 'paprika', 'turmeric', 'chili powder',
    'soy sauce', 'worcestershire', 'cayenne', 'garam masala',
}

# Savory recipe indicators
SAVORY_KEYWORDS = [
    'chicken', 'beef', 'salmon', 'tuna', 'pork', 'turkey', 'lamb', 'fish',
    'shrimp', 'steak', 'burger', 'stir-fry', 'stir fry', 'curry', 'soup',
    'salad', 'wrap', 'bowl', 'rice', 'pasta', 'noodle', 'tofu', 'tempeh',
    'quinoa', 'lentil', 'chili', 'stew', 'casserole', 'roast', 'grilled',
    'baked', 'sauteed', 'scramble', 'omelette', 'frittata', 'sandwich',
    'burrito', 'taco', 'fajita', 'gyro', 'kebab', 'meatball', 'pizza',
    'lasagna', 'risotto',
]

def is_sweet(name):
    nl = name.lower()
    return any(kw in nl for kw in SWEET_KEYWORDS)

def is_savory(name):
    nl = name.lower()
    return any(kw in nl for kw in SAVORY_KEYWORDS)

def needs_salt_pepper(recipe):
    """Most cooked savory dishes need salt and pepper."""
    nl = recipe['name'].lower()
    if is_sweet(nl):
        return False
    mt = recipe.get('meal_type', '')
    if mt == 'snack':
        return False
    # Only add to savory dishes
    return is_savory(nl) or mt in ('lunch', 'dinner')

# ── Protein-specific spice mappings ───────────────────────────────────────────

PROTEIN_SPICES = {
    'chicken': {'name': 'chicken seasoning', 'grams': 3, 'amount': '1 tsp'},
    'turkey': {'name': 'poultry seasoning', 'grams': 3, 'amount': '1 tsp'},
    'salmon': {'name': 'dill & lemon seasoning', 'grams': 2, 'amount': '1/2 tsp'},
    'tuna': {'name': 'fish seasoning', 'grams': 2, 'amount': '1/2 tsp'},
    'fish': {'name': 'fish seasoning', 'grams': 2, 'amount': '1/2 tsp'},
    'shrimp': {'name': 'seafood seasoning', 'grams': 2, 'amount': '1/2 tsp'},
    'beef': {'name': 'steak seasoning', 'grams': 3, 'amount': '1 tsp'},
    'steak': {'name': 'steak seasoning', 'grams': 3, 'amount': '1 tsp'},
    'pork': {'name': 'pork seasoning', 'grams': 3, 'amount': '1 tsp'},
    'lamb': {'name': 'lamb seasoning', 'grams': 3, 'amount': '1 tsp'},
    'tofu': {'name': 'garlic powder', 'grams': 2, 'amount': '1/2 tsp'},
    'tempeh': {'name': 'smoked paprika', 'grams': 2, 'amount': '1/2 tsp'},
}

# ── Egg conversion ────────────────────────────────────────────────────────────

def convert_egg_parts(ingredients):
    """Convert egg whites/yolks to whole eggs with human-readable amounts."""
    new_ingredients = []
    egg_whites_g = 0
    egg_yolks_g = 0
    has_whole_eggs = False

    for ing in ingredients:
        name_lower = ing['name'].lower().strip()
        if 'egg white' in name_lower:
            egg_whites_g += ing['grams']
        elif 'egg yolk' in name_lower:
            egg_yolks_g += ing['grams']
        elif name_lower in ('eggs', 'egg', 'whole eggs', 'large eggs', 'large egg'):
            has_whole_eggs = True
            new_ingredients.append(ing)
        else:
            new_ingredients.append(ing)

    # Convert: ~33g per egg white, ~18g per yolk, ~50g per whole egg
    if egg_whites_g > 0:
        num_whites = max(1, round(egg_whites_g / 33))
        new_ingredients.append({
            'name': 'eggs',
            'grams': num_whites * 50,  # whole egg equivalent
            'amount': str(num_whites) + (' egg' if num_whites == 1 else ' eggs') + ' (use whites only, ~' + str(egg_whites_g) + 'g)'
        })

    if egg_yolks_g > 0:
        num_yolks = max(1, round(egg_yolks_g / 18))
        if not has_whole_eggs and egg_whites_g == 0:
            new_ingredients.append({
                'name': 'eggs',
                'grams': num_yolks * 50,
                'amount': str(num_yolks) + (' egg' if num_yolks == 1 else ' eggs') + ' (use yolks only, ~' + str(egg_yolks_g) + 'g)'
            })
        elif not has_whole_eggs:
            # Already added eggs for whites above, just note yolks in description
            pass

    return new_ingredients

# ── Main fix loop ─────────────────────────────────────────────────────────────

stats = {
    'removed_misplaced': 0,
    'removed_tiny': 0,
    'converted_eggs': 0,
    'added_salt_pepper': 0,
    'added_spice': 0,
    'removed_0g_stevia': 0,
}

for recipe in recipes:
    name = recipe['name']
    ingredients = recipe.get('ingredients', [])
    name_lower = name.lower()

    # 1) Remove out-of-place savory ingredients from sweet recipes
    if is_sweet(name):
        before = len(ingredients)
        ingredients = [
            i for i in ingredients
            if i['name'].lower().strip() not in SAVORY_OUT_OF_PLACE
        ]
        stats['removed_misplaced'] += before - len(ingredients)

    # 2) Remove 0g ingredients
    before = len(ingredients)
    ingredients = [i for i in ingredients if i.get('grams', 0) > 0]
    stats['removed_0g_stevia'] += before - len(ingredients)

    # 3) Remove random tiny (1g) ingredients that don't make sense
    # Keep spices, stevia, salt, etc but remove random ones like garlic 1g in a dessert
    if is_sweet(name):
        filtered = []
        for i in ingredients:
            n = i['name'].lower().strip()
            if i['grams'] <= 2 and n in SAVORY_OUT_OF_PLACE:
                stats['removed_tiny'] += 1
                continue
            filtered.append(i)
        ingredients = filtered

    # 4) Convert egg whites/yolks to whole eggs
    has_egg_parts = any('egg white' in i['name'].lower() or 'egg yolk' in i['name'].lower() for i in ingredients)
    if has_egg_parts:
        ingredients = convert_egg_parts(ingredients)
        stats['converted_eggs'] += 1

    # 5) Add salt & pepper to savory recipes that don't have them
    ingredient_names = {i['name'].lower().strip() for i in ingredients}
    if needs_salt_pepper(recipe):
        if not any('salt' in n for n in ingredient_names):
            ingredients.append({'name': 'salt', 'grams': 2, 'amount': 'pinch'})
            stats['added_salt_pepper'] += 1
        if not any(n == 'black pepper' or n == 'pepper' for n in ingredient_names):
            ingredients.append({'name': 'black pepper', 'grams': 1, 'amount': 'pinch'})

    # 6) Add protein-specific spices  
    ingredient_names = {i['name'].lower().strip() for i in ingredients}
    has_any_seasoning = any('season' in n or 'spice' in n or 'paprika' in n or 'cumin' in n 
                           for n in ingredient_names)
    if not has_any_seasoning and is_savory(name):
        for protein_key, spice_info in PROTEIN_SPICES.items():
            if protein_key in name_lower:
                # Check if this protein is actually in the ingredients
                if any(protein_key in n for n in ingredient_names):
                    ingredients.append(dict(spice_info))
                    stats['added_spice'] += 1
                    break

    recipe['ingredients'] = ingredients

# ── Save ──────────────────────────────────────────────────────────────────────

# Backup original
with open(BACKUP, 'w') as f:
    json.dump(json.load(open(INPUT)), f)

with open(OUTPUT, 'w') as f:
    json.dump(recipes, f, indent=2, ensure_ascii=False)

print('\n=== Recipe Fix Summary ===')
print('Removed misplaced savory ingredients from sweet recipes:', stats['removed_misplaced'])
print('Removed 0g ingredients:', stats['removed_0g_stevia'])
print('Removed tiny misplaced ingredients:', stats['removed_tiny'])
print('Converted egg whites/yolks to whole eggs:', stats['converted_eggs'])
print('Added salt & pepper to savory recipes:', stats['added_salt_pepper'])
print('Added protein-specific spices:', stats['added_spice'])
print('\nTotal recipes: ' + str(len(recipes)))
print('Saved to', OUTPUT)
