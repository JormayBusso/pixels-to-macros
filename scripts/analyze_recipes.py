#!/usr/bin/env python3
"""Analyze recipe quality issues."""
import json

with open('/Users/jormaybusso/pixels-to-macros/assets/recipes.json') as f:
    data = json.load(f)

# Find recipes with <=2g ingredients (likely random additions)
tiny_count = 0
for r in data:
    tiny = [i for i in r.get('ingredients', []) if i.get('grams', 0) <= 2]
    if tiny:
        tiny_count += 1
        if tiny_count <= 5:
            names = [i['name'] + '(' + str(i['grams']) + 'g)' for i in tiny]
            print(r['name'] + ': ' + str(names))

print('\nTotal recipes with <=2g ingredients: ' + str(tiny_count))

# Check for egg whites with gram amounts
egg_count = 0
for r in data:
    for i in r.get('ingredients', []):
        if 'egg white' in i.get('name', '').lower() or 'egg yolk' in i.get('name', '').lower():
            egg_count += 1
            if egg_count <= 5:
                print(r['name'] + ': ' + i['name'] + ' ' + str(i['grams']) + 'g')

print('\nTotal recipes with egg white/yolk: ' + str(egg_count))

# Check for recipes with salt and pepper
salt_count = sum(1 for r in data if any('salt' in i.get('name','').lower() for i in r.get('ingredients',[])))
pepper_count = sum(1 for r in data if any('pepper' in i.get('name','').lower() and 'bell' not in i.get('name','').lower() for i in r.get('ingredients',[])))
print('\nRecipes with salt: ' + str(salt_count) + '/' + str(len(data)))
print('Recipes with pepper: ' + str(pepper_count) + '/' + str(len(data)))

# Find out-of-place ingredients (garlic in desserts, etc.)
sweet_keywords = ['cake', 'pudding', 'parfait', 'brownie', 'cookie', 'muffin', 'smoothie', 
                  'ice cream', 'pancake', 'waffle', 'granola', 'oatmeal', 'mousse', 'dessert',
                  'berry', 'chocolate', 'banana bread', 'cheesecake']
savory_ingredients = ['garlic', 'onion', 'cumin', 'paprika', 'oregano', 'rosemary', 'thyme',
                      'turmeric', 'chili', 'soy sauce', 'worcestershire']

mismatched = 0
for r in data:
    name_lower = r['name'].lower()
    is_sweet = any(kw in name_lower for kw in sweet_keywords)
    if is_sweet:
        bad = [i['name'] for i in r.get('ingredients', []) if any(s in i['name'].lower() for s in savory_ingredients)]
        if bad:
            mismatched += 1
            if mismatched <= 10:
                print('MISMATCH: ' + r['name'] + ' has ' + str(bad))

print('\nTotal sweet recipes with savory ingredients: ' + str(mismatched))

# Check types of savory recipes missing chicken spices, fish spices etc
chicken_recipes = [r for r in data if 'chicken' in r['name'].lower()]
chicken_with_spice = sum(1 for r in chicken_recipes if any('spice' in i['name'].lower() or 'seasoning' in i['name'].lower() for i in r.get('ingredients', [])))
print('\nChicken recipes: ' + str(len(chicken_recipes)) + ', with spices/seasoning: ' + str(chicken_with_spice))
