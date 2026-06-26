#!/usr/bin/env python3
"""Audit allergen coverage across the bundled multilingual recipe corpus.

For each restriction (gluten / dairy / nut) we keep a multilingual lexicon of
*stems*. We scan every ingredient/name/tag word in the corpus, find which
surface forms actually appear, and report:
  - the exact surface forms present (so we can add them as whole-word triggers)
  - any *suspicious* words a stem would falsely match (false-positive guard)

This lets us build a corpus-verified, false-positive-checked keyword list.
Run:  python3 scripts/audit_allergens.py
"""
import json
import re
from collections import Counter, defaultdict

RECIPES = "assets/bundled_recipes.json"

# Canonical multilingual stems per restriction. A "stem" matches a corpus word
# if the word STARTS with the stem (prefix), which handles inflection
# (Polish/German declensions, plurals). We then manually inspect the matched
# surface forms printed below to ensure none are false positives.
STEMS = {
    "gluten": {
        # en
        "wheat", "barley", "rye", "malt", "spelt", "farro", "bulgur",
        "couscous", "seitan", "gluten", "flour", "pasta", "noodle", "bread",
        "breadcrumb", "cracker", "tortilla", "semolina", "durum", "panko",
        "orzo", "ramen", "udon", "brioche", "croissant", "bagel", "naan",
        "biscuit", "pastry", "pastries", "pancake", "waffle", "muffin",
        "cereal", "einkorn", "kamut", "matzo", "gnocchi", "pretzel",
        "crouton", "dumpling", "pierogi", "wonton", "fusilli", "penne",
        "spaghetti", "macaroni", "lasagn", "tagliatell", "fettuccin",
        "linguin", "vermicell", "baguette", "ciabatta", "focaccia",
        "sourdough", "triticale", "freekeh", "rusk", "farina",
        # nl
        "tarwe", "brood", "beschuit", "paneermeel", "griesmeel", "koekje",
        "koek", "deeg", "pannenkoek", "gerst", "rogge", "krentenbol",
        "stokbrood", "volkoren", "meel", "bloembol",  # check 'meel'/'bloem' fps
        # pl
        "pszen", "mąk", "żyt", "jęczmie", "bułk", "chleb", "makaron",
        "kasz", "grzank", "naleśnik", "pieróg", "pierog", "kluski",
        "owsian", "otręb", "bułka tarta",
        # de
        "weizen", "mehl", "brot", "brötchen", "semmel", "nudeln",
        "teigwaren", "roggen", "dinkel", "grieß", "paniermehl",
        "semmelbrösel", "knödel", "spätzle", "keks", "gebäck", "kuchen",
        "plätzchen", "zwieback", "pumpernickel", "brezel",
        # es
        "trigo", "harina", "cebada", "centeno", "espelta", "fideo",
        "galleta", "sémola", "bizcocho", "magdalena", "empanada",
    },
    "dairy": {
        # en
        "milk", "lactose", "cheese", "yogurt", "yoghurt", "cream", "butter",
        "whey", "casein", "curd", "paneer", "ghee", "mozzarella", "parmesan",
        "parmigiano", "feta", "ricotta", "buttermilk", "cheddar", "gouda",
        "brie", "camembert", "gruyere", "gruyère", "emmental", "edam",
        "halloumi", "manchego", "pecorino", "asiago", "mascarpone",
        "burrata", "provolone", "gorgonzola", "roquefort", "stilton",
        "havarti", "queso", "quark", "kefir", "custard", "gelato",
        "creme fraiche", "crème fraîche", "dulce de leche", "milkshake",
        "bechamel", "béchamel", "clotted cream", "condensed milk",
        "evaporated milk", "milk powder", "dairy", "labneh", "skyr",
        # nl
        "melk", "kaas", "boter", "room", "roomboter", "slagroom",
        "yoghurt", "karnemelk", "kwark", "vla", "geitenkaas", "roomkaas",
        # pl
        "mlek", "mleko", "ser", "sera", "serek", "masł", "śmietan",
        "jogurt", "twaróg", "twarog", "twarożek", "maślank", "kefir",
        # de
        "milch", "käse", "sahne", "butter", "quark", "joghurt", "rahm",
        "frischkäse", "schlagsahne", "buttermilch", "vollmilch",
        "magermilch", "schmand", "molke", "kondensmilch",
        # es
        "leche", "queso", "mantequilla", "nata", "crema", "yogur",
        "requesón", "cuajada", "suero",
    },
    "nut": {
        # en
        "nut", "almond", "walnut", "cashew", "peanut", "hazelnut", "pecan",
        "pistachio", "macadamia", "brazil nut", "pine nut", "tahini",
        "marzipan", "praline", "praliné", "nougat", "nutella", "frangipane",
        "gianduja", "gianduia", "pesto", "satay", "groundnut", "pignoli",
        "filbert", "amaretto", "amaretti", "chestnut", "pinenut",
        # nl
        "noot", "noten", "amandel", "pinda", "walnoot", "hazelnoot",
        "cashewnoot", "arachide", "pistache", "ongebrand",  # check 'ongebrand'
        # pl
        "orzech", "orzesz", "migdał", "nerkowc", "pistacj", "arachidow",
        # de
        "nuss", "nüss", "mandel", "erdnuss", "haselnuss", "walnuss",
        "cashewkern", "pistazie", "marzipan", "haselnuß",
        # es
        "nuez", "nuece", "almendra", "cacahuete", "cacahuate", "maní",
        "avellana", "pistacho", "anacardo",
    },
}

# Stems that are dangerous as prefixes (would match unrelated words). We force
# these to WHOLE-WORD matching.
KNOWN_RISKY = {
    "nut",  # nutmeg, nutrition
    "ser",  # serve, serving, serce(heart)
    "room",  # mushroom, room temperature
    "brot",  # broth
    "meel",
    "bloembol",
    "nata",  # banana? (no) but keep exact
    "rye",
    "vla",
    "rahm",
    "edam",  # 'edamame' would falsely match -> keep whole word
    "brie",  # 'brief'? prefix risky
    "curd",
}


def main():
    with open(RECIPES) as f:
        data = json.load(f)

    # collect corpus words per language
    lang_words = defaultdict(Counter)
    all_text_words = Counter()
    for r in data:
        lang = r.get("language", "?")
        chunks = [r.get("name", "")]
        chunks += r.get("tags", []) or []
        for ing in r.get("ingredients", []) or []:
            chunks.append(ing.get("name", ""))
            chunks.append(ing.get("amount", ""))
        for ch in chunks:
            for w in re.findall(r"[a-zà-ÿłńśźżąęćó]+", (ch or "").lower()):
                lang_words[lang][w] += 1
                all_text_words[w] += 1

    print("Corpus languages:", {k: sum(v.values()) for k, v in lang_words.items()})
    print()

    for restriction, stems in STEMS.items():
        print("=" * 70)
        print(f"RESTRICTION: {restriction}")
        print("=" * 70)
        for stem in sorted(stems):
            if " " in stem:
                continue  # multiword handled via substring at runtime
            whole_only = stem in KNOWN_RISKY
            matched = Counter()
            for w, c in all_text_words.items():
                if whole_only:
                    if w == stem:
                        matched[w] += c
                else:
                    if w.startswith(stem):
                        matched[w] += c
            if not matched:
                continue
            forms = sorted(matched, key=lambda x: -matched[x])
            mode = "WHOLE" if whole_only else "PREFIX"
            print(f"  [{mode}] {stem!r}: {forms[:18]}")
        print()


if __name__ == "__main__":
    main()
