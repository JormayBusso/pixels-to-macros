#!/usr/bin/env python3
"""Simulate the Flutter recipe_repository visible-count filters over the merged
recipe pool (bundled + real staging + PL staging). Read-only diagnostic."""
import json
import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BREAKFAST_ANCHOR = [
    'breakfast', 'oat', 'porridge', 'granola', 'muesli', 'yogurt', 'yoghurt',
    'smoothie', 'toast', 'egg', 'omelette', 'omelet', 'pancake', 'pancakes',
    'waffle', 'waffles', 'cereal', 'fruit bowl', 'bagel', 'bagels', 'muffin',
    'muffins', 'pastry', 'pastries', 'crepe', 'crepes', 'shakshuka', 'frittata',
    'hash brown', 'brunch', 'ontbijt', 'frühstück', 'fruehstueck', 'śniadanie',
    'sniadanie', 'desayuno', 'bagietka', 'bułka', 'bulka', 'jajecznica',
    'tortilla española',
]
LUNCH_ANCHOR = [
    'salad', 'wrap', 'sandwich', 'bowl', 'soup', 'toast', 'pita', 'flatbread',
    'poke', 'sushi', 'burrito', 'taco', 'tacos', 'quesadilla', 'quiche',
    'frittata', 'mezze', 'lunch', 'brunch', 'mittagessen', 'lunchgerecht',
    'almuerzo', 'obiad', 'wrapy', 'kanapka', 'kanapki',
]
DINNER_LIKE_BREAKFAST = [
    'curry', 'stew', 'roast', 'steak', 'burger', 'pasta', 'noodle', 'risotto',
    'stir fry', 'stir-fry', 'casserole', 'lasagne', 'lasagna', 'ragu', 'ragout',
    'chili',
]
HEAVY_DINNER = [
    'roast', 'braised', 'casserole', 'lasagne', 'lasagna', 'stew', 'ragu',
    'ragout',
]


def contains_any(text, terms):
    probe = text + '\u0000'
    for term in terms:
        esc = re.escape(term.lower())
        if re.search('(^|[^a-z])' + esc + '([^a-z]|\u0000)', probe):
            return True
    return False


def rule_text(r):
    parts = [r.get('name', ''), ' '.join(r.get('tags', []) or [])]
    for ing in r.get('ingredients', []) or []:
        parts.append('%s %s' % (ing.get('name', ''), ing.get('amount', '')))
    return ' '.join(parts).lower()


def cps(r):
    s = r.get('servings') or 1
    return round((r.get('calories') or 0) / s)


def protein_ps(r):
    s = r.get('servings') or 1
    return (r.get('protein_g') or 0) / s


def has_quality(r):
    s = r.get('servings') or 0
    weighed = sum(1 for i in (r.get('ingredients') or []) if (i.get('grams') or 0) > 0)
    if weighed < 3:
        return False
    if not (r.get('steps') or []):
        return False
    img = (r.get('image') or '').strip()
    if not img:
        return False
    if not os.path.exists(os.path.join(ROOT, img)):
        return False
    if s <= 0 or s > 12:
        return False
    c = cps(r)
    if c < 120 or c > 1200:
        return False
    if protein_ps(r) < 2:
        return False
    mt = r.get('meal_type')
    if mt == 'breakfast':
        return 180 <= c <= 900
    if mt == 'lunch':
        return 180 <= c <= 950
    return True


def meal_match(r):
    mt = r.get('meal_type')
    text = rule_text(r)
    if mt == 'breakfast':
        dinner_like = contains_any(text, DINNER_LIKE_BREAKFAST)
        explicit = 'breakfast' in (r.get('name', '').lower())
        if dinner_like and not explicit:
            return False
        if contains_any(text, BREAKFAST_ANCHOR):
            return True
        return not dinner_like
    if mt == 'lunch':
        if cps(r) > 950:
            return False
        if contains_any(text, HEAVY_DINNER) and not contains_any(text, LUNCH_ANCHOR):
            return False
        return True
    return True


def visible(r):
    if r.get('source') == 'generated':
        return False
    if not has_quality(r):
        return False
    if not meal_match(r):
        return False
    return True


def host(r):
    src = r.get('source') or ''
    return src.replace('www.', '')


def main():
    files = [
        'assets/bundled_recipes.json',
        'assets/scraped_staging.json',
        'assets/scraped_staging_pl.json',
    ]
    pool = {}
    for f in files:
        for r in json.load(open(os.path.join(ROOT, f))):
            rid = r.get('id')
            if rid not in pool:
                pool[rid] = r
    recipes = list(pool.values())
    print('total unique pool:', len(recipes))

    for meal in ('breakfast', 'lunch'):
        vis = [r for r in recipes if r.get('meal_type') == meal and visible(r)]
        print('\n== %s visible: %d ==' % (meal, len(vis)))
        by_host = Counter(host(r) for r in vis)
        for h, n in by_host.most_common():
            print('   %-22s %d' % (h, n))


if __name__ == '__main__':
    main()
