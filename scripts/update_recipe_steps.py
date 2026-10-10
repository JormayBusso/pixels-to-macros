#!/usr/bin/env python3
"""Update all recipes in recipes.json with much more detailed preparation steps."""

import json
import re


def generate_detailed_steps(recipe: dict) -> list[str]:
    """Generate detailed cooking steps based on recipe name, ingredients, and meal type."""
    name = recipe["name"].lower()
    ingredients = recipe.get("ingredients", [])
    ing_names = [i["name"].lower() for i in ingredients]
    ing_map = {i["name"].lower(): i for i in ingredients}
    meal_type = recipe.get("meal_type", "")
    minutes = recipe.get("minutes", 20)

    # Helper to get grams
    def g(ingredient_name):
        for i in ingredients:
            if ingredient_name.lower() in i["name"].lower():
                return i["grams"]
        return None

    # ── BREAKFAST ──────────────────────────────────────────────────────────

    if "pancake" in name:
        flour_type = "almond flour" if any("almond" in n for n in ing_names) else "flour"
        flour_g = g(flour_type) or 30
        has_protein = any("protein" in n for n in ing_names)
        return [
            f"In a medium mixing bowl, combine {flour_g}g of {flour_type} with your eggs. Crack the eggs directly into the bowl and whisk vigorously with a fork or whisk until the mixture is completely smooth and free of lumps.",
            "Add the cream cheese (softened to room temperature for easier mixing) and sweetener. Beat the batter for about 30 seconds until everything is fully incorporated and the consistency is smooth and pourable — similar to traditional pancake batter.",
            "Place a non-stick skillet or frying pan over medium heat. Add coconut oil (or butter) and let it melt, tilting the pan to coat the surface evenly. Wait until the oil shimmers slightly — this indicates it's hot enough.",
            "Pour approximately 2–3 tablespoons of batter per pancake into the pan. You should be able to fit 2 small pancakes at a time. Let them cook undisturbed for 2–3 minutes until you see small bubbles forming on the surface and the edges look set.",
            "Carefully flip each pancake with a thin spatula. Cook for another 1–2 minutes on the second side until golden brown. The center should spring back when lightly pressed.",
            "Transfer the cooked pancakes to a warm plate. Repeat with remaining batter if needed. Serve immediately while warm — optionally topped with fresh berries, a drizzle of sugar-free syrup, or a dollop of Greek yogurt."
        ]

    if "omelette" in name:
        veggies = [n for n in ing_names if any(v in n for v in ["spinach", "mushroom", "pepper", "onion", "tomato"])]
        protein = [n for n in ing_names if any(p in n for p in ["egg", "cheese", "bacon", "turkey"])]
        return [
            "Prepare your vegetables first: wash and finely dice all vegetables into small, uniform pieces (roughly 5mm cubes). This ensures they cook evenly and distribute well throughout the omelette. Pat dry any leafy greens like spinach to prevent excess moisture.",
            f"Heat a non-stick frying pan over medium heat. Add a small amount of oil or cooking spray. Once hot, add the diced vegetables and sauté for 2–3 minutes, stirring occasionally, until they soften slightly and release their aroma. Season with a pinch of salt and pepper.",
            "While the vegetables cook, crack the eggs into a bowl. If using egg whites only, separate them carefully. Whisk briskly for 30 seconds until slightly frothy — this incorporates air and makes the omelette lighter and fluffier.",
            "Push the sautéed vegetables to one side of the pan, then pour the whisked eggs evenly across the entire surface. Tilt the pan gently to spread the egg mixture into a thin, even layer. Reduce heat to medium-low.",
            "Let the eggs cook undisturbed for 2–3 minutes. As the edges begin to set, use a spatula to gently lift the edges and tilt the pan so uncooked egg flows underneath. Continue until the surface is mostly set but still slightly glossy.",
            "Sprinkle any cheese over one half of the omelette. Using a spatula, carefully fold the other half over to create a half-moon shape. Cook for another 30 seconds to melt the cheese, then slide onto a warm plate. Garnish with fresh herbs if desired and serve immediately."
        ]

    if "overnight oat" in name:
        has_chia = any("chia" in n for n in ing_names)
        return [
            f"In a clean mason jar or airtight container, add the oats (use old-fashioned rolled oats for the best texture — quick oats become too mushy).{' Add chia seeds and stir to combine with the dry oats.' if has_chia else ''}",
            "Pour in the milk (dairy or plant-based) until the oats are fully submerged. The liquid-to-oat ratio should be approximately 1:1 by volume. Stir well to ensure all oats are moistened and no dry pockets remain at the bottom.",
            "Add any sweetener and flavourings (vanilla extract, cinnamon, honey, or maple syrup) and stir thoroughly. Taste the liquid — it should be slightly sweeter than your preference since the oats will absorb some sweetness overnight.",
            "Seal the container tightly and refrigerate for at least 6 hours, ideally overnight (8–12 hours). The oats will absorb the liquid, soften, and develop a creamy, pudding-like consistency.",
            "In the morning, remove from the fridge and give it a good stir. The mixture should be thick and creamy. If it's too thick, add a splash of milk and stir. If too thin, let it sit for 10 more minutes.",
            "Top generously with fresh berries, sliced nuts, seeds, or any desired toppings. The contrast of cold creamy oats with crunchy toppings is key. Enjoy cold straight from the jar, or microwave for 90 seconds if you prefer warm oats."
        ]

    if "smoothie bowl" in name:
        return [
            "Place all frozen fruits into a high-powered blender. Using frozen fruit (rather than fresh + ice) creates a naturally thick, ice-cream-like consistency that holds toppings without them sinking.",
            "Add the protein powder, yogurt, and just enough liquid (milk or water) to get the blender moving — start with 2–3 tablespoons. The key is using as little liquid as possible to keep the bowl thick and scoopable.",
            "Blend on high for 30–45 seconds, using the tamper to push ingredients toward the blades. Stop and scrape down the sides if needed. The texture should resemble soft-serve ice cream — much thicker than a drinkable smoothie.",
            "Pour the thick smoothie base into a chilled bowl. Use a spoon to smooth the surface and create an even canvas for your toppings.",
            "Arrange your toppings artfully in rows or sections: fresh berries, sliced banana, granola, nuts, seeds, coconut flakes, and a drizzle of nut butter. Eat immediately with a spoon — smoothie bowls don't keep well once assembled."
        ]

    if "smoothie" in name and "bowl" not in name:
        return [
            "Gather all ingredients and add them to a blender in the correct order: liquids first (milk, water, or juice), then soft ingredients (yogurt, banana, nut butter), and frozen items on top. This layering helps the blender process everything smoothly.",
            "If using protein powder, add it after the liquids to prevent clumping. For leafy greens (spinach, kale), tear them into smaller pieces first.",
            "Blend on low speed for 10 seconds to break down the larger pieces, then increase to high speed. Blend for 45–60 seconds until completely smooth with no chunks remaining. Stop and scrape down the sides if needed.",
            "Taste and adjust: add more liquid if too thick, more frozen fruit if too thin, or a touch more sweetener if needed. Blend again briefly to incorporate any additions.",
            "Pour into a tall glass. For the best experience, drink immediately while cold and frothy. If meal-prepping, store in an airtight container in the fridge for up to 24 hours — shake well before drinking."
        ]

    if "scrambl" in name:
        is_tofu = any("tofu" in n for n in ing_names)
        is_tempeh = any("tempeh" in n for n in ing_names)
        is_seitan = any("seitan" in n for n in ing_names)
        protein_source = "tofu" if is_tofu else ("tempeh" if is_tempeh else ("seitan" if is_seitan else "eggs"))
        if protein_source == "tofu":
            return [
                "Drain the tofu and press it firmly between clean kitchen towels or paper towels for at least 5 minutes to remove excess moisture. This is crucial — wet tofu won't crisp up or absorb seasonings properly.",
                "Crumble the pressed tofu into a bowl using your hands, breaking it into irregular, scrambled-egg-sized pieces. Add turmeric (for colour), nutritional yeast (for a cheesy flavour), garlic powder, salt, and pepper. Toss to coat evenly.",
                "Dice all vegetables into small, uniform pieces (about 5mm). Heat olive oil in a large non-stick skillet over medium-high heat until it shimmers.",
                "Add the firmer vegetables first (onion, bell pepper) and sauté for 2–3 minutes until they start to soften. Then add the seasoned tofu crumbles and spread them into a single layer.",
                "Let the tofu cook undisturbed for 2–3 minutes to develop a golden crust on the bottom, then stir. Add any leafy greens (spinach, kale) in the last minute — they wilt quickly.",
                "Taste and adjust seasoning. The scramble should be golden, slightly crispy on some edges, and well-seasoned. Serve hot on a warm plate, optionally with avocado slices, hot sauce, or fresh herbs on top."
            ]
        else:
            return [
                "Crack the eggs into a bowl. Add a pinch of salt and pepper. Whisk vigorously for 30 seconds until the whites and yolks are fully combined and the mixture is slightly frothy with a uniform yellow colour.",
                "Prepare your mix-ins: dice vegetables finely, grate cheese, and chop any herbs. Having everything prepped before you start cooking (mise en place) is essential since scrambled eggs cook quickly.",
                "Heat a non-stick pan over medium-low heat (this is key — low heat produces the creamiest scrambled eggs). Add butter or oil and let it melt, coating the pan surface.",
                "Pour in the egg mixture. Wait 20 seconds until the edges just begin to set, then use a silicone spatula to gently push the eggs from the edges toward the centre in large, slow folds. Do not stir constantly.",
                "Continue folding every 15–20 seconds. Add vegetables and cheese when the eggs are about 75% set — still slightly wet and glossy on top. The residual heat will finish cooking them.",
                "Remove from heat while the eggs still look slightly underdone (they'll continue cooking on the hot plate). The finished scramble should be soft, creamy, and in large, pillowy curds — never dry or rubbery. Serve immediately on a warm plate with avocado and fresh herbs."
            ]

    if "french toast" in name:
        return [
            "In a wide, shallow bowl, whisk together the eggs, milk, vanilla extract, and cinnamon until completely smooth. The custard should be well-combined with no streaks of egg white visible.",
            "If using protein powder, sift it into the custard mixture and whisk until there are no lumps. The batter should coat the back of a spoon evenly.",
            "Slice the bread into thick slices (about 2cm). If using slightly stale bread, even better — it absorbs the custard without falling apart. Fresh bread can be lightly toasted first.",
            "Dip each bread slice into the custard, letting it soak for 15–20 seconds per side. Don't rush this step — the bread needs to absorb the mixture for the best flavour, but don't leave it so long that it becomes soggy and breaks.",
            "Heat a non-stick pan or griddle over medium heat with a thin layer of butter or oil. Once the butter foams and the foam subsides, place the soaked bread slices in the pan.",
            "Cook for 2–3 minutes per side until deep golden brown and slightly crispy on the outside. The interior should be custardy and soft. Serve hot, dusted with a pinch of cinnamon or topped with fresh berries and a light drizzle of maple syrup."
        ]

    if "chia" in name and "pudding" in name:
        return [
            "In a clean jar or bowl, measure out the chia seeds. Use a ratio of approximately 3 tablespoons of chia seeds to 1 cup (240ml) of liquid for the ideal pudding consistency.",
            "Pour in your liquid of choice (coconut milk, almond milk, or dairy milk) and add any sweetener (honey, maple syrup, or stevia). Add vanilla extract or cocoa powder for flavour if desired.",
            "Whisk vigorously for 30 seconds, then let it sit for 2 minutes and whisk again. This second whisk is crucial — it breaks up any clumps that form as the chia seeds begin absorbing liquid.",
            "Cover tightly and refrigerate for at least 4 hours, preferably overnight (8–12 hours). Stir once after the first hour if possible to ensure even consistency throughout.",
            "The finished pudding should have a thick, tapioca-like consistency. Each chia seed will be surrounded by a gel coating. If too thick, stir in a splash of milk; if too thin, add more chia seeds and wait another hour.",
            "Serve cold, layered in a glass with fresh berries, sliced fruit, granola, or nuts on top. The contrast between the creamy pudding and crunchy toppings makes this dish special."
        ]

    if "muffin" in name and "egg" in name.lower():
        return [
            "Preheat your oven to 180°C (350°F). Grease a standard 6-cup muffin tin with cooking spray or line with silicone muffin cups. Standard paper liners work but silicone prevents sticking better.",
            "Prepare all vegetables: wash, dry, and dice bell peppers, onions, and any other vegetables into very small pieces (3–4mm). Finely chop spinach or other leafy greens. Smaller pieces distribute more evenly in the egg cups.",
            "In a large mixing bowl, crack all the eggs and whisk until fully combined. Season with salt, pepper, and any desired herbs (Italian seasoning, paprika, or fresh chives work well). The mixture should be uniform in colour.",
            "Add the diced vegetables to the egg mixture and stir to distribute evenly. The vegetable-to-egg ratio should be about 1:3 by volume for the best structure.",
            "Pour the egg-vegetable mixture evenly into the prepared muffin cups, filling each about ¾ full (they will puff up slightly during baking). Top each with a small pinch of shredded cheese.",
            "Bake for 18–22 minutes until the tops are golden and puffed, and a toothpick inserted in the centre comes out clean. Let cool in the tin for 3 minutes before removing. Serve warm, or store in the fridge for up to 4 days for easy meal prep — reheat in the microwave for 30 seconds."
        ]

    if "parfait" in name or "yogurt" in name.lower() and "bowl" in name.lower():
        return [
            "Start by selecting a tall glass or clear bowl for layering — visual presentation is part of the parfait experience. Have all your toppings measured and ready to layer.",
            "Spoon a generous layer of Greek yogurt (about one-third of your total) into the bottom of the glass. Smooth it out with the back of the spoon to create an even base layer.",
            "Add a layer of fresh berries or sliced fruit on top of the yogurt. If using frozen berries, thaw them first and drain excess liquid so they don't make the parfait watery.",
            "Sprinkle a layer of granola, nuts, or seeds for crunch. If using honey or maple syrup, drizzle a thin stream over this layer. The sweetener will seep down through the layers as it sits.",
            "Repeat the layering process: yogurt, fruit, then granola/nuts. Create 2–3 distinct layers, ending with a decorative fruit and nut topping.",
            "Serve immediately if you prefer crunchy granola, or refrigerate for 30 minutes for a softer, more melded texture. For meal prep, keep granola separate and add just before eating to maintain crunch."
        ]

    if "steak" in name and "egg" in name:
        return [
            "Remove the steak from the refrigerator 30 minutes before cooking to bring it to room temperature. This ensures even cooking throughout. Pat the surface completely dry with paper towels — moisture prevents proper searing.",
            "Season the steak generously on all sides with salt and freshly ground black pepper. Press the seasoning firmly into the meat surface. For extra flavour, add garlic powder or smoked paprika.",
            "Heat a cast-iron skillet or heavy-bottomed pan over high heat for 3–4 minutes until the pan is smoking hot. Add a high-smoke-point oil (avocado oil or refined coconut oil).",
            "Place the steak in the pan and press it down gently with a spatula. Sear for 3–4 minutes without moving it until a deep brown crust forms. Flip once and cook for another 2–3 minutes for medium-rare, or 4 minutes for medium.",
            "Remove the steak to a cutting board and let it rest for 5 minutes (this allows the juices to redistribute). While resting, reduce the heat to medium and crack the eggs into the same pan, using the steak's rendered fat for flavour.",
            "Fry the eggs to your preference: 2–3 minutes for sunny-side up with set whites and runny yolks. Slice the rested steak against the grain into strips and serve alongside the eggs on a warm plate."
        ]

    if "bulletproof" in name or ("keto" in name and "coffee" in name):
        return [
            "Brew a strong cup of high-quality coffee using your preferred method (French press, pour-over, or espresso machine). Use freshly ground beans for the best flavour. The coffee should be hot — at least 85°C — for proper emulsification.",
            "While the coffee is still piping hot, add the grass-fed butter (or ghee) and MCT oil (or coconut oil). The fats must be added to hot coffee for them to emulsify properly rather than floating as a greasy layer.",
            "Pour everything into a blender (or use an immersion blender directly in a deep mug). Blend on high for 15–20 seconds until the mixture is completely frothy and has a creamy, latte-like consistency with no visible oil separation.",
            "Pour into a warm mug. The drink should look like a perfectly frothed cappuccino with a rich, creamy foam on top. Drink immediately while hot and frothy — the emulsion will separate as it cools."
        ]

    if "wrap" in name and ("turkey" in name or "egg" in name):
        return [
            "If using a tortilla or wrap, warm it briefly in a dry pan or microwave for 10 seconds to make it pliable and prevent cracking when rolling. Set aside on a clean work surface.",
            "Cook your protein: for turkey, slice thinly and sear in a hot pan with a drop of oil for 2 minutes per side until just cooked through. For egg whites, whisk and cook as a thin omelette-style sheet in a non-stick pan.",
            "Prepare the fresh fillings: wash and slice any vegetables (lettuce, tomato, avocado, cucumber) into thin strips. Having uniform, thin strips makes the wrap easier to roll tightly.",
            "Lay the warm wrap flat. Spread any sauce or cream cheese in a thin, even layer across the centre, leaving a 3cm border on all sides.",
            "Arrange the protein and vegetables in a line across the centre of the wrap. Don't overfill — less is more when it comes to a tight, holdable wrap.",
            "Fold the bottom edge of the wrap up over the filling, then fold in both sides tightly. Roll firmly away from you, keeping the sides tucked in as you go. Slice diagonally in half and serve immediately, or wrap tightly in foil for a portable meal."
        ]

    if "roll-up" in name:
        return [
            "Lay out the smoked fish slices (salmon, tuna, or shrimp) on a clean cutting board. If the slices are thick, use a sharp knife to cut them into thinner, more pliable pieces that roll easily.",
            "Spread a thin, even layer of cream cheese (about 1 teaspoon per roll-up) onto each slice of fish. Use the back of a spoon or a small offset spatula for an even coat. The cream cheese should be at room temperature for easy spreading.",
            "Add your fresh toppings: thin cucumber matchsticks, capers, fresh dill, thinly sliced red onion, or a squeeze of lemon juice. Distribute evenly across each slice.",
            "Starting from one end, roll each slice up tightly into a neat cylinder. If the rolls won't stay closed, secure each with a small toothpick.",
            "Arrange the roll-ups on a serving plate seam-side down. For the best flavour and presentation, chill in the refrigerator for 15 minutes before serving. Garnish with fresh herbs, a sprinkle of everything bagel seasoning, or a light drizzle of olive oil."
        ]

    if "cottage cheese" in name and ("berry" in name or "bowl" in name or "pineapple" in name):
        return [
            "Scoop the cottage cheese into a bowl. For a smoother texture, you can blend it briefly in a food processor for 15 seconds — this creates a whipped, almost ricotta-like consistency that many people prefer.",
            "If using fresh fruit, wash and prepare it: hull and halve strawberries, separate blueberry clusters, dice pineapple into bite-sized chunks. If using frozen fruit, thaw at room temperature for 10 minutes — partially frozen works well too.",
            "Arrange the fruit on top of the cottage cheese in an appealing pattern. Add any seeds (chia, flax, hemp) and nuts (almonds, walnuts) for crunch and additional nutrition.",
            "Drizzle with honey or maple syrup if desired, and add a pinch of cinnamon or vanilla extract for extra flavour. Serve immediately for the best contrast between the cool, creamy cheese and fresh fruit."
        ]

    # ── LUNCH ──────────────────────────────────────────────────────────────

    if "burrito bowl" in name:
        has_chicken = any("chicken" in n for n in ing_names)
        has_shrimp = any("shrimp" in n for n in ing_names)
        has_ground = any("ground" in n for n in ing_names) or any("beef" in n for n in ing_names)
        protein = "chicken" if has_chicken else ("shrimp" if has_shrimp else "beef")
        return [
            f"Season the {protein} with cumin, chilli powder, smoked paprika, garlic powder, salt, and pepper. Let it marinate for at least 10 minutes at room temperature (or up to 4 hours in the fridge for more flavour).",
            f"Heat a large skillet or grill pan over medium-high heat. Add a thin layer of oil. Cook the {protein} for 3–4 minutes per side until fully cooked through with a nice char on the outside. {'Dice or shred the cooked chicken into bite-sized pieces.' if protein == 'chicken' else 'Break into crumbles as it cooks.' if protein == 'beef' else 'Cook until pink and curled, about 2 minutes per side.'}",
            "While the protein cooks, prepare the rice: rinse under cold water until the water runs clear, then cook according to package directions. Fluff with a fork and stir in a squeeze of fresh lime juice and chopped cilantro.",
            "Prepare the fresh toppings: drain and rinse black beans, dice tomatoes, slice avocado, shred lettuce, and prepare any salsa or guacamole. Having everything ready makes assembly quick.",
            "Assemble the bowl: start with a base of rice, then arrange the protein, black beans, corn, tomatoes, avocado, and any other toppings in sections around the bowl. This makes the bowl visually appealing and allows you to get a bit of everything in each bite.",
            "Finish with a drizzle of lime juice, a dollop of sour cream or Greek yogurt, hot sauce, and fresh cilantro leaves. Serve immediately with a lime wedge on the side."
        ]

    if ("quinoa" in name or "brown rice" in name) and ("bowl" in name or "meal prep" in name):
        grain = "quinoa" if "quinoa" in name else "brown rice"
        protein_name = next((n for n in ing_names if any(p in n for p in ["chicken", "turkey", "tuna", "shrimp", "salmon", "beef", "ground"])), "protein")
        return [
            f"Cook the {grain}: {'rinse quinoa thoroughly under cold water to remove its natural bitter coating (saponins). Combine with water in a 1:2 ratio, bring to a boil, then reduce to a simmer and cover for 15 minutes until all water is absorbed.' if grain == 'quinoa' else 'rinse rice under cold water until clear. Combine with water in a 1:2.5 ratio, bring to a boil, reduce heat to low, cover, and cook for 40–45 minutes until tender.'}  Fluff with a fork and set aside.",
            f"Prepare the {protein_name}: {'season with salt, pepper, and your choice of herbs or spices.' if 'tuna' not in protein_name else 'drain canned tuna and break into chunks, or sear fresh tuna steaks.'} For chicken or turkey, slice into even pieces for consistent cooking.",
            f"Cook the {protein_name} in a hot pan with a small amount of oil. {'Grill or pan-sear for 5–6 minutes per side until the internal temperature reaches 74°C (165°F).' if 'chicken' in protein_name or 'turkey' in protein_name else 'Cook for 3–4 minutes per side until done to your preference.'}",
            "Steam or roast your vegetables: broccoli, asparagus, or whatever vegetables are included. For roasting, toss with a drizzle of olive oil and roast at 200°C for 15 minutes. For steaming, cook for 4–5 minutes until bright green and tender-crisp.",
            f"Assemble the bowl: place a generous portion of {grain} as the base, arrange the cooked protein and vegetables on top. Drizzle with olive oil, a squeeze of lemon, and season to taste.",
            "For meal prep: divide evenly into containers while everything is still warm. Let cool completely uncovered before sealing with lids. Refrigerate and consume within 4 days — reheat in the microwave for 2 minutes, stirring halfway through."
        ]

    if "salad" in name and ("caesar" in name or "chickpea" in name or "mediterranean" in name):
        return [
            "Wash and thoroughly dry all leafy greens using a salad spinner or clean kitchen towels. Wet greens dilute the dressing and make the salad soggy. Tear larger leaves into bite-sized pieces.",
            "Prepare the protein component: for chicken, season and grill or pan-sear until cooked through (74°C internal), then slice thinly against the grain. For chickpeas, drain, rinse, and pat dry — optionally roast at 200°C for 20 minutes for extra crunch.",
            "Prepare all additional toppings: slice cucumbers, halve cherry tomatoes, dice red onion thinly, crumble feta cheese, pit and slice olives. Keep each component separate until assembly.",
            "Make or prepare the dressing: for Caesar, whisk together the ingredients until emulsified. For Mediterranean, combine olive oil, lemon juice, dried oregano, salt, and pepper. Dress the salad just before serving to prevent wilting.",
            "Assemble in a large bowl: start with the greens as a base, then arrange the protein and toppings in sections. Drizzle the dressing over the top or serve on the side.",
            "Toss gently just before eating to coat everything evenly. Serve immediately on a chilled plate for the crispest texture."
        ]

    if "stir-fry" in name or "stir fry" in name:
        protein_name = next((n for n in ing_names if any(p in n for p in ["chicken", "beef", "shrimp", "tofu", "tempeh"])), "protein")
        return [
            "Prep all ingredients before you start cooking — stir-frying happens fast and there's no time to chop mid-cook. Cut all vegetables into thin, uniform pieces. Slice protein into thin strips against the grain for maximum tenderness.",
            f"If using {'tofu or tempeh, press firmly to remove excess moisture and cut into 2cm cubes' if any(v in protein_name for v in ['tofu', 'tempeh']) else 'meat, marinate briefly in soy sauce, garlic, and a pinch of cornstarch for 10 minutes — the starch creates a velvety coating'}.",
            "Heat a wok or large skillet over the highest heat available. Add oil (sesame or vegetable) and swirl to coat. Wait until the oil just begins to smoke — this high heat is what gives stir-fries their characteristic 'wok hei' flavour.",
            f"Add the {protein_name} in a single layer — don't overcrowd the pan or it will steam instead of sear. Cook for 2–3 minutes, flipping once, until golden on the outside. Remove and set aside on a plate.",
            "In the same pan, add a touch more oil. Stir-fry the harder vegetables first (carrots, broccoli stems) for 2 minutes, then add softer ones (bell peppers, snap peas, leafy greens) for another 1–2 minutes. Everything should be vibrant in colour and still have a slight crunch.",
            "Return the protein to the pan. Add the sauce (soy sauce, sesame oil, ginger, garlic) and toss everything together for 30 seconds until the sauce coats all ingredients and begins to glaze. Serve immediately over cauliflower rice or regular rice while piping hot."
        ]

    if "soup" in name:
        return [
            "Prepare your mise en place: dice onions, mince garlic, peel and cube any root vegetables (carrots, potatoes, sweet potatoes) into 2cm pieces. Uniform cuts ensure even cooking. Rinse and drain any canned beans or lentils.",
            "Heat olive oil in a large, heavy-bottomed pot or Dutch oven over medium heat. Add the onions and cook for 3–4 minutes, stirring occasionally, until translucent and softened. Add garlic and cook for 30 seconds until fragrant — don't let it brown.",
            "Add the harder vegetables (carrots, celery, potatoes) and stir to coat with the aromatics. Cook for 2–3 minutes. Season with salt, pepper, and any dried herbs or spices (cumin, paprika, bay leaves).",
            "Pour in the broth or stock. The liquid should cover the vegetables by about 2cm. Bring to a boil over high heat, then immediately reduce to a gentle simmer (small bubbles breaking the surface). Cover partially with a lid.",
            "Simmer for 20–30 minutes until all vegetables are fork-tender. Add any quick-cooking ingredients (leafy greens, cooked lentils, beans) in the last 5 minutes. Taste and adjust seasoning — soups often need more salt than you think.",
            "Ladle into warm bowls. For a creamier soup, use an immersion blender to partially blend (leaving some chunks for texture). Garnish with fresh herbs, a drizzle of olive oil, or a squeeze of lemon juice. Serve with crusty bread or crackers."
        ]

    if "taco" in name:
        return [
            "Prepare the filling: if using beans, drain, rinse, and set aside. For meat filling, season with a taco spice blend (cumin, chilli powder, paprika, garlic powder, onion powder, oregano, salt, and pepper).",
            "Heat oil in a skillet over medium-high heat. Cook the seasoned filling for 5–7 minutes, stirring frequently, until heated through and well-seasoned. Add a splash of water or lime juice to create a saucy consistency.",
            "While the filling cooks, prepare all toppings: shred lettuce, dice tomatoes and onions, slice avocado, chop fresh cilantro, and prepare any salsa, sour cream, or guacamole.",
            "Warm the taco shells or tortillas: for corn tortillas, heat directly over a gas flame for 15 seconds per side, or warm in a dry skillet. For flour tortillas, microwave wrapped in a damp paper towel for 20 seconds.",
            "Assemble each taco: start with a base of filling, then layer on the fresh toppings. Add cheese and any creamy sauces last. Don't overfill — two-thirds full is ideal for a taco you can actually eat without it falling apart.",
            "Serve immediately with lime wedges on the side for squeezing. For best results, squeeze lime juice over each taco just before biting — the acidity brightens all the flavours."
        ]

    if "poke" in name or "poke bowl" in name:
        return [
            "Prepare the sushi rice: rinse rice under cold water 3–4 times until the water runs mostly clear. Cook according to package directions. Once done, gently fold in rice vinegar, a pinch of sugar, and salt while the rice is still warm. Spread on a plate to cool to room temperature.",
            "Prepare the fish: use sushi-grade salmon or tuna. Cut into 2cm cubes with a very sharp knife, using clean, single cuts rather than sawing back and forth. Place the cubed fish in a bowl.",
            "Make the poke marinade: combine soy sauce, sesame oil, rice vinegar, and a touch of sriracha or chilli flakes. Pour over the cubed fish and toss gently to coat. Let it marinate for 5–10 minutes in the refrigerator.",
            "Prepare all toppings: slice avocado, thinly slice cucumber into rounds, shred carrots or red cabbage, prepare edamame, and slice green onions. Have sesame seeds and crispy shallots ready for garnishing.",
            "Assemble the bowl: place a bed of seasoned rice in a wide bowl. Arrange the marinated fish and each topping in neat sections around the bowl. The visual arrangement is important — poke bowls are meant to be beautiful.",
            "Finish with a drizzle of extra marinade, a sprinkle of sesame seeds, and thinly sliced nori or furikake. Serve immediately while the rice is at room temperature and the fish is still cold."
        ]

    if "lettuce wrap" in name:
        return [
            "Prepare the lettuce cups: carefully separate individual leaves from a head of butter lettuce or iceberg lettuce. Choose the largest, most cup-shaped leaves. Wash gently under cold water, pat dry thoroughly, and refrigerate to keep crisp.",
            "Prepare the filling: if using ground turkey or chicken, break it into small crumbles. If using another protein, dice into small bite-sized pieces that will sit easily in the lettuce cups.",
            "Heat oil in a skillet over medium-high heat. Cook the protein, breaking it into small pieces as it browns. Season with soy sauce, garlic, ginger, and sesame oil as it cooks, stirring frequently for 5–7 minutes until fully cooked and well-seasoned.",
            "Add any diced vegetables (water chestnuts, mushrooms, bell peppers) in the last 2 minutes of cooking. They should soften slightly but retain some crunch. Stir in a splash of hoisin sauce or a mixture of soy sauce and honey for a glossy finish.",
            "Remove filling from heat and stir in any fresh herbs (cilantro, mint) and a squeeze of lime juice. The filling should be flavourful enough to eat on its own since the lettuce adds freshness but not much flavour.",
            "To serve, arrange the lettuce cups on a platter and spoon the warm filling into each one. Garnish with sliced green onions, sesame seeds, and chilli flakes. Let everyone assemble their own at the table for the freshest experience."
        ]

    if "stuffed" in name and ("avocado" in name or "tuna" in name):
        return [
            "Cut the avocados in half lengthwise, working around the pit. Twist to separate the halves. Remove the pit by carefully tapping it with the heel of a knife and twisting to release.",
            "Scoop out a small amount of extra avocado from each half to enlarge the well, creating more room for the filling. Place the scooped avocado into a mixing bowl — it'll be mixed into the filling.",
            "Prepare the filling: drain canned tuna thoroughly. Add it to the bowl with the reserved avocado. Mix in diced celery, red onion, lemon juice, Dijon mustard, salt, and pepper. For a creamy version, add a small amount of Greek yogurt instead of mayonnaise.",
            "Spoon the filling generously into each avocado half, mounding it slightly above the rim. Press gently to compact the filling so it stays in place.",
            "Garnish with fresh herbs (dill, chives, or cilantro), a sprinkle of everything bagel seasoning, paprika, or a drizzle of olive oil. For extra crunch, add a few pieces of crumbled crispy bacon or toasted breadcrumbs.",
            "Serve immediately — the avocado will begin to brown once cut. For a neat presentation, place each stuffed half on a small bed of mixed greens. Squeeze lemon juice over the top just before eating."
        ]

    if "pasta" in name:
        return [
            "Bring a large pot of water to a rolling boil. Add salt generously — the water should taste like the sea. This is your only chance to season the pasta itself. Use at least 4 litres of water per 200g of pasta for proper cooking.",
            "Add the pasta and stir immediately to prevent sticking. Cook according to package directions minus 1 minute — you want the pasta al dente (firm to the bite) since it will continue cooking in the sauce.",
            "While the pasta cooks, prepare the sauce: heat olive oil in a large pan, add garlic and sauté for 30 seconds until fragrant. Add your protein (shrimp, chicken, or ground meat) and cook until done.",
            "Before draining the pasta, reserve 1 cup of the starchy cooking water — this liquid gold helps create a silky, cohesive sauce. Drain the pasta and add it directly to the pan with the sauce.",
            "Toss the pasta with the sauce over medium heat for 1–2 minutes, adding splashes of the reserved pasta water to achieve a glossy, coating consistency. The starch in the water helps the sauce cling to each strand.",
            "Remove from heat. Add any fresh herbs (basil, parsley), a final drizzle of olive oil, and freshly ground pepper. Serve immediately in warm bowls — pasta waits for no one."
        ]

    if "zucchini noodle" in name or "zoodle" in name:
        return [
            "Wash the zucchini and trim the ends. Using a spiralizer (preferred) or a julienne peeler, create long, spaghetti-like noodles. If spiralizing, stop when you reach the seedy core — those parts are too watery.",
            "Lay the zucchini noodles on a clean kitchen towel or paper towels. Sprinkle lightly with salt and let them sit for 10 minutes. This draws out excess moisture, which prevents the finished dish from being watery. After 10 minutes, squeeze gently to remove the released liquid.",
            "Prepare your sauce and toppings: cook any protein, chop fresh vegetables, and prepare your sauce. Have everything ready because zucchini noodles cook in under 2 minutes.",
            "Heat olive oil in a large skillet over medium-high heat. Add the zucchini noodles and toss with tongs for 1–2 minutes maximum. The goal is to warm them through, not to fully cook them — overcooked zoodles turn into mush.",
            "Add the sauce and any cooked protein, tossing everything together for 30 seconds. Remove from heat immediately.",
            "Serve in warm bowls, garnished with freshly grated Parmesan (if not vegan), a drizzle of extra virgin olive oil, fresh basil, and red pepper flakes. Eat immediately — zucchini noodles don't hold well and will release water as they sit."
        ]

    # ── DINNER ─────────────────────────────────────────────────────────────

    if "salmon" in name and ("bake" in name or "sweet potato" in name):
        return [
            "Preheat the oven to 200°C (400°F). Line a baking sheet with parchment paper for easy cleanup. Remove the salmon from the refrigerator 15 minutes before cooking to take the chill off.",
            "Prepare the sweet potato: wash, peel (optional), and cut into 2cm cubes or wedges. Toss with olive oil, salt, pepper, and a pinch of smoked paprika. Spread in a single layer on one half of the baking sheet. Place in the oven and roast for 15 minutes to get a head start.",
            "Season the salmon fillet: pat the surface dry with paper towels (essential for crispy skin). Season with salt, pepper, and a squeeze of lemon juice. Optionally brush with a mixture of olive oil, garlic, and fresh dill.",
            "After the sweet potatoes have had their 15-minute head start, place the salmon fillet skin-side down on the other half of the baking sheet. Return to the oven and bake for 12–15 minutes until the salmon flakes easily with a fork and reaches an internal temperature of 62°C (145°F).",
            "The salmon should be slightly translucent in the very centre (it will continue cooking as it rests) and the sweet potatoes should be golden and tender when pierced with a fork. Remove from the oven and let everything rest for 3 minutes.",
            "Plate by placing the roasted sweet potato on one side and the salmon fillet on the other. Garnish with fresh lemon wedges, chopped fresh dill or parsley, and a light drizzle of extra virgin olive oil. Serve immediately."
        ]

    if "salmon" in name and "teriyaki" in name:
        return [
            "Make the teriyaki sauce from scratch: in a small saucepan, combine soy sauce, mirin (or rice vinegar + sugar), honey, minced garlic, and grated fresh ginger. Bring to a simmer over medium heat, stirring until the sugar dissolves. Simmer for 3–4 minutes until slightly thickened. Set half aside for glazing after cooking.",
            "Prepare the salmon: pat the fillets dry with paper towels. Place in a shallow dish and pour the remaining teriyaki sauce over the top. Let it marinate for 15–20 minutes at room temperature, flipping halfway through.",
            "Cook the rice: rinse under cold water until clear. Combine with water (1:1.5 ratio for sushi rice, 1:2 for jasmine) and cook covered over low heat for 15 minutes. Don't lift the lid during cooking. Remove from heat and let it steam for 5 minutes with the lid on, then fluff with a fork.",
            "Heat a non-stick pan or grill pan over medium-high heat. Remove the salmon from the marinade and place skin-side up in the pan. Sear for 3 minutes until a golden crust forms, then flip and cook for another 3 minutes.",
            "In the last minute of cooking, brush the reserved teriyaki sauce generously over the top of the salmon. The sauce will caramelize and create a beautiful glossy glaze.",
            "Plate the rice alongside the glazed salmon. Garnish with sliced green onions, sesame seeds, and a side of steamed vegetables. Drizzle any remaining sauce around the plate."
        ]

    if "steak" in name and "garlic" in name and "butter" in name:
        return [
            "Remove the steak from the refrigerator 30–45 minutes before cooking. Pat both sides thoroughly dry with paper towels — surface moisture is the enemy of a good sear. Season generously on all sides with fine sea salt and freshly cracked black pepper.",
            "Make the garlic butter: mash room-temperature butter with finely minced garlic (2–3 cloves), chopped fresh herbs (parsley, thyme, rosemary), and a pinch of flaky sea salt. Roll into a small log using cling film and refrigerate until firm.",
            "Heat a cast-iron skillet over high heat for 4–5 minutes until the pan is smoking hot. Add a high-smoke-point oil (avocado or grapeseed oil) — just enough to coat the bottom in a thin layer.",
            "Place the steak in the pan and do not move it for 3–4 minutes. You should hear an aggressive sizzle. Flip once. For medium-rare (our recommendation), cook until the internal temperature reads 54°C (130°F) — about 3 minutes per side for a 2.5cm thick steak.",
            "In the last minute of cooking, add a thick slice of the prepared garlic butter on top of the steak while it's still in the pan. Tilt the pan and continuously spoon the melting, herbed butter over the steak (basting). This infuses incredible flavour.",
            "Transfer the steak to a cutting board and place another slice of garlic butter on top. Rest for at least 5 minutes — this is non-negotiable. The resting allows the juices to redistribute throughout the meat. Slice against the grain and serve on a warm plate with the melted garlic butter pooling around it."
        ]

    if ("chicken" in name and ("sweet potato" in name or "broccoli" in name)) or ("grilled chicken" in name):
        return [
            "If using chicken breast, butterfly it by slicing horizontally through the thickest part to create an even thickness (about 2cm). This ensures the chicken cooks evenly and doesn't dry out. Season both sides with salt, pepper, paprika, and garlic powder.",
            "Preheat a grill pan, outdoor grill, or oven to 200°C (400°F). If grilling, oil the grates to prevent sticking. If baking, line a baking sheet with parchment paper.",
            "Prepare the vegetables: cut sweet potato into 2cm cubes, break broccoli into uniform florets, and toss each with a drizzle of olive oil, salt, and pepper. If roasting, spread in a single layer on a baking sheet.",
            "Cook the chicken: grill for 5–6 minutes per side, or bake for 22–25 minutes, until the internal temperature reaches 74°C (165°F). The outside should be golden with light grill marks, the inside juicy and white throughout.",
            "Cook the vegetables: roast in the oven for 20–25 minutes until the sweet potato is fork-tender and lightly caramelized, and the broccoli edges are slightly charred. Alternatively, steam the broccoli for 4–5 minutes for a lighter preparation.",
            "Let the chicken rest for 5 minutes before slicing. Plate with the roasted vegetables, a drizzle of extra virgin olive oil, and a squeeze of fresh lemon juice. Optionally add a pinch of red pepper flakes for heat."
        ]

    if "bolognese" in name:
        has_lentil = any("lentil" in n for n in ing_names)
        protein = "lentils" if has_lentil else "ground beef"
        return [
            f"Prepare the base ingredients: finely dice the onion, carrot, and celery into very small pieces (about 3mm — this classic trio is called 'soffritto' and forms the flavour foundation). {'Rinse the lentils under cold water and drain.' if has_lentil else 'Break the ground beef into small pieces.'}",
            "Heat olive oil in a large, deep pan or Dutch oven over medium heat. Add the soffritto and cook for 5–7 minutes, stirring occasionally, until the vegetables are soft, translucent, and just beginning to caramelize at the edges.",
            f"{'Add the lentils to the pan and stir to coat with the aromatics. Cook for 1 minute.' if has_lentil else 'Increase heat to medium-high and add the ground beef. Break it into very small crumbles using a wooden spoon. Cook for 6–8 minutes until well-browned, not just grey — browning develops deep, meaty flavour.'}",
            "Add minced garlic and tomato paste, stirring for 1 minute until the paste darkens and becomes fragrant. Pour in the crushed tomatoes or passata, and add a splash of red wine (or beef broth). Season with dried oregano, basil, salt, pepper, and a pinch of sugar to balance the tomato acidity.",
            "Bring to a gentle simmer, then reduce heat to low. Cover partially and let it simmer for at least 25–30 minutes, stirring occasionally. The longer it simmers, the deeper the flavour develops. The sauce should reduce and thicken naturally.",
            f"Cook your pasta (or zucchini noodles for low-carb) separately. Taste the Bolognese and adjust seasoning — it should be rich, savoury, and slightly sweet. Serve the sauce ladled generously over the pasta, finished with fresh basil leaves and {'nutritional yeast' if has_lentil else 'freshly grated Parmesan cheese'}."
        ]

    if "curry" in name:
        return [
            "Prepare all ingredients before starting: dice onions, mince garlic and ginger (or use grated ginger), drain and rinse chickpeas if canned, and chop any vegetables. Toast your curry spices (cumin, turmeric, garam masala, coriander) in a dry pan for 30 seconds until fragrant — this intensifies their flavour.",
            "Heat coconut oil or vegetable oil in a large, deep pan over medium heat. Add the diced onions and cook for 5–6 minutes until golden and soft. Add the garlic and ginger, stirring constantly for 1 minute — they burn easily.",
            "Add the toasted spice blend and cook for 30 seconds, stirring to coat the onions in the spices. The mixture should be intensely aromatic. Add tomato paste and stir for another 30 seconds.",
            "Pour in the coconut milk (full-fat for richness) and crushed tomatoes. Stir well to combine and bring to a gentle simmer. Add the chickpeas (or other protein) and any harder vegetables. Season with salt.",
            "Simmer uncovered for 20–25 minutes, stirring occasionally, until the sauce thickens and the flavours meld together. Add softer vegetables or spinach in the last 5 minutes. The curry should be rich and creamy with a thick, coating consistency.",
            "Taste and adjust: add more salt, a squeeze of lime juice for brightness, or a pinch of sugar to balance heat. Serve over basmati rice or cauliflower rice. Garnish with fresh cilantro leaves, a swirl of coconut cream, and a sprinkle of red pepper flakes."
        ]

    if "cod" in name or "fish" in name:
        return [
            "Remove the cod fillets from the refrigerator 15 minutes before cooking. Pat completely dry with paper towels on all sides — this is the single most important step for getting a crispy exterior. Season generously with salt and pepper.",
            "If the recipe calls for a herb crust: combine breadcrumbs, finely chopped fresh herbs (parsley, dill, chives), lemon zest, and a drizzle of olive oil. Press this mixture firmly onto the top of each fillet.",
            "For pan-searing: heat oil in a non-stick pan over medium-high heat until it shimmers. Place the fillets presentation-side down and cook without moving for 3–4 minutes until a golden crust forms. Flip carefully and cook for another 2–3 minutes. The fish should flake easily when pressed gently with a fork.",
            "Prepare the vegetables: trim green beans, cut asparagus, or prepare whatever vegetables are included. Steam for 4–5 minutes until bright green and tender-crisp, or roast at 200°C for 12–15 minutes with olive oil and seasoning.",
            "For any sauce: melt butter in the pan, add minced garlic and lemon juice, and let it sizzle for 30 seconds. The browned butter adds a nutty depth that pairs perfectly with white fish.",
            "Plate the fish over or beside the vegetables. Spoon the pan sauce over the top. Garnish with fresh lemon wedges, chopped fresh herbs, and a sprinkle of flaky sea salt. Serve immediately — fish doesn't reheat well."
        ]

    if "pizza" in name:
        return [
            "Make the fathead dough: microwave shredded mozzarella and cream cheese together for 60 seconds, stir, then microwave for another 30 seconds until fully melted and combined into a smooth, stretchy mixture.",
            "Add the almond flour (or coconut flour), egg, and Italian seasoning to the melted cheese mixture. Stir quickly with a fork or spatula until a uniform dough forms. Work quickly — the dough becomes harder to handle as it cools.",
            "Preheat the oven to 220°C (425°F). Place the dough between two sheets of parchment paper and roll it out into your desired pizza shape, about 5mm thick. Remove the top parchment and transfer the dough (on the bottom parchment) to a baking sheet.",
            "Par-bake the crust for 10–12 minutes until the surface is golden and firm to the touch. This step ensures a crispy base that won't get soggy under the toppings.",
            "Remove from the oven and add your toppings: spread a thin layer of sugar-free marinara sauce, add shredded mozzarella, and your choice of toppings (pepperoni, mushrooms, olives, bell peppers). Don't overload — less is more for a crispy keto pizza.",
            "Return to the oven for 8–10 minutes until the cheese is bubbly, melted, and starting to brown in spots. Let it cool for 2–3 minutes (the cheese will firm up slightly), then slice and serve."
        ]

    if "butter chicken" in name:
        return [
            "Cut the chicken into 3cm pieces. In a bowl, combine yogurt, garam masala, turmeric, cumin, chilli powder, minced garlic, grated ginger, salt, and a squeeze of lemon juice. Add the chicken and mix to coat evenly. Marinate for at least 30 minutes (or overnight in the fridge for the best flavour).",
            "Heat ghee or butter in a large, heavy-bottomed pan over medium-high heat. Add the marinated chicken pieces in a single layer (work in batches to avoid overcrowding). Sear for 2–3 minutes per side until golden brown on the outside but not necessarily cooked through — they'll finish in the sauce.",
            "In the same pan, add more butter if needed. Add diced onion and cook for 3–4 minutes until soft. Add garlic and ginger paste, and cook for 1 minute. Add tomato paste and cook for another minute until it darkens.",
            "Pour in the crushed tomatoes, heavy cream (or coconut cream for dairy-free), and spices (garam masala, paprika, a pinch of sugar). Stir well and bring to a gentle simmer.",
            "Return the seared chicken to the sauce. Simmer on low heat for 15–20 minutes, stirring occasionally, until the chicken is cooked through and the sauce has thickened to a rich, creamy, orange-red consistency.",
            "Finish with a knob of cold butter stirred in (this gives it the characteristic silky richness), dried fenugreek leaves (kasuri methi) crushed between your palms, and fresh cilantro. Serve over cauliflower rice for keto, or basmati rice for a traditional presentation."
        ]

    if "meatball" in name:
        return [
            "In a large mixing bowl, combine the ground turkey (or meat of choice) with finely minced onion, garlic, egg, breadcrumbs (or almond flour for low-carb), Italian seasoning, salt, and pepper. Mix gently with your hands until just combined — overworking makes meatballs dense and tough.",
            "Portion the mixture into uniform balls (about 3cm diameter — roughly the size of a golf ball). Roll each one gently between your palms. Place them on a plate or tray. You should get approximately 12–15 meatballs from a standard batch.",
            "Heat olive oil in a large skillet over medium-high heat. Add the meatballs in a single layer, leaving space between each. Sear for 2–3 minutes per side, turning carefully with tongs, until browned on all sides. They don't need to be cooked through — they'll finish in the sauce.",
            "If making a tomato sauce: in the same pan, add crushed tomatoes, garlic, basil, oregano, and a pinch of sugar. Nestle the meatballs into the sauce, cover, and simmer for 15 minutes until they reach an internal temperature of 74°C (165°F).",
            "While the meatballs simmer, prepare the zucchini noodles (or pasta). Spiralize the zucchini and set aside — remember, they only need 1–2 minutes of cooking.",
            "Serve the meatballs and sauce over the zucchini noodles (or pasta). Garnish with fresh basil leaves, a drizzle of extra virgin olive oil, and freshly grated Parmesan cheese. Serve immediately."
        ]

    if "bell pepper" in name and "stuff" in name:
        return [
            "Preheat the oven to 190°C (375°F). Cut the bell peppers in half lengthwise and remove the seeds and white membranes. Place them cut-side up in a baking dish. Brush the insides lightly with olive oil and season with salt and pepper.",
            "Prepare the filling: cook the ground meat (or prepare the grain/bean filling) in a skillet with diced onion, garlic, and spices until fully cooked. Add cooked rice or quinoa, diced tomatoes, and any additional vegetables. Season well and stir to combine.",
            "Spoon the filling generously into each pepper half, pressing down gently to pack it in. The peppers should be heaping full, mounded slightly above the rim.",
            "Cover the baking dish loosely with aluminium foil. Bake for 25 minutes — this steams the peppers and softens them without browning the filling.",
            "Remove the foil, sprinkle shredded cheese on top of each pepper, and return to the oven for another 10–15 minutes until the cheese is melted and bubbly, and the peppers are tender when pierced with a knife but still hold their shape.",
            "Let the stuffed peppers rest for 5 minutes before serving (the filling will be very hot). Garnish with fresh herbs (cilantro, parsley, or chives), a dollop of sour cream, and hot sauce if desired."
        ]

    if "skewer" in name:
        return [
            "If using wooden skewers, soak them in water for at least 30 minutes before grilling to prevent them from burning. Cut the protein and vegetables into uniform 3cm pieces for even cooking.",
            "Prepare a marinade: combine olive oil, lemon juice, garlic, herbs, and spices in a bowl. Add the protein pieces and marinate for at least 20 minutes (up to 2 hours in the fridge). Reserve a small amount of marinade for basting.",
            "Thread the marinated protein and vegetables onto the skewers, alternating between protein and vegetables. Leave a small gap between each piece to allow heat to circulate evenly. Pack 4–5 pieces per skewer.",
            "Preheat your grill or grill pan to medium-high heat. Brush the grates with oil to prevent sticking.",
            "Grill the skewers for 3–4 minutes per side (turning 4 times total for even browning), basting with the reserved marinade during the last few minutes. The protein should be cooked through and the vegetables slightly charred at the edges.",
            "Remove from the grill and let rest for 2 minutes. Serve on a plate over rice or salad. Squeeze fresh lemon over the top and garnish with fresh herbs."
        ]

    if "cauliflower" in name and ("mash" in name or "rice" in name):
        if "mash" in name:
            return [
                "Cut the cauliflower into uniform florets, discarding the thick stem. Wash thoroughly under cold water.",
                "Bring a large pot of salted water to a boil. Add the cauliflower florets and cook for 10–12 minutes until very tender and easily pierced with a fork — they need to be softer than you'd cook them for eating as florets.",
                "Drain the cauliflower extremely well. Excess water is the main cause of watery cauliflower mash. Let it sit in the colander for 5 minutes, then press gently with a clean towel to remove more moisture.",
                "Transfer to a food processor (preferred) or use an immersion blender. Add butter, cream cheese or sour cream, garlic powder, salt, and white pepper. Process until smooth and creamy — about 30 seconds in a food processor.",
                "While the cauliflower is being prepared, cook the chicken thighs: season with salt, pepper, and your choice of herbs. Pan-sear skin-side down for 5 minutes until crispy, then flip and cook for another 6–7 minutes until the internal temperature reaches 74°C.",
                "Serve the chicken over a generous mound of cauliflower mash. Spoon any pan juices over the top. The mash should be silky smooth, almost indistinguishable from mashed potato in texture."
            ]
        else:
            return [
                "Cut the cauliflower into florets and pulse in a food processor in batches until it resembles rice-sized grains. Don't over-process — you want distinct grain-like pieces, not a paste. Alternatively, use the large holes of a box grater.",
                "Heat oil in a large non-stick skillet over medium-high heat. Add the cauliflower rice in an even layer and cook without stirring for 3–4 minutes to get some colour on the bottom.",
                "Stir the cauliflower rice and continue cooking for another 3–4 minutes. Season with salt and pepper. The rice should be tender but still have a slight bite — not mushy.",
                "While the cauliflower rice cooks, prepare the protein and sauce components in a separate pan.",
                "Combine the cauliflower rice with the protein and any vegetables. Toss everything together with the sauce for 30 seconds over high heat.",
                "Serve immediately in warm bowls. Cauliflower rice is best eaten fresh — it doesn't hold well and can become watery if it sits too long."
            ]

    # ── SNACKS ─────────────────────────────────────────────────────────────

    if "protein ball" in name or "energy" in name and "ball" in name or "date ball" in name:
        return [
            "Gather all dry ingredients in a large mixing bowl: oats, protein powder, ground flaxseed, and any other dry components. Stir to combine evenly.",
            "Add the sticky binding ingredients: nut butter (peanut, almond, or cashew), honey or maple syrup, and any liquid flavourings (vanilla extract). Mix thoroughly until a thick, slightly sticky dough forms.",
            "Fold in any add-ins: mini chocolate chips, chopped dried fruit, coconut flakes, or chopped nuts. These should be distributed evenly throughout the dough.",
            "Refrigerate the dough for 15–20 minutes — this makes it firmer and much easier to roll into balls. Cold dough also prevents the balls from becoming sticky and misshapen.",
            "Scoop out approximately 1 tablespoon of dough at a time. Roll firmly between your palms to create compact, smooth balls. Wet your hands slightly with water if the mixture sticks.",
            "Place the finished balls on a parchment-lined tray. Refrigerate for at least 30 minutes to set. Store in an airtight container in the fridge for up to 1 week, or freeze for up to 3 months. Grab 2–3 as a convenient pre- or post-workout snack."
        ]

    if "cheese crisp" in name:
        return [
            "Preheat the oven to 200°C (400°F). Line a baking sheet with parchment paper or a silicone baking mat — this is essential to prevent sticking.",
            "Shred the cheese freshly from a block (pre-shredded cheese contains anti-caking agents that prevent proper crisping). Use hard, aged cheeses like Parmesan, aged cheddar, or Gruyère for the best results.",
            "Place tablespoon-sized mounds of cheese on the prepared baking sheet, spacing them at least 5cm apart as they will spread while baking. Flatten each mound slightly with the back of a spoon.",
            "Bake for 5–7 minutes until the cheese has melted, spread, and turned golden brown around the edges. Watch carefully — they can go from perfect to burnt in under a minute.",
            "Remove from the oven and let cool completely on the baking sheet for 5 minutes. The crisps will be soft when hot but will firm up and become crunchy as they cool. For extra flavour, sprinkle with herbs or spices immediately after removing from the oven while they're still slightly tacky.",
            "Serve as a crunchy snack on their own, or use as a dipper for guacamole. Store in an airtight container at room temperature for up to 3 days."
        ]

    if "fat bomb" in name:
        return [
            "Line a mini muffin tin with small paper liners, or use silicone moulds for easy release. Set aside.",
            "Melt the coconut oil and dark chocolate (or cocoa butter and cocoa powder) together in a microwave-safe bowl — heat in 20-second intervals, stirring between each, until smooth and fully melted.",
            "Stir in the nut butter until completely incorporated. The mixture should be smooth and glossy. Add sweetener (stevia, erythritol, or monk fruit) and a pinch of sea salt. Mix well.",
            "Pour the mixture evenly into the prepared moulds, filling each about ¾ full. Tap the mould gently on the counter to release any air bubbles and level the tops.",
            "If desired, sprinkle the tops with flaky sea salt, crushed nuts, unsweetened coconut flakes, or cacao nibs for texture. Press toppings gently into the surface.",
            "Freeze for at least 1 hour until completely solid. Store in the freezer in an airtight container for up to 2 months. Remove 2–3 minutes before eating to soften slightly — they should be firm but not rock hard. Each fat bomb provides a quick dose of healthy fats to keep you satiated."
        ]

    if "protein shake" in name or "chocolate protein" in name:
        return [
            "Add ice-cold liquid to the blender first: milk (dairy or plant-based), water, or cold brew coffee. Using cold liquid improves the texture and makes the shake more refreshing.",
            "Add the protein powder. If using cocoa powder or powdered supplements, add them now too. Blend on low for 10 seconds to incorporate the powders without creating a dust cloud.",
            "Add any remaining ingredients: banana (fresh or frozen), nut butter, yogurt, or greens. Frozen banana creates a thicker, ice-cream-like consistency without needing as much ice.",
            "Blend on high for 30–45 seconds until completely smooth and frothy. Stop and scrape down the sides if needed. The shake should be thick enough to coat the glass but still easily drinkable through a straw.",
            "Taste and adjust: add more milk if too thick, more frozen fruit or ice if too thin, or a touch more sweetener if needed. Pour into a tall glass and drink immediately for the best texture — protein shakes thicken as they sit."
        ]

    if "banana bread" in name:
        return [
            "Preheat the oven to 175°C (350°F). Grease a standard loaf pan with butter or cooking spray, and line the bottom with parchment paper for easy removal.",
            "In a large bowl, mash the ripe bananas with a fork until mostly smooth (a few small lumps are fine — they add moisture pockets). The bananas should be very ripe with brown spots on the skin for maximum sweetness and moisture.",
            "Add the wet ingredients to the mashed banana: eggs, melted butter (or coconut oil), protein powder, vanilla extract, and sweetener. Whisk until smooth and well combined.",
            "In a separate bowl, combine the dry ingredients: almond flour (or flour of choice), baking soda, baking powder, cinnamon, and a pinch of salt. Whisk to distribute the leavening agents evenly.",
            "Fold the dry ingredients into the wet mixture using a spatula. Mix until just combined — stop as soon as you no longer see dry streaks. Over-mixing develops gluten and makes the bread tough. Fold in any add-ins (chocolate chips, walnuts, seeds).",
            "Pour the batter into the prepared pan, smoothing the top with a spatula. Bake for 45–55 minutes until a toothpick inserted in the centre comes out clean or with just a few moist crumbs. If the top browns too quickly, tent with foil after 30 minutes. Cool in the pan for 10 minutes, then transfer to a wire rack. Slice when completely cool for the cleanest cuts."
        ]

    if "hummus" in name:
        return [
            "Prepare your vegetable dippers: wash and cut carrots, celery, cucumber, and bell peppers into sticks approximately 8cm long and 1cm wide. Arrange them attractively on a serving plate around a central space for the hummus.",
            "If making hummus from scratch: blend chickpeas, tahini, lemon juice, garlic, olive oil, and a splash of cold water in a food processor for 3–4 minutes until very smooth and creamy. Season with salt, cumin, and paprika.",
            "Spoon the hummus into the centre of the plate or into a small serving bowl. Create a well in the centre with the back of a spoon, drizzle with extra virgin olive oil, and sprinkle with paprika and toasted pine nuts.",
            "Serve immediately at room temperature for the creamiest texture. Store leftover hummus in an airtight container in the fridge for up to 5 days. Add a thin layer of olive oil on top before sealing to prevent it from drying out."
        ]

    if "jerky" in name or "trail mix" in name:
        return [
            "Measure out all components separately: turkey jerky pieces, mixed nuts (almonds, cashews, walnuts), dried fruit (if included), and any seeds. Quality matters — choose unsweetened jerky and raw or dry-roasted nuts without added oils.",
            "If the jerky pieces are large, tear or cut them into bite-sized pieces (about 2cm) that are similar in size to the nuts for a consistent eating experience.",
            "Combine all components in a large bowl and toss gently to distribute evenly. The ratio should be approximately equal parts jerky and nuts, with seeds and dried fruit as accents.",
            "Divide into individual portions (about 40–50g each) using small bags or containers. Having pre-portioned snacks prevents overeating and makes them grab-and-go convenient. Store at room temperature in a cool, dry place for up to 2 weeks."
        ]

    # ── DESSERTS ───────────────────────────────────────────────────────────

    if "brownie" in name:
        return [
            "Preheat the oven to 175°C (350°F). Line an 8×8 inch (20×20cm) baking pan with parchment paper, leaving overhang on two sides for easy removal. Lightly grease the parchment.",
            "Melt the dark chocolate and butter (or coconut oil) together using a double boiler or microwave (30-second intervals, stirring between each). The mixture should be smooth, glossy, and fully combined. Let it cool for 5 minutes.",
            "In a separate bowl, whisk together the eggs, sweetener (erythritol, monk fruit, or sugar), and vanilla extract until slightly pale and frothy — about 2 minutes of vigorous whisking. This step adds airiness to the brownies.",
            "Pour the cooled chocolate mixture into the egg mixture and fold gently until combined. Add the almond flour, cocoa powder, and a pinch of salt. Fold until just incorporated — the batter should be thick, glossy, and fudgy. Do not over-mix.",
            "Pour the batter into the prepared pan and smooth the top with a spatula. If desired, sprinkle with chopped nuts, a pinch of flaky sea salt, or extra chocolate chips on top.",
            "Bake for 20–25 minutes until the top is set and slightly cracked, but a toothpick inserted in the centre comes out with moist crumbs attached (not wet batter — that's underdone; not clean — that's overdone). Cool completely in the pan before lifting out using the parchment overhang. Cut into 9 squares with a sharp knife."
        ]

    if "mousse" in name:
        return [
            "Melt the dark chocolate gently using a double boiler: place a heatproof bowl over a pot of barely simmering water (the bowl should not touch the water). Stir occasionally until completely smooth and melted. Alternatively, microwave in 20-second intervals. Remove from heat and let cool to room temperature (about 5 minutes).",
            "While the chocolate cools, whip the cream (coconut cream for dairy-free) in a chilled bowl using an electric mixer or whisk. Beat on medium-high speed until stiff peaks form — when you lift the whisk, the cream should hold its shape without flopping over. Do not over-whip or it will become grainy.",
            "Add the sweetener (stevia, powdered erythritol, or sugar) and vanilla extract to the whipped cream and fold gently to combine.",
            "Take a small scoop of the whipped cream (about ¼) and stir it vigorously into the melted chocolate. This 'sacrificial' scoop lightens the chocolate and makes the final folding much easier without deflating the mousse.",
            "Pour the lightened chocolate mixture over the remaining whipped cream. Using a large spatula, fold gently in a figure-8 motion, rotating the bowl as you go. Fold until no white streaks remain, but stop immediately after — over-folding deflates the mousse.",
            "Divide the mousse into individual glasses or ramekins. Cover with cling film and refrigerate for at least 2 hours (ideally 4 hours or overnight) until set and firm. Serve topped with a dollop of whipped cream, chocolate shavings, or fresh berries."
        ]

    if "mug cake" in name:
        return [
            "In a microwave-safe mug (at least 350ml capacity — the cake rises significantly), add the flour (coconut flour, almond flour, or regular flour). Add baking powder and a pinch of salt. Stir the dry ingredients with a fork to combine.",
            "Add the wet ingredients directly to the mug: egg (or egg white), milk, melted butter (or oil), sweetener, and vanilla extract. Mix thoroughly with a fork until the batter is smooth with no lumps or dry patches at the bottom.",
            "If adding mix-ins (chocolate chips, blueberries, nuts), fold them in gently now. The batter should be thick but pourable — like thick pancake batter. If it's too thick, add a splash of milk.",
            "Microwave on high for 60–90 seconds (timing varies by microwave power). The cake is done when the top is set and springs back when lightly touched. It will look slightly moist on top — this is perfect; it'll firm up as it cools. If the centre is still liquid, add 15 seconds at a time.",
            "Let the mug cake cool for 2 minutes before eating — it will be extremely hot in the centre. Eat directly from the mug, or run a knife around the edge and tip it out onto a plate. Top with a dusting of powdered sweetener, a drizzle of nut butter, or fresh berries."
        ]

    if "ice cream" in name:
        return [
            "Place all ingredients (frozen banana, protein powder, milk, and any flavourings) into a high-powered blender or food processor. Frozen banana is the key to achieving an ice-cream-like consistency without an ice cream maker.",
            "Blend on high, using a tamper to push ingredients toward the blades. Scrape down the sides as needed. The mixture will first look crumbly, then smooth — blend until it reaches the consistency of soft-serve ice cream.",
            "Taste and adjust: add more sweetener, a splash of vanilla, or cocoa powder for chocolate flavour. Blend briefly to incorporate.",
            "For soft-serve consistency, eat immediately. For firmer scoopable ice cream, transfer to a freezer-safe container, press cling film directly onto the surface (prevents ice crystals), and freeze for 2–3 hours.",
            "If frozen solid, let the container sit at room temperature for 10–15 minutes before scooping. Scoop into a bowl and top with chopped nuts, dark chocolate shavings, or fresh berries. Eat within 2 weeks of freezing for the best texture."
        ]

    # ── GENERIC FALLBACK ──────────────────────────────────────────────────

    # Default: produce detailed steps for any recipe not caught above
    has_oven = any(word in name for word in ["bake", "roast", "oven"])
    has_grill = any(word in name for word in ["grill", "bbq", "char"])
    has_blend = any(word in name for word in ["blend", "smoothie", "shake", "pudding"])

    steps = []
    # Step 1: Prep
    ing_list = ", ".join(i["name"] for i in ingredients[:4])
    steps.append(
        f"Prepare all ingredients: wash, measure, and pre-cut everything before you start cooking. "
        f"For this recipe you'll need: {ing_list}{', and more' if len(ingredients) > 4 else ''}. "
        f"Having everything measured and ready (mise en place) makes the cooking process smoother and faster."
    )

    # Step 2: Start cooking
    if has_oven:
        steps.append(
            f"Preheat the oven to {'200°C (400°F)' if 'chicken' in name or 'fish' in name else '180°C (350°F)'}. "
            "Line a baking sheet or dish with parchment paper for easy cleanup. While the oven heats, "
            "season your protein with salt, pepper, and any spices called for in the recipe."
        )
    elif has_grill:
        steps.append(
            "Preheat your grill or grill pan over medium-high heat. While it heats, season the protein "
            "with salt, pepper, and your choice of herbs or marinade. Oil the grill grates to prevent sticking."
        )
    elif has_blend:
        steps.append(
            "Add liquids to the blender first, followed by softer ingredients, and frozen items on top. "
            "This layering ensures smooth blending and prevents air pockets."
        )
    else:
        steps.append(
            "Heat a non-stick skillet or pan over medium heat. Add a small amount of oil and let it "
            "heat until it shimmers. While the pan heats, season your main ingredient with salt and pepper."
        )

    # Step 3: Cook protein
    protein_ing = next((i["name"] for i in ingredients if any(p in i["name"].lower() for p in
        ["chicken", "beef", "salmon", "cod", "shrimp", "turkey", "tofu", "tempeh", "egg"])), None)
    if protein_ing:
        steps.append(
            f"Cook the {protein_ing}: add to the heated pan/oven and cook until golden on the outside "
            f"and fully cooked through. For most proteins, this means {minutes // 2 - 2}–{minutes // 2} minutes "
            f"of cooking time. Use a thermometer if available to ensure food safety (74°C/165°F for poultry, "
            f"62°C/145°F for fish)."
        )

    # Step 4: Cook sides
    veggies = [i["name"] for i in ingredients if any(v in i["name"].lower() for v in
        ["broccoli", "spinach", "pepper", "onion", "tomato", "zucchini", "asparagus", "carrot", "mushroom", "kale", "cauliflower", "sweet potato"])]
    if veggies:
        v_list = ", ".join(veggies[:3])
        steps.append(
            f"Prepare the vegetables ({v_list}): wash and cut into uniform pieces. "
            f"{'Roast in the oven alongside the protein for 15–20 minutes' if has_oven else 'Sauté in the same pan for 3–5 minutes'} "
            f"until tender-crisp and lightly coloured. Season with salt and pepper."
        )

    # Step 5: Combine
    steps.append(
        "Combine all cooked components on a warm plate or in a bowl. Arrange the protein as the "
        "centrepiece with vegetables and any grains or sides around it. A thoughtful presentation "
        "enhances the eating experience."
    )

    # Step 6: Finish
    steps.append(
        f"Finish with a final seasoning check — taste and adjust salt and pepper as needed. "
        f"Garnish with fresh herbs, a drizzle of olive oil or lemon juice, and any final touches. "
        f"Serve immediately while hot. {'This dish stores well for meal prep — refrigerate in airtight containers for up to 4 days.' if minutes > 20 else 'Best enjoyed fresh.'}"
    )

    return steps


def main():
    import os
    recipe_path = os.path.join(os.path.dirname(__file__), "..", "assets", "recipes.json")
    recipe_path = os.path.abspath(recipe_path)

    with open(recipe_path, "r") as f:
        recipes = json.load(f)

    for recipe in recipes:
        new_steps = generate_detailed_steps(recipe)
        if new_steps and len(new_steps) >= len(recipe.get("steps", [])):
            recipe["steps"] = new_steps

    with open(recipe_path, "w") as f:
        json.dump(recipes, f, indent=2, ensure_ascii=False)

    print(f"Updated {len(recipes)} recipes with detailed preparation steps.")
    # Print a few examples
    for r in [recipes[0], recipes[65], recipes[115], recipes[196]]:
        print(f"\n{r['name']}:")
        for i, s in enumerate(r["steps"], 1):
            print(f"  {i}. {s[:100]}...")


if __name__ == "__main__":
    main()
