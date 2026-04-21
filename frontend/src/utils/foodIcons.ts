// Maps food names / liquid types to emoji icons

const FOOD_ICON_MAP: [RegExp, string][] = [
  // Proteins
  [/chicken|poultry/i,       '🍗'],
  [/beef|steak|burger/i,     '🥩'],
  [/pork|bacon|ham/i,        '🥓'],
  [/fish|salmon|tuna|cod/i,  '🐟'],
  [/shrimp|prawn/i,          '🦐'],
  [/egg/i,                   '🥚'],
  [/tofu|tempeh/i,           '🫘'],
  // Grains
  [/rice/i,                  '🍚'],
  [/pasta|spaghetti|noodle/i,'🍝'],
  [/bread|toast/i,           '🍞'],
  [/pizza/i,                 '🍕'],
  [/oat|porridge/i,          '🥣'],
  [/quinoa|couscous/i,       '🌾'],
  [/potato|fries/i,          '🥔'],
  [/corn|maize/i,            '🌽'],
  // Vegetables
  [/salad|lettuce/i,         '🥗'],
  [/broccoli/i,              '🥦'],
  [/carrot/i,                '🥕'],
  [/tomato/i,                '🍅'],
  [/spinach|kale|greens/i,   '🥬'],
  [/avocado/i,               '🥑'],
  [/pepper/i,                '🌶️'],
  [/mushroom/i,              '🍄'],
  [/cucumber/i,              '🥒'],
  [/pea|bean|lentil/i,       '🫘'],
  // Fruits
  [/apple/i,                 '🍎'],
  [/banana/i,                '🍌'],
  [/orange/i,                '🍊'],
  [/strawberry|berry/i,      '🍓'],
  [/mango/i,                 '🥭'],
  [/grape/i,                 '🍇'],
  [/watermelon/i,            '🍉'],
  [/cherry/i,                '🍒'],
  // Dairy
  [/milk/i,                  '🥛'],
  [/cheese/i,                '🧀'],
  [/yogurt/i,                '🍶'],
  [/butter/i,                '🧈'],
  [/cream/i,                 '🥛'],
  // Sweets / snacks
  [/chocolate|cocoa/i,       '🍫'],
  [/cookie|biscuit/i,        '🍪'],
  [/cake/i,                  '🎂'],
  [/ice.?cream/i,            '🍦'],
  [/nuts|almond|peanut/i,    '🥜'],
  // Soups / stews
  [/soup|stew|curry/i,       '🍲'],
  // Sushi
  [/sushi|roll/i,            '🍱'],
  // Sandwich
  [/sandwich|wrap/i,         '🥪'],
  // Tacos / burrito
  [/taco|burrito/i,          '🌮'],
];

const LIQUID_ICON_MAP: [RegExp, string][] = [
  [/water/i,        '💧'],
  [/coffee/i,       '☕'],
  [/tea/i,          '🍵'],
  [/juice/i,        '🥤'],
  [/milk/i,         '🥛'],
  [/soda|cola|fizz/i, '🥤'],
  [/smoothie/i,     '🥤'],
  [/sports/i,       '🏃'],
  [/wine/i,         '🍷'],
  [/beer/i,         '🍺'],
];

export function getFoodIcon(name: string): string {
  for (const [regex, icon] of FOOD_ICON_MAP) {
    if (regex.test(name)) return icon;
  }
  return '🍽️';
}

export function getLiquidIcon(type: string): string {
  for (const [regex, icon] of LIQUID_ICON_MAP) {
    if (regex.test(type)) return icon;
  }
  return '🥤';
}
