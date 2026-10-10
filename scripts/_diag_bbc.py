import json
import pathlib

recipes = json.loads(pathlib.Path('assets/bundled_recipes.json').read_text())


def isbbc(r):
    s = (r.get('source') or '').lower()
    u = (r.get('source_url') or '').lower()
    return 'bbc' in s or 'bbc' in u


bbc = [r for r in recipes if isbbc(r)]
print('TOTAL', len(recipes), 'BBC-ish', len(bbc))
for r in bbc:
    ings = r.get('ingredients') or []
    weighed = sum(1 for i in ings if (i.get('grams') or 0) > 0)
    cals = r.get('calories') or 0
    serv = r.get('servings') or 1
    print('---')
    print(' name   ', r.get('name'))
    print(' meal   ', r.get('meal_type'), '| lang', r.get('language'),
          '| source', r.get('source'))
    print(' weighed', weighed, '/', len(ings), '| cal', cals, '| serv', serv,
          '| cal/serv', round(cals / serv, 1) if serv else 'na')
    print(' steps  ', len(r.get('steps') or []), '| image', r.get('image'))
