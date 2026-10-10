import json
import pathlib
import collections

recipes = json.loads(pathlib.Path('assets/bundled_recipes.json').read_text())

BREAKFAST_ANCHORS = []  # not needed for rough simulation


def cps(r):
    serv = r.get('servings') or 1
    if serv <= 0:
        serv = 1
    return round((r.get('calories') or 0) / serv)


def weighed(r):
    return sum(1 for i in (r.get('ingredients') or []) if (i.get('grams') or 0) > 0)


def quality(r):
    serv = r.get('servings') or 0
    if weighed(r) < 3:
        return False, 'ingredients<3'
    if not (r.get('steps') or []):
        return False, 'no steps'
    if not (r.get('image') or '').strip():
        return False, 'no image'
    if serv <= 0 or serv > 12:
        return False, 'servings'
    c = cps(r)
    if c < 120 or c > 1200:
        return False, 'cal global'
    mt = (r.get('meal_type') or '').lower()
    if mt == 'breakfast':
        ok = 180 <= c <= 900
    elif mt == 'lunch':
        ok = 250 <= c <= 950
    elif mt == 'snack':
        ok = 120 <= c <= 550
    elif mt == 'dinner':
        ok = 250 <= c <= 1200
    elif mt == 'dessert':
        ok = 120 <= c <= 900
    else:
        ok = False
    return (ok, 'cal meal' if not ok else 'ok')


counts = collections.Counter((r.get('meal_type') or '').lower() for r in recipes)
print('meal_type distribution:', dict(counts))
print()

for mt in ('breakfast', 'lunch'):
    rows = [r for r in recipes if (r.get('meal_type') or '').lower() == mt]
    passing = [r for r in rows if quality(r)[0]]
    fails = collections.Counter(quality(r)[1] for r in rows if not quality(r)[0])
    langs = collections.Counter((r.get('language') or '').lower() for r in passing)
    print(f'{mt}: total={len(rows)} pass_quality={len(passing)}')
    print(f'  fail reasons: {dict(fails)}')
    print(f'  passing by language: {dict(langs)}')
    print()
