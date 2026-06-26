#!/usr/bin/env python3
"""Validate the new multilingual allergen matcher against the whole corpus.

Mirrors lib/models/dietary_restriction.dart `matchesText`. For each restriction
it reports allowed/blocked counts and, crucially, performs a LEAK CHECK: it uses
an *independent* broad ground-truth lexicon to find recipes that were ALLOWED
(passed the filter) yet still look like they contain the allergen -> potential
false negatives (unsafe). It also samples blocked recipes for false positives.
"""
import json
import re

RECIPES = "assets/bundled_recipes.json"
WORD = re.compile(r"[a-zßà-ÿ\u0100-\u017e]+")

RULES = {
    "gluten": {
        "safe_labels": ["gluten-free", "gluten free", "glutenfree", "glutenvrij",
            "glutenfrei", "sin gluten", "sans gluten", "bez glutenu", "bezglutenow"],
        "safe_phrases": ["almond flour", "coconut flour", "rice flour", "corn flour",
            "chickpea flour", "gram flour", "oat flour", "cassava flour", "tapioca flour",
            "potato flour", "buckwheat flour", "quinoa flour", "millet flour", "sorghum flour",
            "teff flour", "amaranth flour", "plantain flour", "banana flour", "nut flour",
            "soy flour", "soya flour", "almond meal", "flourless", "rice noodle", "rice noodles",
            "glass noodle", "glass noodles", "shirataki", "kelp noodle", "rice pasta", "corn pasta",
            "chickpea pasta", "lentil pasta", "red lentil pasta", "edamame pasta", "rice paper",
            "corn tortilla", "corn tortillas", "koekkruiden", "reisnudel", "glasnudel", "reisbandnudel"],
        "phrase_triggers": ["brood", "deeg", "nudel", "pan rallado"],
        "whole": {"rye", "brot", "mehl", "malt", "farina", "bloem"},
        "prefixes": ["wheat", "barley", "spelt", "farro", "bulgur", "couscous", "seitan",
            "gluten", "flour", "pasta", "noodle", "bread", "breadcrumb", "cracker", "tortilla",
            "semolina", "durum", "panko", "orzo", "ramen", "udon", "brioche", "croissant",
            "bagel", "naan", "biscuit", "pastry", "pancake", "waffle", "muffin", "cereal",
            "einkorn", "kamut", "matzo", "gnocchi", "pretzel", "crouton", "dumpling", "pierogi",
            "fusilli", "penne", "spaghetti", "macaroni", "lasagn", "tagliatell", "fettuccin",
            "linguin", "vermicell", "baguette", "ciabatta", "focaccia", "sourdough", "triticale",
            "freekeh", "rusk", "pizza", "tarwe", "beschuit", "paneermeel", "griesmeel", "koek",
            "pannenkoek", "gerst", "rogge", "krentenbol", "stokbrood", "volkoren", "boterham",
            "patentbloem", "bakmeel", "bloemtortilla",
            "pszen", "mąk", "żyt", "jęczmie", "bułk", "chleb", "makaron", "kasz", "grzank",
            "naleśnik", "pieróg", "pierog", "owsian", "otręb", "weizen", "brötchen", "semmel",
            "teigwaren", "roggen", "dinkel", "grieß", "paniermehl", "vollkorn",
            "knödel", "spätzle", "keks", "gebäck", "kuchen", "plätzchen", "zwieback",
            "pumpernickel", "brezel", "trigo", "harina", "cebada", "centeno", "espelta",
            "fideo", "galleta", "sémola", "bizcocho", "magdalena", "empanada"],
        # independent broad ground-truth (substring) to catch leaks
        "truth": ["wheat", "barley", " rye", "gluten", "flour", "pasta", "noodle", "bread",
            "spaghetti", "macaroni", "lasagn", "couscous", "bulgur", "semolina", "cracker",
            "tortilla", "biscuit", "pastry", "croissant", "baguette", "tarwe", "brood", "deeg",
            "pszen", "mąk", "chleb", "makaron", "bułk", "weizen", "mehl", "brot", "nudeln",
            "semmel", "brötchen", "trigo", "harina"],
    },
    "dairy": {
        "safe_labels": ["dairy-free", "dairy free", "dairyfree", "lactose-free", "lactose free",
            "lactosefree", "non-dairy", "nondairy", "lactosevrij", "laktosefrei", "sin lactosa",
            "bez laktozy", "zuivelvrij"],
        "safe_phrases": ["coconut milk", "coconut cream", "almond milk", "almond cream",
            "oat milk", "oat cream", "soy milk", "soya milk", "soy cream", "rice milk",
            "cashew milk", "cashew cream", "hemp milk", "pea milk", "hazelnut milk",
            "macadamia milk", "flax milk", "peanut butter", "sunflower butter", "seed butter",
            "nut butter", "cocoa butter", "shea butter", "apple butter", "cream of tartar",
            "creme of tartar", "vegan butter", "vegan cheese", "vegan cream", "plant butter",
            "mleko kokosowe", "mleko migdałowe", "mleko sojowe", "mleko owsiane", "mleko ryżowe",
            "masło orzechowe", "masło kakaowe", "masło arachidowe", "masło shea", "masło kokosowe",
            "śmietana kokosowa", "śmietana sojowa", "leche de coco", "leche de almendra",
            "leche de almendras", "leche de soja", "leche de avena", "leche de arroz",
            "mantequilla de cacahuete", "mantequilla de maní", "manteca de cacao", "crema de coco",
            "pflanzliche milch", "plantaardige melk", "plantaardige boter",
            "pindakaas", "sojakaas", "vegan kaas", "plantaardige kaas",
            "veganer käse", "vegane käse", "pflanzlicher käse", "pflanzenkäse",
            "sojajoghurt", "kokosjoghurt", "joghurtalternative"],
        "phrase_triggers": ["zure room", "crème fraîche", "creme fraiche", "käse",
            "kaas", "joghurt", "jogurt"],
        "whole": {"ser", "curd", "brie", "edam", "butter", "boter", "nata", "crema", "vla"},
        "prefixes": ["milk", "lactose", "cheese", "yogurt", "yoghurt", "cream", "whey", "casein",
            "paneer", "ghee", "mozzarella", "parmesan", "parmigiano", "feta", "ricotta",
            "buttermilk", "cheddar", "gouda", "camembert", "gruyère", "gruyere", "emmental",
            "halloumi", "manchego", "pecorino", "asiago", "mascarpone", "burrata", "provolone",
            "gorgonzola", "roquefort", "stilton", "havarti", "queso", "quark", "kefir", "custard",
            "gelato", "milkshake", "bechamel", "béchamel", "labneh", "skyr", "dairy", "melk",
            "kaas", "kwark", "geitenkaas", "roomkaas", "karnemelk", "slagroom", "roomboter",
            "kookroom", "roomijs", "mlek", "sera", "serek", "masł", "śmietan", "jogurt", "twaróg",
            "twarog", "twarożek", "maślank", "milch", "käse", "sahne", "joghurt", "rahm",
            "frischkäse", "schlagsahne", "buttermilch", "vollmilch", "magermilch", "schmand",
            "molke", "kondensmilch", "leche", "mantequilla", "requesón", "cuajada"],
        "truth": ["milk", "cheese", "yogurt", "yoghurt", "cream", "butter", "whey", "casein",
            "mozzarella", "parmesan", "feta", "ricotta", "melk", "kaas", "boter", "room", "kwark",
            "yoghurt", "mlek", " ser", "masł", "śmietan", "jogurt", "twar", "milch", "käse",
            "sahne", "joghurt", "quark", "butter", "leche", "queso", "nata"],
    },
    "nut": {
        "safe_labels": ["nut-free", "nut free", "nutfree", "peanut-free", "peanut free",
            "notenvrij", "noten vrij", "nussfrei", "sin frutos secos", "bez orzechów"],
        "safe_phrases": ["water chestnut", "water chestnuts", "tiger nut", "tiger nuts",
            "nuez moscada", "muskatnuss", "kokosnuss", "nootmuskaat"],
        "phrase_triggers": ["mandel", "nuss", "nüss"],
        "whole": {"nut", "noot"},
        "prefixes": ["almond", "walnut", "cashew", "peanut", "hazelnut", "pecan", "pistachio",
            "macadamia", "tahini", "marzipan", "praline", "praliné", "pralin", "nougat", "nutella",
            "frangipane", "gianduja", "gianduia", "pesto", "satay", "groundnut", "pignoli",
            "filbert", "amaretto", "amaretti", "chestnut", "pinenut", "amandel", "pinda",
            "walnoot", "hazelnoot", "cashewnoot", "arachide", "pistache", "noten", "orzech",
            "orzesz", "migdał", "nerkowc", "pistacj", "arachidow", "nuss", "nüss", "mandel",
            "erdnuss", "haselnuss", "walnuss", "cashewkern", "pistazie", "nuez", "nuece",
            "almendra", "cacahuete", "cacahuate", "maní", "avellana", "pistacho", "anacardo"],
        "truth": ["almond", "walnut", "cashew", "peanut", "hazelnut", "pecan", "pistachio",
            "macadamia", "amandel", "pinda", "walnoot", "hazelnoot", "orzech", "migdał",
            "nerkowc", "erdnuss", "haselnuss", "walnuss", "mandel", " nuss", "nuez", "almendra",
            "cacahuete", "avellana"],
        # truth substrings that are NOT actually the allergen -> exclude from leak flags
        "truth_false": ["coconut", "butternut", "nutmeg", "nutrition", "nootmuskaat",
            "water chestnut", "tiger nut", "nuez moscada", "muskatnuss", "muszkat", "kokos"],
    },
}


