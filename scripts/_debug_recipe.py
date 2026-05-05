import re, json, sys
sys.path.insert(0, '.')
exec(open('scripts/fix_nutrition.py').read())

with open('assets/recipes.json') as f:
    recipes = json.load(f)

# Debug one high-calorie recipe
for r in recipes:
    if r['name'] == 'Apple Frangipan Tart':
        print('=== Apple Frangipan Tart ===')
        for ing in r['ingredients']:
            name = ing['name']
            amount = ing['amount']
            key = _ingredient_key(name)
            grams = _amount_to_grams(amount, name)
            if key:
                vals = NUTRIENTS[key]
                kcal = vals[0] * grams / 100
                print(f'  {name!r} ({amount!r}) -> {grams:.0f}g [{key}] -> {kcal:.0f} kcal')
            else:
                print(f'  {name!r} ({amount!r}) -> {grams:.0f}g [NOT FOUND]')
        macros = compute_macros(r['ingredients'])
        print(f'  TOTAL: {macros}')
        print(f'  Per serving (x{r["servings"]}): {macros["calories"] // r["servings"]} kcal')
        break

# Show distribution of per-serving calories
per_serving = [(r['name'], r['calories'] // r['servings']) for r in recipes if r['servings'] > 0]
over_2000 = [(n, c) for n, c in per_serving if c > 2000]
print(f'\nRecipes > 2000 kcal/serving: {len(over_2000)}')
for n, c in sorted(over_2000, key=lambda x: -x[1])[:10]:
    print(f'  {n}: {c} kcal/serving')