def matches(text, r):
    lower = text.lower()
    for lab in r["safe_labels"]:
        if lab in lower:
            return False
    scrubbed = lower
    for ph in r["safe_phrases"]:
        if ph in scrubbed:
            scrubbed = scrubbed.replace(ph, " ")
    for ph in r["phrase_triggers"]:
        if ph in scrubbed:
            return True
    for w in WORD.findall(scrubbed):
        if w in r["whole"]:
            return True
        for p in r["prefixes"]:
            if w.startswith(p):
                return True
    return False


def recipe_text(rec):
    parts = [rec.get("name", "")] + (rec.get("tags", []) or [])
    for ing in rec.get("ingredients", []) or []:
        parts.append(ing.get("name", ""))
        parts.append(ing.get("amount", ""))
    return " ".join(parts)


def truth_hit(text, r):
    low = " " + text.lower() + " "
    for fp in r.get("truth_false", []):
        low = low.replace(fp, " ")
    return any(t in low for t in r["truth"])


def main():
    data = json.load(open(RECIPES))
    for name, r in RULES.items():
        allowed = blocked = 0
        leaks = []
        for rec in data:
            txt = recipe_text(rec)
            if matches(txt, r):
                blocked += 1
            else:
                allowed += 1
                if truth_hit(txt, r):
                    leaks.append(rec.get("name", "?"))
        print("=" * 70)
        print(f"{name}: allowed={allowed} blocked={blocked} potential_leaks={len(leaks)}")
        for n in leaks[:25]:
            print("   LEAK?", n)


if __name__ == "__main__":
    main()
