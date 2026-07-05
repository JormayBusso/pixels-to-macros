import 'package:flutter/material.dart';

/// App-wide localised strings.
///
/// Usage: `AppLocalizations.of(context).settings`
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String get _lang => locale.languageCode;

  // ── Helpers ──

  String _t(Map<String, String> map) => map[_lang] ?? map['en']!;

  // ── General ──

  String get appName => 'Pixels to Macros';

  String get ok => _t({
        'en': 'OK',
        'pl': 'OK',
        'nl': 'OK',
        'es': 'OK',
        'de': 'OK',
      });

  String get cancel => _t({
        'en': 'Cancel',
        'pl': 'Anuluj',
        'nl': 'Annuleren',
        'es': 'Cancelar',
        'de': 'Abbrechen',
      });

  String get save => _t({
        'en': 'Save',
        'pl': 'Zapisz',
        'nl': 'Opslaan',
        'es': 'Guardar',
        'de': 'Speichern',
      });

  String get delete => _t({
        'en': 'Delete',
        'pl': 'Usuń',
        'nl': 'Verwijderen',
        'es': 'Eliminar',
        'de': 'Löschen',
      });

  String selectedCount(int count) => _t({
        'en': '$count selected',
        'pl': 'Zaznaczono: $count',
        'nl': '$count geselecteerd',
        'es': '$count seleccionados',
        'de': '$count ausgewählt',
      });

  String deleteSelectedQuestion(int count) => _t({
        'en':
            'Delete $count selected ${count == 1 ? 'item' : 'items'}? This cannot be undone.',
        'pl':
            'Usunąć $count zaznaczonych elementów? Tej operacji nie można cofnąć.',
        'nl':
            '$count geselecteerde ${count == 1 ? 'item' : 'items'} verwijderen? Dit kan niet ongedaan worden gemaakt.',
        'es':
            '¿Eliminar $count ${count == 1 ? 'elemento' : 'elementos'} seleccionados? No se puede deshacer.',
        'de':
            '$count ausgewählte ${count == 1 ? 'Element' : 'Elemente'} löschen? Dies kann nicht rückgängig gemacht werden.',
      });

  String get back => _t({
        'en': 'Back',
        'pl': 'Wstecz',
        'nl': 'Terug',
        'es': 'Atrás',
        'de': 'Zurück',
      });

  String get next => _t({
        'en': 'Next',
        'pl': 'Dalej',
        'nl': 'Volgende',
        'es': 'Siguiente',
        'de': 'Weiter',
      });

  String get done => _t({
        'en': 'Done',
        'pl': 'Gotowe',
        'nl': 'Klaar',
        'es': 'Hecho',
        'de': 'Fertig',
      });

  String get close => _t({
        'en': 'Close',
        'pl': 'Zamknij',
        'nl': 'Sluiten',
        'es': 'Cerrar',
        'de': 'Schließen',
      });

  String get search => _t({
        'en': 'Search',
        'pl': 'Szukaj',
        'nl': 'Zoeken',
        'es': 'Buscar',
        'de': 'Suchen',
      });

  String get add => _t({
        'en': 'Add',
        'pl': 'Dodaj',
        'nl': 'Toevoegen',
        'es': 'Añadir',
        'de': 'Hinzufügen',
      });

  String get refresh => _t({
        'en': 'Refresh',
        'pl': 'Odśwież',
        'nl': 'Vernieuwen',
        'es': 'Actualizar',
        'de': 'Aktualisieren',
      });

  String get loading => _t({
        'en': 'Loading...',
        'pl': 'Ładowanie...',
        'nl': 'Laden...',
        'es': 'Cargando...',
        'de': 'Laden...',
      });

  // ── Navigation / Tabs ──

  String get home => _t({
        'en': 'Home',
        'pl': 'Główna',
        'nl': 'Home',
        'es': 'Inicio',
        'de': 'Home',
      });

  String get settings => _t({
        'en': 'Settings',
        'pl': 'Ustawienia',
        'nl': 'Instelling',
        'es': 'Ajustes',
        'de': 'Einstell.',
      });

  String get aboutSection => _t({
        'en': 'About',
        'pl': 'O aplikacji',
        'nl': 'Over',
        'es': 'Acerca de',
        'de': 'Über',
      });

  String get chooseMascot => _t({
        'en': 'Choose your companion mascot',
        'pl': 'Wybierz swoją maskotkę',
        'nl': 'Kies je begeleidende mascotte',
        'es': 'Elige tu mascota compañera',
        'de': 'Wähle dein Begleit-Maskottchen',
      });

  String get history => _t({
        'en': 'History',
        'pl': 'Historia',
        'nl': 'Geschiedenis',
        'es': 'Historial',
        'de': 'Verlauf',
      });

  String get scan => _t({
        'en': 'Scan',
        'pl': 'Skanuj',
        'nl': 'Scan',
        'es': 'Escanear',
        'de': 'Scannen',
      });

  String get recipes => _t({
        'en': 'Recipes',
        'pl': 'Przepisy',
        'nl': 'Recepten',
        'es': 'Recetas',
        'de': 'Rezepte',
      });

  String get noRecipesMatch => _t({
        'en': 'No recipes match your filters. Try widening your search.',
        'pl': 'Brak przepisów pasujących do filtrów. Poszerz wyszukiwanie.',
        'nl': 'Geen recepten passen bij je filters. Probeer breder te zoeken.',
        'es': 'Ninguna receta coincide con tus filtros. Amplía tu búsqueda.',
        'de': 'Keine Rezepte passen zu deinen Filtern. Suche breiter.',
      });

  String get mealPlanner => _t({
        'en': 'Planner',
        'pl': 'Planer',
        'nl': 'Planner',
        'es': 'Planner',
        'de': 'Planer',
      });

  String get groceryList => _t({
        'en': 'Groceries',
        'pl': 'Zakupy',
        'nl': 'Boodschappen',
        'es': 'Compras',
        'de': 'Einkäufe',
      });

  String get bodyMap => _t({
        'en': 'Body Map',
        'pl': 'Mapa ciała',
        'nl': 'Lichaamskaart',
        'es': 'Mapa corporal',
        'de': 'Körperkarte',
      });

  String get analytics => _t({
        'en': 'Analytics',
        'pl': 'Analityka',
        'nl': 'Analyse',
        'es': 'Análisis',
        'de': 'Analyse',
      });

  String get nutritionDashboard => _t({
        'en': 'Nutrition Dashboard',
        'pl': 'Panel żywienia',
        'nl': 'Voedingsdashboard',
        'es': 'Panel nutricional',
        'de': 'Ernährungs-Dashboard',
      });

  // ── Onboarding ──

  String get welcomeTitle => _t({
        'en': 'Welcome to Pixels to Macros',
        'pl': 'Witaj w Pixels to Macros',
        'nl': 'Welkom bij Pixels to Macros',
        'es': 'Bienvenido a Pixels to Macros',
        'de': 'Willkommen bei Pixels to Macros',
      });

  String get welcomeSubtitle => _t({
        'en': 'Your AI-powered nutrition companion',
        'pl': 'Twój asystent żywienia oparty na AI',
        'nl': 'Jouw AI-aangedreven voedingsassistent',
        'es': 'Tu asistente nutricional con IA',
        'de': 'Dein KI-gestützter Ernährungsassistent',
      });

  String get whatsYourName => _t({
        'en': "What's your name?",
        'pl': 'Jak masz na imię?',
        'nl': 'Wat is je naam?',
        'es': '¿Cómo te llamas?',
        'de': 'Wie heißt du?',
      });

  String get selectGender => _t({
        'en': 'Biological sex',
        'pl': 'Płeć biologiczna',
        'nl': 'Biologisch geslacht',
        'es': 'Sexo biológico',
        'de': 'Biologisches Geschlecht',
      });

  String get male => _t({
        'en': 'Male',
        'pl': 'Mężczyzna',
        'nl': 'Man',
        'es': 'Hombre',
        'de': 'Männlich',
      });

  String get female => _t({
        'en': 'Female',
        'pl': 'Kobieta',
        'nl': 'Vrouw',
        'es': 'Mujer',
        'de': 'Weiblich',
      });

  String get preferNotToSay => _t({
        'en': 'Prefer not to say',
        'pl': 'Wolę nie podawać',
        'nl': 'Zeg ik liever niet',
        'es': 'Prefiero no decirlo',
        'de': 'Keine Angabe',
      });

  String get other => _t({
        'en': 'Other',
        'pl': 'Inne',
        'nl': 'Anders',
        'es': 'Otro',
        'de': 'Andere',
      });

  String get selectGoal => _t({
        'en': 'Select your nutrition goal',
        'pl': 'Wybierz swój cel żywieniowy',
        'nl': 'Kies je voedingsdoel',
        'es': 'Selecciona tu objetivo nutricional',
        'de': 'Wähle dein Ernährungsziel',
      });

  String get weightKg => _t({
        'en': 'Your weight (kg)',
        'pl': 'Twoja waga (kg)',
        'nl': 'Je gewicht (kg)',
        'es': 'Tu peso (kg)',
        'de': 'Dein Gewicht (kg)',
      });

  String get weightEstimateNote => _t({
        'en':
            'Used for a guideline-based starting calorie target. It is still an estimate: body composition, height, age, activity and your progress trend matter.',
        'pl':
            'Używane do wyliczenia orientacyjnego celu kalorycznego. To nadal szacunek: znaczenie mają skład ciała, wzrost, wiek, aktywność i trend postępów.',
        'nl':
            'Gebruikt voor een richtlijngebaseerd startdoel voor calorieën. Het blijft een schatting: lichaamssamenstelling, lengte, leeftijd, activiteit en je voortgangstrend tellen mee.',
        'es':
            'Se usa para un objetivo calórico inicial basado en guías. Sigue siendo una estimación: importan la composición corporal, altura, edad, actividad y tu tendencia de progreso.',
        'de':
            'Wird für ein leitlinienbasiertes Startziel für Kalorien verwendet. Es bleibt eine Schätzung: Körperzusammensetzung, Größe, Alter, Aktivität und dein Verlauf zählen mit.',
      });

  String get heightCm => _t({
        'en': 'Height',
        'pl': 'Wzrost',
        'nl': 'Lengte',
        'es': 'Altura',
        'de': 'Größe',
      });

  String get muscleAmount => _t({
        'en': 'Muscle amount',
        'pl': 'Ilość mięśni',
        'nl': 'Spiermassa',
        'es': 'Cantidad de músculo',
        'de': 'Muskelanteil',
      });

  String get nameDashboardHint => _t({
        'en': "We'll use it to personalise your dashboard.",
        'pl': 'Użyjemy go, aby spersonalizować Twój panel.',
        'nl': 'We gebruiken het om je dashboard te personaliseren.',
        'es': 'Lo usaremos para personalizar tu panel.',
        'de': 'Wir verwenden ihn, um dein Dashboard zu personalisieren.',
      });

  String get yourNameHint => _t({
        'en': 'Your name',
        'pl': 'Twoje imię',
        'nl': 'Je naam',
        'es': 'Tu nombre',
        'de': 'Dein Name',
      });

  String get genderTargetsNote => _t({
        'en':
            'Used to personalise your nutrient targets\n(vitamin, mineral & calorie recommendations).',
        'pl':
            'Służy do personalizacji celów odżywczych\n(witaminy, minerały i kalorie).',
        'nl':
            'Gebruikt om je voedingsdoelen te personaliseren\n(vitamines, mineralen en calorieën).',
        'es':
            'Se usa para personalizar tus objetivos nutricionales\n(vitaminas, minerales y calorías).',
        'de':
            'Dient zur Personalisierung deiner Nährstoffziele\n(Vitamine, Mineralstoffe und Kalorien).',
      });

  String get whatsYourGoal => _t({
        'en': "What's your goal?",
        'pl': 'Jaki jest Twój cel?',
        'nl': 'Wat is je doel?',
        'es': '¿Cuál es tu objetivo?',
        'de': 'Was ist dein Ziel?',
      });

  String get goalLifestyleSubtitle => _t({
        'en': 'Choose the plan that fits your lifestyle.',
        'pl': 'Wybierz plan dopasowany do Twojego stylu życia.',
        'nl': 'Kies het plan dat bij je leven past.',
        'es': 'Elige el plan que se adapte a tu estilo de vida.',
        'de': 'Wähle den Plan, der zu deinem Leben passt.',
      });

  String get dailyTargetsAdjust => _t({
        'en': 'Your daily targets (adjust if needed)',
        'pl': 'Twoje dzienne cele (dostosuj w razie potrzeby)',
        'nl': 'Je dagelijkse doelen (pas aan indien nodig)',
        'es': 'Tus objetivos diarios (ajústalos si quieres)',
        'de': 'Deine Tagesziele (bei Bedarf anpassen)',
      });

  String get sliderDailyCalories => _t({
        'en': '🔥 Daily Calories',
        'pl': '🔥 Dzienne kalorie',
        'nl': '🔥 Dagelijkse calorieën',
        'es': '🔥 Calorías diarias',
        'de': '🔥 Tägliche Kalorien',
      });

  String get sliderCarbLimit => _t({
        'en': '🍞 Carb Limit',
        'pl': '🍞 Limit węglowodanów',
        'nl': '🍞 Koolhydraatlimiet',
        'es': '🍞 Límite de carbohidratos',
        'de': '🍞 Kohlenhydrat-Limit',
      });

  String get sliderProteinTarget => _t({
        'en': '💪 Protein Target',
        'pl': '💪 Cel białka',
        'nl': '💪 Eiwitdoel',
        'es': '💪 Objetivo de proteínas',
        'de': '💪 Proteinziel',
      });

  String get sliderFatTarget => _t({
        'en': '🥑 Fat Target',
        'pl': '🥑 Cel tłuszczu',
        'nl': '🥑 Vetdoel',
        'es': '🥑 Objetivo de grasas',
        'de': '🥑 Fettziel',
      });

  String get gramsPerDayUnit => _t({
        'en': 'g / day',
        'pl': 'g / dzień',
        'nl': 'g / dag',
        'es': 'g / día',
        'de': 'g / Tag',
      });

  String macrosAddUpTo(int total, int pct, int target) => _t({
        'en': 'Macros add up to $total kcal ($pct% of $target kcal target)',
        'pl': 'Makroskładniki dają $total kcal ($pct% z celu $target kcal)',
        'nl': "Macro's tellen op tot $total kcal ($pct% van $target kcal-doel)",
        'es':
            'Los macros suman $total kcal ($pct% del objetivo de $target kcal)',
        'de': 'Makros ergeben $total kcal ($pct% des Ziels von $target kcal)',
      });

  String get icrTitle => _t({
        'en': 'Your Insulin-to-Carb Ratio',
        'pl': 'Twój współczynnik insulina-węglowodany',
        'nl': 'Je insuline-koolhydraatratio',
        'es': 'Tu ratio insulina-carbohidratos',
        'de': 'Dein Insulin-Kohlenhydrat-Verhältnis',
      });

  String get icrExplanation => _t({
        'en':
            'Your ICR (Insulin-to-Carb Ratio) tells you how many grams of carbohydrate one unit of insulin covers.\n\n'
                'Example: an ICR of 10 means 1 unit covers 10 g of carbs.\n\n'
                'This value is personal and should be set by your diabetes care team. '
                'Do NOT use a pre-set value — an incorrect ICR can cause dangerous blood sugar swings.',
        'pl':
            'Twój WWcW (współczynnik insulina-węglowodany) mówi, ile gramów węglowodanów pokrywa jedna jednostka insuliny.\n\n'
                'Przykład: WWcW równy 10 oznacza, że 1 jednostka pokrywa 10 g węglowodanów.\n\n'
                'Ta wartość jest indywidualna i powinna być ustalona przez Twój zespół diabetologiczny. '
                'NIE używaj wartości domyślnej — błędny współczynnik może powodować groźne wahania cukru.',
        'nl':
            'Je ICR (insuline-koolhydraatratio) geeft aan hoeveel gram koolhydraten één eenheid insuline dekt.\n\n'
                'Voorbeeld: een ICR van 10 betekent dat 1 eenheid 10 g koolhydraten dekt.\n\n'
                'Deze waarde is persoonlijk en moet door je diabetesteam worden ingesteld. '
                'Gebruik GEEN vooraf ingestelde waarde — een onjuiste ICR kan gevaarlijke bloedsuikerschommelingen veroorzaken.',
        'es':
            'Tu ICR (ratio insulina-carbohidratos) indica cuántos gramos de carbohidratos cubre una unidad de insulina.\n\n'
                'Ejemplo: un ICR de 10 significa que 1 unidad cubre 10 g de carbohidratos.\n\n'
                'Este valor es personal y debe establecerlo tu equipo médico de diabetes. '
                'NO uses un valor predefinido: un ICR incorrecto puede causar variaciones peligrosas de azúcar en sangre.',
        'de':
            'Dein KE-Faktor (Insulin-Kohlenhydrat-Verhältnis) gibt an, wie viele Gramm Kohlenhydrate eine Einheit Insulin abdeckt.\n\n'
                'Beispiel: Ein ICR von 10 bedeutet, dass 1 Einheit 10 g Kohlenhydrate abdeckt.\n\n'
                'Dieser Wert ist persönlich und sollte von deinem Diabetes-Team festgelegt werden. '
                'Verwende KEINEN voreingestellten Wert — ein falscher ICR kann gefährliche Blutzuckerschwankungen verursachen.',
      });

  String get icrFieldLabel => _t({
        'en': 'ICR — grams of carbs per 1 unit of insulin',
        'pl': 'WWcW — gramy węglowodanów na 1 jednostkę insuliny',
        'nl': 'ICR — gram koolhydraten per 1 eenheid insuline',
        'es': 'ICR — gramos de carbohidratos por 1 unidad de insulina',
        'de': 'ICR — Gramm Kohlenhydrate pro 1 Einheit Insulin',
      });

  String get icrExampleHint => _t({
        'en': 'e.g. 10',
        'pl': 'np. 10',
        'nl': 'bv. 10',
        'es': 'p. ej. 10',
        'de': 'z. B. 10',
      });

  /// Localized mascot evolution-stage label shown under the home mascot.
  /// [key] is a stable stage key defined in goal_mascot_widget.dart.
  String mascotStageLabel(String key) {
    switch (key) {
      case 'gorilla_baby':
        return _t({'en': 'Baby Gorilla', 'pl': 'Mały goryl', 'nl': 'Babygorilla', 'es': 'Gorila bebé', 'de': 'Baby-Gorilla'});
      case 'gorilla_growing':
      case 'plant_growing':
        return _t({'en': 'Growing Strong', 'pl': 'Rośnie w siłę', 'nl': 'Wordt sterker', 'es': 'Creciendo fuerte', 'de': 'Wird stärker'});
      case 'gorilla_mighty':
        return _t({'en': 'Mighty Gorilla', 'pl': 'Potężny goryl', 'nl': 'Machtige gorilla', 'es': 'Gorila poderoso', 'de': 'Mächtiger Gorilla'});
      case 'gorilla_champion':
        return _t({'en': 'Champion', 'pl': 'Mistrz', 'nl': 'Kampioen', 'es': 'Campeón', 'de': 'Champion'});
      case 'plant_seedling':
        return _t({'en': 'Seedling', 'pl': 'Sadzonka', 'nl': 'Zaailing', 'es': 'Plántula', 'de': 'Sämling'});
      case 'plant_sprouting':
        return _t({'en': 'Sprouting', 'pl': 'Kiełkowanie', 'nl': 'Ontkiemend', 'es': 'Brotando', 'de': 'Keimt'});
      case 'plant_bloom':
        return _t({'en': 'In Full Bloom', 'pl': 'W pełnym rozkwicie', 'nl': 'In volle bloei', 'es': 'En plena floración', 'de': 'In voller Blüte'});
      case 'flame_none':
        return _t({'en': 'No Burn Yet', 'pl': 'Brak spalania', 'nl': 'Nog geen verbranding', 'es': 'Sin quema aún', 'de': 'Noch keine Verbrennung'});
      case 'flame_warming':
        return _t({'en': 'Warming Up', 'pl': 'Rozgrzewka', 'nl': 'Opwarmen', 'es': 'Calentando', 'de': 'Aufwärmen'});
      case 'flame_burning':
        return _t({'en': 'Fat Burning', 'pl': 'Spalanie tłuszczu', 'nl': 'Vetverbranding', 'es': 'Quema de grasa', 'de': 'Fettverbrennung'});
      case 'flame_extreme':
        return _t({'en': 'Extreme Burn', 'pl': 'Ekstremalne spalanie', 'nl': 'Extreme verbranding', 'es': 'Quema extrema', 'de': 'Extreme Verbrennung'});
      case 'sugar_overload':
        return _t({'en': 'Sugar Overload', 'pl': 'Przeładowanie cukrem', 'nl': 'Suikeroverbelasting', 'es': 'Sobrecarga de azúcar', 'de': 'Zuckerüberladung'});
      case 'sugar_toomuch':
        return _t({'en': 'Too Much Sugar', 'pl': 'Za dużo cukru', 'nl': 'Te veel suiker', 'es': 'Demasiado azúcar', 'de': 'Zu viel Zucker'});
      case 'sugar_control':
        return _t({'en': 'Under Control', 'pl': 'Pod kontrolą', 'nl': 'Onder controle', 'es': 'Bajo control', 'de': 'Unter Kontrolle'});
      case 'sugar_excellent':
        return _t({'en': 'Excellent Control', 'pl': 'Doskonała kontrola', 'nl': 'Uitstekende controle', 'es': 'Control excelente', 'de': 'Ausgezeichnete Kontrolle'});
      default:
        return key;
    }
  }

  String get nutritionDetails => _t({
        'en': 'Nutrition details',
        'pl': 'Szczegóły żywieniowe',
        'nl': 'Voedingsdetails',
        'es': 'Detalles nutricionales',
        'de': 'Nährwertdetails',
      });

  String get bodyProfileEstimateNote => _t({
        'en':
            'Calories use weight, height, biological sex and muscle amount as a starting estimate, then should be refined from your real weight trend.',
        'pl':
            'Kalorie używają masy, wzrostu, płci biologicznej i ilości mięśni jako punktu startowego, a potem powinny być dopasowane do realnego trendu masy.',
        'nl':
            'Calorieën gebruiken gewicht, lengte, biologisch geslacht en spiermassa als startschatting en moeten daarna worden verfijnd met je echte gewichtstrend.',
        'es':
            'Las calorías usan peso, altura, sexo biológico y cantidad de músculo como estimación inicial, y luego deben ajustarse con tu tendencia real de peso.',
        'de':
            'Kalorien nutzen Gewicht, Größe, biologisches Geschlecht und Muskelanteil als Startschätzung und sollten danach mit deinem echten Gewichtstrend verfeinert werden.',
      });

  String get adaptiveCalorieCalibration => _t({
        'en': 'Adaptive calorie calibration',
        'pl': 'Adaptacyjna kalibracja kalorii',
        'nl': 'Adaptieve caloriecalibratie',
        'es': 'Calibración calórica adaptativa',
        'de': 'Adaptive Kalorienkalibrierung',
      });

  String get adaptiveCalorieCalibrationDesc => _t({
        'en':
            'Log your weight once per month. The app gently adjusts calorie targets from trend instead of guessing forever from a formula.',
        'pl':
            'Zapisuj masę raz w miesiącu. Aplikacja delikatnie dopasowuje kalorie z trendu, zamiast ciągle zgadywać ze wzoru.',
        'nl':
            'Log je gewicht één keer per maand. De app past calorieën voorzichtig aan op basis van trend in plaats van steeds te schatten.',
        'es':
            'Registra tu peso una vez al mes. La app ajusta suavemente las calorías según la tendencia en vez de adivinar siempre con una fórmula.',
        'de':
            'Trage dein Gewicht einmal pro Monat ein. Die App passt Kalorien vorsichtig nach Trend an, statt dauerhaft nur zu schätzen.',
      });

  String get logMonthlyWeight => _t({
        'en': 'Log monthly weight',
        'pl': 'Zapisz miesięczną masę',
        'nl': 'Maandgewicht loggen',
        'es': 'Registrar peso mensual',
        'de': 'Monatsgewicht eintragen',
      });

  String get noMonthlyWeightsYet => _t({
        'en': 'No monthly weights yet. Add this month to start calibration.',
        'pl':
            'Brak miesięcznych pomiarów. Dodaj ten miesiąc, aby zacząć kalibrację.',
        'nl': 'Nog geen maandgewichten. Voeg deze maand toe om te starten.',
        'es': 'Aún no hay pesos mensuales. Añade este mes para empezar.',
        'de':
            'Noch keine Monatsgewichte. Füge diesen Monat hinzu, um zu starten.',
      });

  String get monthlyWeightHelper => _t({
        'en': 'One entry per month; saving again updates this month.',
        'pl': 'Jeden wpis na miesiąc; ponowny zapis aktualizuje ten miesiąc.',
        'nl': 'Eén invoer per maand; opnieuw opslaan werkt deze maand bij.',
        'es': 'Una entrada por mes; guardar otra vez actualiza este mes.',
        'de':
            'Ein Eintrag pro Monat; erneutes Speichern aktualisiert diesen Monat.',
      });

  String calorieCalibrationMessage(String key) {
    switch (key) {
      case 'firstMonthlyWeightSaved':
        return _t({
          'en':
              'First monthly weight saved. Add another month to calibrate from trend.',
          'pl':
              'Pierwsza miesięczna masa zapisana. Dodaj kolejny miesiąc, aby kalibrować z trendu.',
          'nl':
              'Eerste maandgewicht opgeslagen. Voeg nog een maand toe om op trend te kalibreren.',
          'es':
              'Primer peso mensual guardado. Añade otro mes para calibrar con la tendencia.',
          'de':
              'Erstes Monatsgewicht gespeichert. Füge einen weiteren Monat hinzu, um nach Trend zu kalibrieren.',
        });
      case 'weightTrendAligned':
        return _t({
          'en': 'Weight trend is aligned; calories stayed steady.',
          'pl': 'Trend masy jest zgodny; kalorie zostały bez zmian.',
          'nl': 'Gewichtstrend past; calorieën blijven gelijk.',
          'es':
              'La tendencia de peso está alineada; las calorías se mantienen.',
          'de': 'Gewichtstrend passt; Kalorien bleiben stabil.',
        });
      case 'weightLossSlow':
        return _t({
          'en':
              'Weight loss is slower than planned, so calories were nudged down gently.',
          'pl':
              'Utrata masy jest wolniejsza niż plan, więc kalorie delikatnie obniżono.',
          'nl':
              'Gewichtsverlies gaat trager dan gepland, dus calorieën zijn licht verlaagd.',
          'es':
              'La pérdida de peso va más lenta de lo previsto, así que se bajaron suavemente las calorías.',
          'de':
              'Gewichtsverlust ist langsamer als geplant, daher wurden Kalorien leicht gesenkt.',
        });
      case 'weightLossFast':
        return _t({
          'en':
              'Weight loss is fast, so calories were nudged up to protect energy and lean mass.',
          'pl':
              'Utrata masy jest szybka, więc kalorie lekko podniesiono dla energii i mięśni.',
          'nl':
              'Gewichtsverlies gaat snel, dus calorieën zijn licht verhoogd voor energie en spiermassa.',
          'es':
              'La pérdida de peso es rápida, así que se subieron calorías para proteger energía y masa magra.',
          'de':
              'Gewichtsverlust ist schnell, daher wurden Kalorien zum Schutz von Energie und Muskelmasse leicht erhöht.',
        });
      case 'weightGainSlow':
        return _t({
          'en':
              'Weight gain is slower than planned, so calories were nudged up.',
          'pl':
              'Przyrost masy jest wolniejszy niż plan, więc kalorie lekko podniesiono.',
          'nl':
              'Gewichtstoename gaat trager dan gepland, dus calorieën zijn licht verhoogd.',
          'es':
              'La subida de peso va más lenta de lo previsto, así que se subieron calorías.',
          'de':
              'Gewichtszunahme ist langsamer als geplant, daher wurden Kalorien leicht erhöht.',
        });
      case 'weightGainFast':
        return _t({
          'en':
              'Weight is rising quickly, so calories were nudged down slightly.',
          'pl': 'Masa rośnie szybko, więc kalorie lekko obniżono.',
          'nl': 'Gewicht stijgt snel, dus calorieën zijn licht verlaagd.',
          'es': 'El peso sube rápido, así que se bajaron un poco las calorías.',
          'de': 'Gewicht steigt schnell, daher wurden Kalorien leicht gesenkt.',
        });
      case 'weightTrendingUp':
        return _t({
          'en':
              'Weight is trending upward, so calories were nudged down slightly.',
          'pl': 'Masa trenduje w górę, więc kalorie lekko obniżono.',
          'nl': 'Gewicht trendt omhoog, dus calorieën zijn licht verlaagd.',
          'es':
              'El peso tiende a subir, así que se bajaron un poco las calorías.',
          'de':
              'Gewicht tendiert nach oben, daher wurden Kalorien leicht gesenkt.',
        });
      case 'weightTrendingDown':
        return _t({
          'en':
              'Weight is trending downward, so calories were nudged up slightly.',
          'pl': 'Masa trenduje w dół, więc kalorie lekko podniesiono.',
          'nl': 'Gewicht trendt omlaag, dus calorieën zijn licht verhoogd.',
          'es':
              'El peso tiende a bajar, así que se subieron un poco las calorías.',
          'de':
              'Gewicht tendiert nach unten, daher wurden Kalorien leicht erhöht.',
        });
    }
    return key;
  }

  String get dietaryRestrictions => _t({
        'en': 'Dietary restrictions',
        'pl': 'Ograniczenia żywieniowe',
        'nl': 'Dieetbeperkingen',
        'es': 'Restricciones dietéticas',
        'de': 'Ernährungseinschränkungen',
      });

  String get dietaryRestrictionsDesc => _t({
        'en':
            'Used for recipe filters, meal planning, and scan/manual entry alerts.',
        'pl':
            'Używane w filtrach przepisów, planowaniu posiłków i alertach skanu/ręcznego wpisu.',
        'nl':
            'Gebruikt voor receptfilters, maaltijdplanning en waarschuwingen bij scan/handmatige invoer.',
        'es':
            'Se usa en filtros de recetas, planificación y alertas de escaneo/entrada manual.',
        'de':
            'Für Rezeptfilter, Mahlzeitenplanung und Scan-/manuelle Warnungen.',
      });

  String get restrictionAlert => _t({
        'en': 'Restriction alert',
        'pl': 'Alert ograniczenia',
        'nl': 'Beperkingswaarschuwing',
        'es': 'Alerta de restricción',
        'de': 'Einschränkungswarnung',
      });

  String get restrictionScanNote => _t({
        'en':
            'Scan labels can be imperfect. Check ingredients and labels before eating or logging.',
        'pl':
            'Etykiety ze skanu mogą być niedokładne. Sprawdź skład i etykiety przed jedzeniem lub zapisem.',
        'nl':
            'Scanlabels kunnen onvolmaakt zijn. Controleer ingrediënten en etiketten vóór eten of loggen.',
        'es':
            'Las etiquetas del escaneo pueden fallar. Revisa ingredientes y etiquetas antes de comer o registrar.',
        'de':
            'Scan-Bezeichnungen können ungenau sein. Prüfe Zutaten und Etiketten vor dem Essen oder Speichern.',
      });

  String dietaryRestrictionLabel(String key) {
    switch (key) {
      case 'glutenFree':
        return _t({
          'en': 'Gluten-Free',
          'pl': 'Bez glutenu',
          'nl': 'Glutenvrij',
          'es': 'Sin gluten',
          'de': 'Glutenfrei',
        });
      case 'dairyFree':
        return _t({
          'en': 'Lactose-Free / Dairy-Free',
          'pl': 'Bez laktozy / nabiału',
          'nl': 'Lactosevrij / zuivelvrij',
          'es': 'Sin lactosa / sin lácteos',
          'de': 'Laktosefrei / milchfrei',
        });
      case 'nutFree':
        return _t({
          'en': 'Nut-Free',
          'pl': 'Bez orzechów',
          'nl': 'Notenvrij',
          'es': 'Sin frutos secos',
          'de': 'Nussfrei',
        });
    }
    return key;
  }

  String dietaryRestrictionShortLabel(String key) {
    switch (key) {
      case 'glutenFree':
        return _t({
          'en': 'Gluten-Free',
          'pl': 'Bez glutenu',
          'nl': 'Glutenvrij',
          'es': 'Sin gluten',
          'de': 'Glutenfrei',
        });
      case 'dairyFree':
        return _t({
          'en': 'Dairy-Free',
          'pl': 'Bez nabiału',
          'nl': 'Zuivelvrij',
          'es': 'Sin lácteos',
          'de': 'Milchfrei',
        });
      case 'nutFree':
        return _t({
          'en': 'Nut-Free',
          'pl': 'Bez orzechów',
          'nl': 'Notenvrij',
          'es': 'Sin frutos secos',
          'de': 'Nussfrei',
        });
    }
    return key;
  }

  String dietaryRestrictionDescription(String key) {
    switch (key) {
      case 'glutenFree':
        return _t({
          'en':
              'Filters wheat, rye, barley, malt, seitan, flour, pasta, bread, and similar gluten sources.',
          'pl':
              'Filtruje pszenicę, żyto, jęczmień, słód, seitan, mąkę, makaron, chleb i podobne źródła glutenu.',
          'nl':
              'Filtert tarwe, rogge, gerst, mout, seitan, bloem, pasta, brood en vergelijkbare glutenbronnen.',
          'es':
              'Filtra trigo, centeno, cebada, malta, seitán, harina, pasta, pan y fuentes similares de gluten.',
          'de':
              'Filtert Weizen, Roggen, Gerste, Malz, Seitan, Mehl, Pasta, Brot und ähnliche Glutenquellen.',
        });
      case 'dairyFree':
        return _t({
          'en':
              'Filters milk, lactose, cheese, yogurt, cream, butter, whey, casein, and similar dairy sources.',
          'pl':
              'Filtruje mleko, laktozę, ser, jogurt, śmietanę, masło, serwatkę, kazeinę i podobne źródła nabiału.',
          'nl':
              'Filtert melk, lactose, kaas, yoghurt, room, boter, wei, caseïne en vergelijkbare zuivelbronnen.',
          'es':
              'Filtra leche, lactosa, queso, yogur, crema, mantequilla, suero, caseína y fuentes lácteas similares.',
          'de':
              'Filtert Milch, Laktose, Käse, Joghurt, Sahne, Butter, Molke, Casein und ähnliche Milchquellen.',
        });
      case 'nutFree':
        return _t({
          'en':
              'Filters tree nuts and peanut ingredients, including nut butters, nut flours, and common nut oils.',
          'pl':
              'Filtruje orzechy drzewne i arachidowe, w tym masła, mąki i popularne oleje orzechowe.',
          'nl':
              'Filtert noten en pinda-ingrediënten, inclusief notenpasta, notenmeel en veelgebruikte notenoliën.',
          'es':
              'Filtra frutos secos y cacahuete, incluidas mantequillas, harinas y aceites comunes de frutos secos.',
          'de':
              'Filtert Nüsse und Erdnusszutaten, einschließlich Nussmus, Nussmehl und gängiger Nussöle.',
        });
    }
    return key;
  }

  String restrictionItemAlert(String itemName, String restrictionKey) => _t({
        'en':
            '$itemName may not fit your ${dietaryRestrictionShortLabel(restrictionKey)} setting. Check ingredients and labels before logging it.',
        'pl':
            '$itemName może nie pasować do ustawienia ${dietaryRestrictionShortLabel(restrictionKey)}. Sprawdź skład i etykiety przed zapisem.',
        'nl':
            '$itemName past mogelijk niet bij je instelling ${dietaryRestrictionShortLabel(restrictionKey)}. Controleer ingrediënten en etiketten vóór het loggen.',
        'es':
            '$itemName puede no encajar con tu ajuste ${dietaryRestrictionShortLabel(restrictionKey)}. Revisa ingredientes y etiquetas antes de registrarlo.',
        'de':
            '$itemName passt möglicherweise nicht zu deiner Einstellung ${dietaryRestrictionShortLabel(restrictionKey)}. Prüfe Zutaten und Etiketten vor dem Speichern.',
      });

  String get progressStoryTitle => _t({
        'en': 'Progress Story',
        'pl': 'Historia postępów',
        'nl': 'Voortgangsverhaal',
        'es': 'Historia de progreso',
        'de': 'Fortschrittsstory',
      });

  String get progressStorySubtitle => _t({
        'en':
            'A compact recap of how your logging, planning, pantry and body trend are moving together.',
        'pl':
            'Krótkie podsumowanie tego, jak łączą się logowanie, planowanie, spiżarnia i trend masy.',
        'nl':
            'Een compacte samenvatting van hoe je logging, planning, voorraad en gewichtstrend samen bewegen.',
        'es':
            'Un resumen compacto de cómo avanzan juntos tu registro, planificación, despensa y tendencia corporal.',
        'de':
            'Eine kompakte Übersicht, wie Logging, Planung, Vorrat und Gewichtstrend zusammenspielen.',
      });

  String get progressStoryLoadFailed => _t({
        'en': 'Progress story could not be loaded.',
        'pl': 'Nie udało się wczytać historii postępów.',
        'nl': 'Voortgangsverhaal kon niet worden geladen.',
        'es': 'No se pudo cargar la historia de progreso.',
        'de': 'Fortschrittsstory konnte nicht geladen werden.',
      });

  String progressMomentum(int percent) => _t({
        'en': '$percent% monthly logging momentum',
        'pl': '$percent% miesięcznej regularności',
        'nl': '$percent% maandelijkse logmomentum',
        'es': '$percent% de impulso mensual de registro',
        'de': '$percent% monatlicher Logging-Schwung',
      });

  String storyTotalScans(int count) => _t({
        'en': '$count meals scanned',
        'pl': '$count zeskanowanych posiłków',
        'nl': '$count maaltijden gescand',
        'es': '$count comidas escaneadas',
        'de': '$count Mahlzeiten gescannt',
      });

  String get storyTotalScansBody => _t({
        'en': 'Every scan gives the app more context for your food patterns.',
        'pl':
            'Każdy skan daje aplikacji więcej kontekstu o Twoich wzorcach jedzenia.',
        'nl': 'Elke scan geeft de app meer context over je eetpatronen.',
        'es': 'Cada escaneo da más contexto sobre tus patrones de comida.',
        'de': 'Jeder Scan gibt der App mehr Kontext zu deinen Essmustern.',
      });

  String storyLoggedDays(int count) => _t({
        'en': '$count active days in the last 30',
        'pl': '$count aktywnych dni z ostatnich 30',
        'nl': '$count actieve dagen in de laatste 30',
        'es': '$count días activos en los últimos 30',
        'de': '$count aktive Tage in den letzten 30',
      });

  String get storyLoggedDaysBody => _t({
        'en': 'Consistency matters more than perfect entries.',
        'pl': 'Regularność jest ważniejsza niż idealne wpisy.',
        'nl': 'Consistentie telt meer dan perfecte invoer.',
        'es': 'La constancia importa más que entradas perfectas.',
        'de': 'Konstanz ist wichtiger als perfekte Einträge.',
      });

  String storyAverageCalories(int kcal) => _t({
        'en':
            kcal > 0 ? '$kcal kcal average logged day' : 'No calorie trend yet',
        'pl': kcal > 0
            ? 'Średnio $kcal kcal w dniu z wpisem'
            : 'Brak trendu kalorii',
        'nl': kcal > 0
            ? '$kcal kcal gemiddeld per logdag'
            : 'Nog geen calorietrend',
        'es': kcal > 0
            ? '$kcal kcal de media en días registrados'
            : 'Aún no hay tendencia calórica',
        'de': kcal > 0
            ? '$kcal kcal im Schnitt pro Logtag'
            : 'Noch kein Kalorientrend',
      });

  String get storyAverageCaloriesBody => _t({
        'en': 'Use the trend with your goal, weight change and energy levels.',
        'pl': 'Łącz trend z celem, zmianą masy i poziomem energii.',
        'nl': 'Gebruik de trend samen met je doel, gewicht en energieniveau.',
        'es': 'Usa la tendencia junto con tu objetivo, peso y energía.',
        'de': 'Nutze den Trend zusammen mit Ziel, Gewicht und Energie.',
      });

  String storyWeightTrend(double? changeKg) => _t({
        'en': changeKg == null
            ? 'Weight trend needs 2 months'
            : '${changeKg >= 0 ? '+' : ''}${changeKg.toStringAsFixed(1)} kg since last month',
        'pl': changeKg == null
            ? 'Trend masy wymaga 2 miesięcy'
            : '${changeKg >= 0 ? '+' : ''}${changeKg.toStringAsFixed(1)} kg od zeszłego miesiąca',
        'nl': changeKg == null
            ? 'Gewichtstrend heeft 2 maanden nodig'
            : '${changeKg >= 0 ? '+' : ''}${changeKg.toStringAsFixed(1)} kg sinds vorige maand',
        'es': changeKg == null
            ? 'La tendencia necesita 2 meses'
            : '${changeKg >= 0 ? '+' : ''}${changeKg.toStringAsFixed(1)} kg desde el mes pasado',
        'de': changeKg == null
            ? 'Gewichtstrend braucht 2 Monate'
            : '${changeKg >= 0 ? '+' : ''}${changeKg.toStringAsFixed(1)} kg seit letztem Monat',
      });

  String get storyWeightTrendBody => _t({
        'en':
            'Monthly entries help calibrate calorie targets from real outcomes.',
        'pl':
            'Miesięczne wpisy pomagają kalibrować kalorie z realnych efektów.',
        'nl': 'Maandelijkse invoer kalibreert calorieën op echte resultaten.',
        'es': 'Las entradas mensuales calibran calorías con resultados reales.',
        'de':
            'Monatliche Einträge kalibrieren Kalorien mit echten Ergebnissen.',
      });

  String storyPlannedMeals(int count) => _t({
        'en': '$count meals planned this week',
        'pl': '$count posiłków zaplanowanych w tym tygodniu',
        'nl': '$count maaltijden gepland deze week',
        'es': '$count comidas planificadas esta semana',
        'de': '$count Mahlzeiten diese Woche geplant',
      });

  String get storyPlannedMealsBody => _t({
        'en': 'Planning turns goals into ready choices before hunger decides.',
        'pl': 'Planowanie zamienia cele w gotowe wybory, zanim zdecyduje głód.',
        'nl': 'Planning maakt doelen klaar voordat honger beslist.',
        'es':
            'Planificar convierte objetivos en opciones antes de que decida el hambre.',
        'de':
            'Planung macht Ziele zu fertigen Entscheidungen, bevor Hunger entscheidet.',
      });

  String storyPantryItems(int count) => _t({
        'en': '$count pantry ingredients ready',
        'pl': '$count składników w spiżarni',
        'nl': '$count voorraadingrediënten klaar',
        'es': '$count ingredientes listos en despensa',
        'de': '$count Vorratszutaten bereit',
      });

  String get storyPantryItemsBody => _t({
        'en': 'Pantry Mode helps plans use what you already have.',
        'pl': 'Tryb spiżarni pomaga planom używać tego, co już masz.',
        'nl': 'Voorraadmodus helpt plannen gebruiken wat je al hebt.',
        'es': 'El modo despensa ayuda a usar lo que ya tienes.',
        'de': 'Vorratsmodus hilft, vorhandene Zutaten zu nutzen.',
      });

  String get getStarted => _t({
        'en': 'Let\'s get started!',
        'pl': 'Zaczynajmy!',
        'nl': 'Laten we beginnen!',
        'es': '¡Comencemos!',
        'de': 'Los geht\'s!',
      });

  String get chooseLanguage => _t({
        'en': 'Choose your language',
        'pl': 'Wybierz język',
        'nl': 'Kies je taal',
        'es': 'Elige tu idioma',
        'de': 'Wähle deine Sprache',
      });

  String get languageChangeLater => _t({
        'en': 'You can change this later in Settings.',
        'pl': 'Możesz to później zmienić w Ustawieniach.',
        'nl': 'Je kunt dit later wijzigen in Instellingen.',
        'es': 'Puedes cambiar esto más tarde en Ajustes.',
        'de': 'Du kannst dies später in den Einstellungen ändern.',
      });

  String get aiSpeech => _t({
        'en': 'AI Speech',
        'pl': 'Mowa AI',
        'nl': 'AI Spraak',
        'es': 'Voz IA',
        'de': 'KI-Sprache',
      });

  String get manualLog => _t({
        'en': 'Manual Log',
        'pl': 'Ręczny wpis',
        'nl': 'Handmatig loggen',
        'es': 'Registro manual',
        'de': 'Manueller Eintrag',
      });

  String get aiScan => _t({
        'en': 'AI Scan',
        'pl': 'Skan AI',
        'nl': 'AI Scan',
        'es': 'Escaneo IA',
        'de': 'KI-Scan',
      });

  String get allGoals => _t({
        'en': 'All goals',
        'pl': 'Wszystkie cele',
        'nl': 'Alle doelen',
        'es': 'Todos los objetivos',
        'de': 'Alle Ziele',
      });

  String get allMeals => _t({
        'en': 'All meals',
        'pl': 'Wszystkie posiłki',
        'nl': 'Alle maaltijden',
        'es': 'Todas las comidas',
        'de': 'Alle Mahlzeiten',
      });

  String get myMeals => _t({
        'en': 'My Meals',
        'pl': 'Moje posiłki',
        'nl': 'Mijn maaltijden',
        'es': 'Mis comidas',
        'de': 'Meine Mahlzeiten',
      });

  String get newItem => _t({
        'en': 'New',
        'pl': 'Nowy',
        'nl': 'Nieuw',
        'es': 'Nuevo',
        'de': 'Neu',
      });

  String get startScanning => _t({
        'en': 'Start Scanning! 🚀',
        'pl': 'Zacznij skanować! 🚀',
        'nl': 'Start met scannen! 🚀',
        'es': '¡Empieza a escanear! 🚀',
        'de': 'Scannen starten! 🚀',
      });

  // ── Goals ──

  String get muscleGrowth => _t({
        'en': 'Muscle Growth',
        'pl': 'Budowa mięśni',
        'nl': 'Spiergroei',
        'es': 'Crecimiento muscular',
        'de': 'Muskelaufbau',
      });

  String get diabetes => _t({
        'en': 'Diabetes',
        'pl': 'Cukrzyca',
        'nl': 'Diabetes',
        'es': 'Diabetes',
        'de': 'Diabetes',
      });

  String get veganDiet => _t({
        'en': 'Vegan Diet',
        'pl': 'Dieta wegańska',
        'nl': 'Veganistisch dieet',
        'es': 'Dieta vegana',
        'de': 'Vegane Ernährung',
      });

  String get vegetarianDiet => _t({
        'en': 'Vegetarian Diet',
        'pl': 'Dieta wegetariańska',
        'nl': 'Vegetarisch dieet',
        'es': 'Dieta vegetariana',
        'de': 'Vegetarische Ernährung',
      });

  String get pescatarian => _t({
        'en': 'Pescatarian',
        'pl': 'Peskatarianizm',
        'nl': 'Pescotarisch',
        'es': 'Pescetariana',
        'de': 'Pescetarisch',
      });

  String get mediterranean => _t({
        'en': 'Mediterranean',
        'pl': 'Dieta śródziemnomorska',
        'nl': 'Mediterraan',
        'es': 'Mediterránea',
        'de': 'Mediterran',
      });

  String get weightLoss => _t({
        'en': 'Weight Loss',
        'pl': 'Odchudzanie',
        'nl': 'Gewichtsverlies',
        'es': 'Pérdida de peso',
        'de': 'Gewichtsverlust',
      });

  String get keto => _t({
        'en': 'Keto',
        'pl': 'Keto',
        'nl': 'Keto',
        'es': 'Keto',
        'de': 'Keto',
      });

  String get maintainWeight => _t({
        'en': 'Maintain Weight',
        'pl': 'Utrzymanie wagi',
        'nl': 'Gewicht behouden',
        'es': 'Mantener peso',
        'de': 'Gewicht halten',
      });

  // ── Meals ──

  String get breakfast => _t({
        'en': 'Breakfast',
        'pl': 'Śniadanie',
        'nl': 'Ontbijt',
        'es': 'Desayuno',
        'de': 'Frühstück',
      });

  String get lunch => _t({
        'en': 'Lunch',
        'pl': 'Obiad',
        'nl': 'Lunch',
        'es': 'Almuerzo',
        'de': 'Mittagessen',
      });

  String get dinner => _t({
        'en': 'Dinner',
        'pl': 'Kolacja',
        'nl': 'Diner',
        'es': 'Cena',
        'de': 'Abendessen',
      });

  String get snack => _t({
        'en': 'Snack',
        'pl': 'Przekąska',
        'nl': 'Snack',
        'es': 'Merienda',
        'de': 'Snack',
      });

  String get dessert => _t({
        'en': 'Dessert',
        'pl': 'Deser',
        'nl': 'Dessert',
        'es': 'Postre',
        'de': 'Dessert',
      });

  // ── Macros ──

  String get calories => _t({
        'en': 'Calories',
        'pl': 'Kalorie',
        'nl': 'Calorieën',
        'es': 'Calorías',
        'de': 'Kalorien',
      });

  String get protein => _t({
        'en': 'Protein',
        'pl': 'Białko',
        'nl': 'Eiwit',
        'es': 'Proteína',
        'de': 'Eiweiß',
      });

  String get carbs => _t({
        'en': 'Carbs',
        'pl': 'Węglowodany',
        'nl': 'Koolhydraten',
        'es': 'Carbohidratos',
        'de': 'Kohlenhydrate',
      });

  String get fat => _t({
        'en': 'Fat',
        'pl': 'Tłuszcz',
        'nl': 'Vet',
        'es': 'Grasa',
        'de': 'Fett',
      });

  String get fiber => _t({
        'en': 'Fiber',
        'pl': 'Błonnik',
        'nl': 'Vezels',
        'es': 'Fibra',
        'de': 'Ballaststoffe',
      });

  String get sugar => _t({
        'en': 'Sugar',
        'pl': 'Cukier',
        'nl': 'Suiker',
        'es': 'Azúcar',
        'de': 'Zucker',
      });

  // ── Settings ──

  String get account => _t({
        'en': 'Account',
        'pl': 'Konto',
        'nl': 'Account',
        'es': 'Cuenta',
        'de': 'Konto',
      });

  String get appearance => _t({
        'en': 'Appearance',
        'pl': 'Wygląd',
        'nl': 'Weergave',
        'es': 'Apariencia',
        'de': 'Darstellung',
      });

  String get privacy => _t({
        'en': 'Privacy',
        'pl': 'Prywatność',
        'nl': 'Privacy',
        'es': 'Privacidad',
        'de': 'Datenschutz',
      });

  String get evaluation => _t({
        'en': 'Evaluation',
        'pl': 'Ewaluacja',
        'nl': 'Evaluatie',
        'es': 'Evaluación',
        'de': 'Auswertung',
      });

  String get profile => _t({
        'en': 'Profile',
        'pl': 'Profil',
        'nl': 'Profiel',
        'es': 'Perfil',
        'de': 'Profil',
      });

  String get yourName => _t({
        'en': 'Your name',
        'pl': 'Twoje imię',
        'nl': 'Je naam',
        'es': 'Tu nombre',
        'de': 'Dein Name',
      });

  String get dailyCalorieGoal => _t({
        'en': 'Daily calorie goal (kcal)',
        'pl': 'Dzienny cel kaloryczny (kcal)',
        'nl': 'Dagelijks caloriedoel (kcal)',
        'es': 'Objetivo calórico diario (kcal)',
        'de': 'Tägliches Kalorienziel (kcal)',
      });

  String get saveChanges => _t({
        'en': 'Save Changes',
        'pl': 'Zapisz zmiany',
        'nl': 'Wijzigingen opslaan',
        'es': 'Guardar cambios',
        'de': 'Änderungen speichern',
      });

  String get settingsSaved => _t({
        'en': 'Settings saved',
        'pl': 'Ustawienia zapisane',
        'nl': 'Instellingen opgeslagen',
        'es': 'Ajustes guardados',
        'de': 'Einstellungen gespeichert',
      });

  String get nutritionGoal => _t({
        'en': 'Nutrition Goal',
        'pl': 'Cel żywieniowy',
        'nl': 'Voedingsdoel',
        'es': 'Objetivo nutricional',
        'de': 'Ernährungsziel',
      });

  String get dailyMacroTargets => _t({
        'en': 'Daily Macro Targets',
        'pl': 'Dzienne cele makro',
        'nl': 'Dagelijkse macrodoelen',
        'es': 'Objetivos de macros diarios',
        'de': 'Tägliche Makroziele',
      });

  String get waterGoal => _t({
        'en': 'Water Goal',
        'pl': 'Cel nawodnienia',
        'nl': 'Waterdoel',
        'es': 'Objetivo de agua',
        'de': 'Wasserziel',
      });

  String get dailyWaterGoalMl => _t({
        'en': 'Daily water goal (ml)',
        'pl': 'Dzienny cel wody (ml)',
        'nl': 'Dagelijks waterdoel (ml)',
        'es': 'Objetivo de agua diario (ml)',
        'de': 'Tägliches Wasserziel (ml)',
      });

  String get language => _t({
        'en': 'Language',
        'pl': 'Język',
        'nl': 'Taal',
        'es': 'Idioma',
        'de': 'Sprache',
      });

  String get database => _t({
        'en': 'Database',
        'pl': 'Baza danych',
        'nl': 'Database',
        'es': 'Base de datos',
        'de': 'Datenbank',
      });

  String get foodDatabaseEntries => _t({
        'en': 'Food database entries',
        'pl': 'Wpisy w bazie żywności',
        'nl': 'Voedingsdatabase-items',
        'es': 'Entradas en la base de alimentos',
        'de': 'Lebensmittel-Datenbankeinträge',
      });

  String get browseFoodDatabase => _t({
        'en': 'Browse Food Database',
        'pl': 'Przeglądaj bazę żywności',
        'nl': 'Voedingsdatabase bekijken',
        'es': 'Explorar base de alimentos',
        'de': 'Lebensmittel-Datenbank durchsuchen',
      });

  String get reminders => _t({
        'en': 'Reminders',
        'pl': 'Przypomnienia',
        'nl': 'Herinneringen',
        'es': 'Recordatorios',
        'de': 'Erinnerungen',
      });

  String get vacationMode => _t({
        'en': 'Vacation Mode',
        'pl': 'Tryb wakacyjny',
        'nl': 'Vakantiemodus',
        'es': 'Modo vacaciones',
        'de': 'Urlaubsmodus',
      });

  String get vacationModeDesc => _t({
        'en': 'Keeps your streak alive while you\'re away.',
        'pl': 'Utrzymuje passę, gdy jesteś na urlopie.',
        'nl': 'Houdt je reeks intact terwijl je weg bent.',
        'es': 'Mantiene tu racha mientras estás fuera.',
        'de': 'Hält deine Serie aufrecht, während du weg bist.',
      });

  String get textSize => _t({
        'en': 'Text Size',
        'pl': 'Rozmiar tekstu',
        'nl': 'Tekstgrootte',
        'es': 'Tamaño de texto',
        'de': 'Textgröße',
      });

  String get mascot => _t({
        'en': 'Mascot',
        'pl': 'Maskotka',
        'nl': 'Mascotte',
        'es': 'Mascota',
        'de': 'Maskottchen',
      });

  String get appColorTheme => _t({
        'en': 'App Color Theme',
        'pl': 'Motyw kolorystyczny',
        'nl': 'App kleurthema',
        'es': 'Tema de color de la app',
        'de': 'App-Farbthema',
      });

  String get pickAccentColor => _t({
        'en': 'Pick an accent color for the whole app',
        'pl': 'Wybierz kolor akcentu dla całej aplikacji',
        'nl': 'Kies een accentkleur voor de hele app',
        'es': 'Elige un color de acento para toda la app',
        'de': 'Wähle eine Akzentfarbe für die ganze App',
      });

  // ── Scan ──

  String get startScan => _t({
        'en': 'Start Scan',
        'pl': 'Rozpocznij skanowanie',
        'nl': 'Start scan',
        'es': 'Iniciar escaneo',
        'de': 'Scan starten',
      });

  String get scanning => _t({
        'en': 'Scanning...',
        'pl': 'Skanowanie...',
        'nl': 'Scannen...',
        'es': 'Escaneando...',
        'de': 'Scannen...',
      });

  String get scanComplete => _t({
        'en': 'Scan complete!',
        'pl': 'Skanowanie zakończone!',
        'nl': 'Scan voltooid!',
        'es': '¡Escaneo completado!',
        'de': 'Scan abgeschlossen!',
      });

  // ── Voice / AI Speech ──

  String get voiceEntry => _t({
        'en': 'Voice Entry',
        'pl': 'Wpis głosowy',
        'nl': 'Spraakinvoer',
        'es': 'Entrada por voz',
        'de': 'Spracheingabe',
      });

  String get tapToSpeak => _t({
        'en': 'Tap to speak',
        'pl': 'Dotknij, aby mówić',
        'nl': 'Tik om te spreken',
        'es': 'Toca para hablar',
        'de': 'Tippen zum Sprechen',
      });

  String get listening => _t({
        'en': 'Listening...',
        'pl': 'Słucham...',
        'nl': 'Luisteren...',
        'es': 'Escuchando...',
        'de': 'Hören...',
      });

  String get speakYourFood => _t({
        'en':
            'Tell me what you ate. For example: "200 grams of chicken and a banana"',
        'pl':
            'Powiedz mi, co jadłeś. Na przykład: "200 gramów kurczaka i banana"',
        'nl':
            'Vertel me wat je hebt gegeten. Bijvoorbeeld: "200 gram kip en een banaan"',
        'es':
            'Dime qué comiste. Por ejemplo: "200 gramos de pollo y un plátano"',
        'de':
            'Sag mir, was du gegessen hast. Zum Beispiel: "200 Gramm Hähnchen und eine Banane"',
      });

  // ── Body Map ──

  String get noData => _t({
        'en': 'No data',
        'pl': 'Brak danych',
        'nl': 'Geen data',
        'es': 'Sin datos',
        'de': 'Keine Daten',
      });

  String get low => _t({
        'en': 'Low',
        'pl': 'Niski',
        'nl': 'Laag',
        'es': 'Bajo',
        'de': 'Niedrig',
      });

  String get fair => _t({
        'en': 'Fair',
        'pl': 'Dobry',
        'nl': 'Redelijk',
        'es': 'Regular',
        'de': 'Ausreichend',
      });

  String get good => _t({
        'en': 'Good',
        'pl': 'Dobrze',
        'nl': 'Goed',
        'es': 'Bueno',
        'de': 'Gut',
      });

  String get goalMet => _t({
        'en': 'Goal ✓',
        'pl': 'Cel ✓',
        'nl': 'Doel ✓',
        'es': 'Meta ✓',
        'de': 'Ziel ✓',
      });

  String get over => _t({
        'en': 'Over!',
        'pl': 'Za dużo!',
        'nl': 'Te veel!',
        'es': '¡Exceso!',
        'de': 'Zu viel!',
      });

  // ── Meal Planner ──

  String get weeklyMealPlanner => _t({
        'en': 'Weekly Meal Planner',
        'pl': 'Tygodniowy planer posiłków',
        'nl': 'Wekelijkse maaltijdplanner',
        'es': 'Planificador semanal de comidas',
        'de': 'Wöchentlicher Mahlzeitenplaner',
      });

  String get clearWeek => _t({
        'en': 'Clear Week',
        'pl': 'Wyczyść tydzień',
        'nl': 'Week wissen',
        'es': 'Borrar semana',
        'de': 'Woche löschen',
      });

  String personalisedFor(String goal) => _t({
        'en': 'Personalised for $goal',
        'pl': 'Spersonalizowane dla: $goal',
        'nl': 'Gepersonaliseerd voor $goal',
        'es': 'Personalizado para $goal',
        'de': 'Personalisiert für $goal',
      });

  String get mealPlannerInstructions => _t({
        'en':
            'Toggle meal slots to plan your week. Tap shuffle to get a new recipe.',
        'pl':
            'Włącz posiłki, aby zaplanować tydzień. Dotknij mieszania, aby dostać nowy przepis.',
        'nl':
            'Schakel maaltijden in om je week te plannen. Tik op schudden voor een nieuw recept.',
        'es':
            'Activa comidas para planificar tu semana. Toca mezclar para obtener otra receta.',
        'de':
            'Aktiviere Mahlzeiten, um deine Woche zu planen. Tippe auf Mischen für ein neues Rezept.',
      });

  String get generateGroceryList => _t({
        'en': 'Generate Grocery List',
        'pl': 'Generuj listę zakupów',
        'nl': 'Boodschappenlijst genereren',
        'es': 'Generar lista de compras',
        'de': 'Einkaufsliste erstellen',
      });

  String get tapToAddMeals => _t({
        'en': 'Tap to add meals',
        'pl': 'Dotknij, aby dodać posiłki',
        'nl': 'Tik om maaltijden toe te voegen',
        'es': 'Toca para agregar comidas',
        'de': 'Tippen um Mahlzeiten hinzuzufügen',
      });

  String get findingRecipe => _t({
        'en': 'Finding recipe…',
        'pl': 'Szukam przepisu…',
        'nl': 'Recept zoeken…',
        'es': 'Buscando receta…',
        'de': 'Rezept suchen…',
      });

  String get portion => _t({
        'en': 'portion',
        'pl': 'porcja',
        'nl': 'portie',
        'es': 'porción',
        'de': 'Portion',
      });

  String get mealPlanAutopilot => _t({
        'en': 'AI Planner',
        'pl': 'Planer AI',
        'nl': 'AI-planner',
        'es': 'Planificador IA',
        'de': 'KI-Planer',
      });

  String get mealPlanAutopilotDone => _t({
        'en': 'Your week was planned with goal-matched meals.',
        'pl': 'Tydzień został zaplanowany posiłkami dopasowanymi do celu.',
        'nl': 'Je week is gepland met maaltijden die bij je doel passen.',
        'es': 'Tu semana se planificó con comidas según tu objetivo.',
        'de': 'Deine Woche wurde mit passenden Mahlzeiten geplant.',
      });

  String get pantryMode => _t({
        'en': 'Pantry Mode',
        'pl': 'Tryb spiżarni',
        'nl': 'Voorraadmodus',
        'es': 'Modo despensa',
        'de': 'Vorratsmodus',
      });

  String get managePantry => _t({
        'en': 'Manage Pantry',
        'pl': 'Zarządzaj spiżarnią',
        'nl': 'Voorraad beheren',
        'es': 'Gestionar despensa',
        'de': 'Vorrat verwalten',
      });

  String get pantryModeDescription => _t({
        'en':
            'Add ingredients you already have. Autopilot and Smart Swap can prefer recipes that use them.',
        'pl':
            'Dodaj składniki, które już masz. Autopilot i inteligentna zamiana mogą wybierać przepisy, które ich używają.',
        'nl':
            'Voeg ingrediënten toe die je al hebt. Autopilot en slimme wissels kunnen recepten met die ingrediënten voorrang geven.',
        'es':
            'Añade ingredientes que ya tienes. El piloto automático y los cambios inteligentes pueden priorizar recetas que los usen.',
        'de':
            'Füge Zutaten hinzu, die du schon hast. Autopilot und intelligente Wechsel können Rezepte damit bevorzugen.',
      });

  String get addPantryItem => _t({
        'en': 'Add ingredient you have',
        'pl': 'Dodaj składnik, który masz',
        'nl': 'Voeg ingrediënt toe dat je hebt',
        'es': 'Añade un ingrediente que tienes',
        'de': 'Vorhandene Zutat hinzufügen',
      });

  String pantryModeReadyHint(int count) => _t({
        'en':
            'Pantry Mode on — Autopilot will prioritise the $count ${count == 1 ? 'ingredient' : 'ingredients'} you have.',
        'pl':
            'Tryb spiżarni włączony — Autopilot będzie preferować $count ${count == 1 ? 'składnik' : 'składniki'}, które masz.',
        'nl':
            'Voorraadmodus aan — Autopilot geeft voorrang aan je $count ${count == 1 ? 'ingrediënt' : 'ingrediënten'}.',
        'es':
            'Modo despensa activado: el piloto automático priorizará los $count ${count == 1 ? 'ingrediente' : 'ingredientes'} que tienes.',
        'de':
            'Vorratsmodus an — Autopilot bevorzugt deine $count ${count == 1 ? 'Zutat' : 'Zutaten'}.',
      });

  String get pantryModeEmptyHint => _t({
        'en':
            'Add a few ingredients you already have so Autopilot can prioritise recipes that use them.',
        'pl':
            'Dodaj kilka składników, które już masz, aby Autopilot mógł preferować przepisy z nimi.',
        'nl':
            'Voeg een paar ingrediënten toe die je al hebt, zodat Autopilot recepten daarmee voorrang kan geven.',
        'es':
            'Añade algunos ingredientes que ya tienes para que el piloto automático priorice recetas que los usen.',
        'de':
            'Füge ein paar vorhandene Zutaten hinzu, damit der Autopilot Rezepte damit bevorzugen kann.',
      });

  String get emptyPantry => _t({
        'en': 'No pantry items yet.',
        'pl': 'Nie ma jeszcze składników w spiżarni.',
        'nl': 'Nog geen voorraaditems.',
        'es': 'Aún no hay ingredientes en la despensa.',
        'de': 'Noch keine Vorratsartikel.',
      });

  String get availableForPlanning => _t({
        'en': 'Available for planning',
        'pl': 'Dostępne do planowania',
        'nl': 'Beschikbaar voor planning',
        'es': 'Disponible para planificar',
        'de': 'Für Planung verfügbar',
      });

  String get hiddenFromPlanning => _t({
        'en': 'Hidden from planning',
        'pl': 'Ukryte przed planowaniem',
        'nl': 'Verborgen voor planning',
        'es': 'Oculto de la planificación',
        'de': 'Für Planung ausgeblendet',
      });

  String get smartSwap => _t({
        'en': 'AI Swap',
        'pl': 'Zamiana AI',
        'nl': 'AI-wissel',
        'es': 'Cambio IA',
        'de': 'KI-Tausch',
      });

  String get smartSwapSubtitle => _t({
        'en': 'Choose what should improve in this meal.',
        'pl': 'Wybierz, co ma się poprawić w tym posiłku.',
        'nl': 'Kies wat beter moet worden in deze maaltijd.',
        'es': 'Elige qué debería mejorar en esta comida.',
        'de': 'Wähle, was an dieser Mahlzeit besser werden soll.',
      });

  String smartSwapIntentLabel(String key) {
    switch (key) {
      case 'balanced':
        return _t({
          'en': 'More balanced',
          'pl': 'Bardziej zbilansowane',
          'nl': 'Meer in balans',
          'es': 'Más equilibrado',
          'de': 'Ausgewogener',
        });
      case 'higherProtein':
        return _t({
          'en': 'Higher protein',
          'pl': 'Więcej białka',
          'nl': 'Meer eiwit',
          'es': 'Más proteína',
          'de': 'Mehr Eiweiß',
        });
      case 'lowerCarb':
        return _t({
          'en': 'Lower carb',
          'pl': 'Mniej węglowodanów',
          'nl': 'Minder koolhydraten',
          'es': 'Menos carbohidratos',
          'de': 'Weniger Kohlenhydrate',
        });
      case 'faster':
        return _t({
          'en': 'Faster to cook',
          'pl': 'Szybsze w gotowaniu',
          'nl': 'Sneller te maken',
          'es': 'Más rápido de preparar',
          'de': 'Schneller gekocht',
        });
      case 'pantryFirst':
        return _t({
          'en': 'Use pantry first',
          'pl': 'Najpierw spiżarnia',
          'nl': 'Eerst voorraad gebruiken',
          'es': 'Usar despensa primero',
          'de': 'Vorrat zuerst nutzen',
        });
    }
    return key;
  }

  String smartSwapIntentDescription(String key) {
    switch (key) {
      case 'balanced':
        return _t({
          'en': 'Keeps calories and macros closer to the day target.',
          'pl': 'Utrzymuje kalorie i makro bliżej dziennego celu.',
          'nl': 'Houdt calorieën en macro’s dichter bij je dagdoel.',
          'es': 'Mantiene calorías y macros cerca del objetivo diario.',
          'de': 'Hält Kalorien und Makros näher am Tagesziel.',
        });
      case 'higherProtein':
        return _t({
          'en': 'Prioritizes recipes with stronger protein density.',
          'pl': 'Priorytet dla przepisów z większą gęstością białka.',
          'nl': 'Geeft voorkeur aan recepten met meer eiwitdichtheid.',
          'es': 'Prioriza recetas con mayor densidad de proteína.',
          'de': 'Bevorzugt Rezepte mit höherer Eiweißdichte.',
        });
      case 'lowerCarb':
        return _t({
          'en': 'Finds a steadier lower-carb option for the same slot.',
          'pl': 'Szuka spokojniejszej opcji z mniejszą ilością węglowodanów.',
          'nl': 'Zoekt een stabielere optie met minder koolhydraten.',
          'es': 'Busca una opción más estable y baja en carbohidratos.',
          'de': 'Findet eine stabilere Option mit weniger Kohlenhydraten.',
        });
      case 'faster':
        return _t({
          'en': 'Prefers shorter prep and cook times.',
          'pl': 'Preferuje krótsze przygotowanie i gotowanie.',
          'nl': 'Geeft voorkeur aan kortere bereidings- en kooktijd.',
          'es': 'Prefiere menor tiempo de preparación y cocción.',
          'de': 'Bevorzugt kürzere Vorbereitungs- und Kochzeit.',
        });
      case 'pantryFirst':
        return _t({
          'en': 'Boosts recipes that use ingredients you marked available.',
          'pl': 'Premiuje przepisy ze składnikami oznaczonymi jako dostępne.',
          'nl': 'Geeft recepten met beschikbare ingrediënten extra gewicht.',
          'es': 'Impulsa recetas que usan ingredientes marcados disponibles.',
          'de': 'Bevorzugt Rezepte mit als verfügbar markierten Zutaten.',
        });
    }
    return key;
  }

  String get foodScore => _t({
        'en': 'Food score',
        'pl': 'Ocena jedzenia',
        'nl': 'Voedingsscore',
        'es': 'Puntuación del alimento',
        'de': 'Lebensmittelbewertung',
      });

  String get whyThisScore => _t({
        'en': 'Why this score',
        'pl': 'Skąd ta ocena',
        'nl': 'Waarom deze score',
        'es': 'Por qué esta puntuación',
        'de': 'Warum diese Bewertung',
      });

  String foodScoreTitle(String key) {
    switch (key) {
      case 'excellentFit':
        return _t({
          'en': 'Excellent fit',
          'pl': 'Świetne dopasowanie',
          'nl': 'Uitstekende keuze',
          'es': 'Excelente ajuste',
          'de': 'Sehr gute Wahl',
        });
      case 'strongChoice':
        return _t({
          'en': 'Strong choice',
          'pl': 'Mocny wybór',
          'nl': 'Sterke keuze',
          'es': 'Buena elección',
          'de': 'Starke Wahl',
        });
      case 'usefulWithBalance':
        return _t({
          'en': 'Useful with balance',
          'pl': 'Dobre z balansem',
          'nl': 'Nuttig met balans',
          'es': 'Útil con equilibrio',
          'de': 'Gut mit Ausgleich',
        });
      case 'needsBalancing':
        return _t({
          'en': 'Needs balancing',
          'pl': 'Wymaga zbalansowania',
          'nl': 'Heeft balans nodig',
          'es': 'Necesita equilibrio',
          'de': 'Braucht Ausgleich',
        });
    }
    return key;
  }

  String foodScoreReason(String key) {
    switch (key) {
      case 'highProtein':
        return _t({
          'en': 'High protein supports fullness and lean mass.',
          'pl': 'Wysokie białko wspiera sytość i masę mięśniową.',
          'nl': 'Veel eiwit ondersteunt verzadiging en vetvrije massa.',
          'es': 'La proteína alta ayuda a la saciedad y masa magra.',
          'de': 'Viel Eiweiß unterstützt Sättigung und fettfreie Masse.',
        });
      case 'usefulProtein':
        return _t({
          'en': 'Provides a useful protein contribution.',
          'pl': 'Dostarcza sensowną ilość białka.',
          'nl': 'Levert een nuttige eiwitbijdrage.',
          'es': 'Aporta una cantidad útil de proteína.',
          'de': 'Liefert einen nützlichen Eiweißbeitrag.',
        });
      case 'highFiber':
        return _t({
          'en': 'High fiber supports digestion and steadier glucose.',
          'pl': 'Wysoki błonnik wspiera trawienie i stabilniejszą glukozę.',
          'nl':
              'Veel vezels ondersteunen spijsvertering en stabielere glucose.',
          'es': 'La fibra alta ayuda a digestión y glucosa más estable.',
          'de':
              'Viele Ballaststoffe unterstützen Verdauung und stabilere Glukose.',
        });
      case 'meaningfulFiber':
        return _t({
          'en': 'Adds meaningful fiber to the meal.',
          'pl': 'Dodaje do posiłku sensowną ilość błonnika.',
          'nl': 'Voegt merkbaar vezels toe aan de maaltijd.',
          'es': 'Añade fibra relevante a la comida.',
          'de': 'Fügt der Mahlzeit relevante Ballaststoffe hinzu.',
        });
      case 'highSugar':
        return _t({
          'en': 'High sugar can make the meal less steady.',
          'pl': 'Wysoki cukier może obniżyć stabilność posiłku.',
          'nl': 'Veel suiker kan de maaltijd minder stabiel maken.',
          'es': 'El azúcar alto puede hacer la comida menos estable.',
          'de': 'Viel Zucker kann die Mahlzeit weniger stabil machen.',
        });
      case 'moderateSugar':
        return _t({
          'en': 'Moderate sugar: pair with protein or fiber.',
          'pl': 'Umiarkowany cukier: połącz z białkiem lub błonnikiem.',
          'nl': 'Matige suiker: combineer met eiwit of vezels.',
          'es': 'Azúcar moderado: combínalo con proteína o fibra.',
          'de': 'Mäßiger Zucker: mit Eiweiß oder Ballaststoffen kombinieren.',
        });
      case 'highSaturatedFat':
        return _t({
          'en': 'Saturated fat is high for frequent choices.',
          'pl': 'Tłuszcz nasycony jest wysoki jak na częsty wybór.',
          'nl': 'Verzadigd vet is hoog voor een frequente keuze.',
          'es': 'La grasa saturada es alta para una opción frecuente.',
          'de': 'Gesättigte Fette sind hoch für eine häufige Wahl.',
        });
      case 'highSodium':
        return _t({
          'en': 'Sodium is high; balance the day with lower-salt foods.',
          'pl': 'Sód jest wysoki; zbalansuj dzień mniej słonym jedzeniem.',
          'nl': 'Natrium is hoog; balanceer de dag met minder zout.',
          'es': 'El sodio es alto; equilibra el día con menos sal.',
          'de': 'Natrium ist hoch; gleiche den Tag mit weniger Salz aus.',
        });
      case 'energyDenseLowSatiety':
        return _t({
          'en': 'Energy dense without much protein or fiber.',
          'pl': 'Wysoka gęstość energii bez dużej ilości białka lub błonnika.',
          'nl': 'Energierijk zonder veel eiwit of vezels.',
          'es': 'Denso en energía sin mucha proteína o fibra.',
          'de': 'Energiedicht ohne viel Eiweiß oder Ballaststoffe.',
        });
      case 'diabetesCarbFiber':
        return _t({
          'en': 'For diabetes, carbs are better when fiber is higher.',
          'pl':
              'Przy cukrzycy węglowodany są korzystniejsze z większą ilością błonnika.',
          'nl': 'Bij diabetes zijn koolhydraten beter met meer vezels.',
          'es': 'Para diabetes, los carbohidratos van mejor con más fibra.',
          'de':
              'Bei Diabetes sind Kohlenhydrate mit mehr Ballaststoffen besser.',
        });
      case 'ketoHighCarb':
        return _t({
          'en': 'Carbs are high for keto.',
          'pl': 'Węglowodany są wysokie jak na keto.',
          'nl': 'Koolhydraten zijn hoog voor keto.',
          'es': 'Los carbohidratos son altos para keto.',
          'de': 'Kohlenhydrate sind hoch für Keto.',
        });
      case 'weightLossSatiety':
        return _t({
          'en': 'Helpful for weight loss because it supports satiety.',
          'pl': 'Pomocne przy odchudzaniu, bo wspiera sytość.',
          'nl': 'Helpt bij gewichtsverlies doordat het verzadigt.',
          'es': 'Ayuda a perder peso porque favorece saciedad.',
          'de': 'Hilfreich beim Abnehmen, weil es sättigt.',
        });
      case 'muscleProteinFit':
        return _t({
          'en': 'Strong fit for muscle growth protein targets.',
          'pl': 'Dobre dopasowanie do celów białka na budowę mięśni.',
          'nl': 'Past goed bij eiwitdoelen voor spiergroei.',
          'es': 'Encaja bien con objetivos de proteína para músculo.',
          'de': 'Passt gut zu Eiweißzielen für Muskelaufbau.',
        });
      case 'balancedContext':
        return _t({
          'en': 'Balanced everyday food; portion and plate context matter.',
          'pl':
              'Zbalansowane codzienne jedzenie; liczy się porcja i cały talerz.',
          'nl': 'Gebalanceerde dagelijkse keuze; portie en bordcontext tellen.',
          'es':
              'Alimento cotidiano equilibrado; importan porción y plato completo.',
          'de': 'Ausgewogene Alltagswahl; Portion und Tellerkontext zählen.',
        });
    }
    return key;
  }

  String get manualRecipePicker => _t({
        'en': 'Browse all matching recipes manually.',
        'pl': 'Przejrzyj ręcznie wszystkie pasujące przepisy.',
        'nl': 'Blader handmatig door alle passende recepten.',
        'es': 'Explora manualmente todas las recetas compatibles.',
        'de': 'Alle passenden Rezepte manuell durchsuchen.',
      });

  // ── Grocery ──

  String get editGroceryItem => _t({
        'en': 'Edit item',
        'pl': 'Edytuj pozycję',
        'nl': 'Item bewerken',
        'es': 'Editar artículo',
        'de': 'Artikel bearbeiten',
      });

  String get itemName => _t({
        'en': 'Item name',
        'pl': 'Nazwa pozycji',
        'nl': 'Itemnaam',
        'es': 'Nombre del artículo',
        'de': 'Artikelname',
      });

  String get quantityLabel => _t({
        'en': 'Quantity',
        'pl': 'Ilość',
        'nl': 'Aantal',
        'es': 'Cantidad',
        'de': 'Menge',
      });

  String get unitOptional => _t({
        'en': 'Unit (optional)',
        'pl': 'Jednostka (opcjonalnie)',
        'nl': 'Eenheid (optioneel)',
        'es': 'Unidad (opcional)',
        'de': 'Einheit (optional)',
      });

  String get addGroceryItem => _t({
        'en': 'Add Grocery Item',
        'pl': 'Dodaj pozycję',
        'nl': 'Boodschap toevoegen',
        'es': 'Agregar artículo',
        'de': 'Artikel hinzufügen',
      });

  String groceryCategoryLabel(String key) {
    switch (key) {
      case 'Fruits':
        return _t({'en': 'Fruits', 'pl': 'Owoce', 'nl': 'Fruit', 'es': 'Frutas', 'de': 'Obst'});
      case 'Vegetables':
        return _t({'en': 'Vegetables', 'pl': 'Warzywa', 'nl': 'Groenten', 'es': 'Verduras', 'de': 'Gemüse'});
      case 'Protein':
        return _t({'en': 'Protein', 'pl': 'Białko', 'nl': 'Eiwitten', 'es': 'Proteína', 'de': 'Protein'});
      case 'Dairy':
        return _t({'en': 'Dairy', 'pl': 'Nabiał', 'nl': 'Zuivel', 'es': 'Lácteos', 'de': 'Milchprodukte'});
      case 'Grains':
        return _t({'en': 'Grains', 'pl': 'Zboża', 'nl': 'Granen', 'es': 'Cereales', 'de': 'Getreide'});
      case 'Snacks':
        return _t({'en': 'Snacks', 'pl': 'Przekąski', 'nl': 'Snacks', 'es': 'Aperitivos', 'de': 'Snacks'});
      case 'Drinks':
        return _t({'en': 'Drinks', 'pl': 'Napoje', 'nl': 'Dranken', 'es': 'Bebidas', 'de': 'Getränke'});
      case 'Other':
      default:
        return _t({'en': 'Other', 'pl': 'Inne', 'nl': 'Overig', 'es': 'Otros', 'de': 'Sonstiges'});
    }
  }

  String get deleteEntireList => _t({
        'en': 'Delete entire list?',
        'pl': 'Usunąć całą listę?',
        'nl': 'Hele lijst verwijderen?',
        'es': '¿Eliminar toda la lista?',
        'de': 'Ganze Liste löschen?',
      });

  String get deleteAll => _t({
        'en': 'Delete all',
        'pl': 'Usuń wszystko',
        'nl': 'Alles verwijderen',
        'es': 'Eliminar todo',
        'de': 'Alle löschen',
      });

  String get smartGrocerySuggestions => _t({
        'en': 'Smart Grocery Suggestions',
        'pl': 'Inteligentne sugestie zakupów',
        'nl': 'Slimme boodschappensuggesties',
        'es': 'Sugerencias inteligentes de compra',
        'de': 'Clevere Einkaufsvorschläge',
      });

  String get basedOnMealHistory => _t({
        'en': 'Based on your meal history',
        'pl': 'Na podstawie historii posiłków',
        'nl': 'Op basis van je maaltijdgeschiedenis',
        'es': 'Según tu historial de comidas',
        'de': 'Basierend auf deinem Mahlzeitenverlauf',
      });

  String get howOftenShop => _t({
        'en': 'How often do you shop?',
        'pl': 'Jak często robisz zakupy?',
        'nl': 'Hoe vaak doe je boodschappen?',
        'es': '¿Con qué frecuencia compras?',
        'de': 'Wie oft kaufst du ein?',
      });

  String timesPerWeek(int n) => _t({
        'en': '${n}x/week',
        'pl': '${n}x/tydz.',
        'nl': '${n}x/week',
        'es': '${n}x/semana',
        'de': '${n}x/Woche',
      });

  String get noMealHistoryYet => _t({
        'en': 'No meal history yet',
        'pl': 'Brak historii posiłków',
        'nl': 'Nog geen maaltijdgeschiedenis',
        'es': 'Aún no hay historial de comidas',
        'de': 'Noch kein Mahlzeitenverlauf',
      });

  String get stockUpHint => _t({
        'en': 'You often eat these — stock up!',
        'pl': 'Często to jesz — zrób zapasy!',
        'nl': 'Dit eet je vaak — sla in!',
        'es': 'Comes esto a menudo — ¡abastécete!',
        'de': 'Das isst du oft — leg dir einen Vorrat an!',
      });

  String suggestedQtyLabel(String category, int qty) => _t({
        'en': '$category • suggested qty: $qty',
        'pl': '$category • sugerowana ilość: $qty',
        'nl': '$category • voorgestelde hoeveelheid: $qty',
        'es': '$category • cantidad sugerida: $qty',
        'de': '$category • empfohlene Menge: $qty',
      });

  String get scanningIngredients => _t({
        'en': 'Scanning your ingredients…',
        'pl': 'Skanowanie składników…',
        'nl': 'Je ingrediënten scannen…',
        'es': 'Escaneando tus ingredientes…',
        'de': 'Zutaten werden gescannt…',
      });

  String get analyzingFoodTextQty => _t({
        'en': 'Analyzing food, text and quantities…',
        'pl': 'Analiza jedzenia, tekstu i ilości…',
        'nl': 'Eten, tekst en hoeveelheden analyseren…',
        'es': 'Analizando comida, texto y cantidades…',
        'de': 'Essen, Text und Mengen werden analysiert…',
      });

  String foundIngredients(int n) => _t({
        'en': 'Found $n ingredient${n > 1 ? 's' : ''} you already have!',
        'pl': 'Znaleziono $n składnik(i), które już masz!',
        'nl': '$n ingrediënt${n > 1 ? 'en' : ''} gevonden die je al hebt!',
        'es': '¡Se encontró $n ingrediente${n > 1 ? 's' : ''} que ya tienes!',
        'de': '$n Zutat${n > 1 ? 'en' : ''} gefunden, die du schon hast!',
      });

  String get noMatchingGroceryItems => _t({
        'en': 'No matching grocery items found in the photo. Try scanning closer to the items.',
        'pl': 'Nie znaleziono pasujących produktów na zdjęciu. Spróbuj zeskanować bliżej.',
        'nl': 'Geen overeenkomende boodschappen gevonden op de foto. Scan dichter bij de items.',
        'es': 'No se encontraron artículos coincidentes en la foto. Intenta escanear más cerca.',
        'de': 'Keine passenden Artikel im Foto gefunden. Versuche, näher zu scannen.',
      });

  String get couldNotAnalyzePhoto => _t({
        'en': 'Could not analyze the photo.',
        'pl': 'Nie udało się przeanalizować zdjęcia.',
        'nl': 'Kon de foto niet analyseren.',
        'es': 'No se pudo analizar la foto.',
        'de': 'Foto konnte nicht analysiert werden.',
      });

  String get weeklyGroceryList => _t({
        'en': 'Weekly Grocery List',
        'pl': 'Tygodniowa lista zakupów',
        'nl': 'Wekelijkse boodschappenlijst',
        'es': 'Lista de compras semanal',
        'de': 'Wöchentliche Einkaufsliste',
      });

  String get addToGroceryList => _t({
        'en': 'Add to Grocery List',
        'pl': 'Dodaj do listy zakupów',
        'nl': 'Toevoegen aan boodschappenlijst',
        'es': 'Agregar a la lista de compras',
        'de': 'Zur Einkaufsliste hinzufügen',
      });

  String get scanReceipt => _t({
        'en': 'Scan Receipt / Fridge',
        'pl': 'Skanuj paragon / lodówkę',
        'nl': 'Scan bon / koelkast',
        'es': 'Escanear recibo / nevera',
        'de': 'Kassenbon / Kühlschrank scannen',
      });

  // ── Misc ──

  String get ingredients => _t({
        'en': 'Ingredients',
        'pl': 'Składniki',
        'nl': 'Ingrediënten',
        'es': 'Ingredientes',
        'de': 'Zutaten',
      });

  String get steps => _t({
        'en': 'Steps',
        'pl': 'Kroki',
        'nl': 'Stappen',
        'es': 'Pasos',
        'de': 'Schritte',
      });

  String get servings => _t({
        'en': 'Servings',
        'pl': 'Porcje',
        'nl': 'Porties',
        'es': 'Porciones',
        'de': 'Portionen',
      });

  String get minutes => _t({
        'en': 'min',
        'pl': 'min',
        'nl': 'min',
        'es': 'min',
        'de': 'min',
      });

  String get kcal => _t({
        'en': 'kcal',
        'pl': 'kcal',
        'nl': 'kcal',
        'es': 'kcal',
        'de': 'kcal',
      });

  String get perDay => _t({
        'en': '/ day',
        'pl': '/ dzień',
        'nl': '/ dag',
        'es': '/ día',
        'de': '/ Tag',
      });

  String get password => _t({
        'en': 'Password',
        'pl': 'Hasło',
        'nl': 'Wachtwoord',
        'es': 'Contraseña',
        'de': 'Passwort',
      });

  String get cloudSync => _t({
        'en': 'Cloud Sync',
        'pl': 'Synchronizacja chmury',
        'nl': 'Cloud synchronisatie',
        'es': 'Sincronización en la nube',
        'de': 'Cloud-Synchronisierung',
      });

  String get about => _t({
        'en': 'About',
        'pl': 'O aplikacji',
        'nl': 'Over',
        'es': 'Acerca de',
        'de': 'Über',
      });

  String get replayAppTour => _t({
        'en': 'Replay App Tour',
        'pl': 'Powtórz przewodnik',
        'nl': 'App-rondleiding opnieuw',
        'es': 'Repetir recorrido de la app',
        'de': 'App-Tour wiederholen',
      });

  String get replayAppTourSubtitle => _t({
        'en': 'Re-watch the guided feature tour',
        'pl': 'Obejrzyj ponownie przewodnik po funkcjach',
        'nl': 'Bekijk de rondleiding met functies opnieuw',
        'es': 'Vuelve a ver el recorrido guiado por funciones',
        'de': 'Geführte Funktions-Tour erneut ansehen',
      });

  String get replayScanTutorial => _t({
        'en': 'Replay Scan Tutorial',
        'pl': 'Powtórz samouczek skanowania',
        'nl': 'Scan-uitleg opnieuw',
        'es': 'Repetir tutorial de escaneo',
        'de': 'Scan-Anleitung wiederholen',
      });

  String get replayScanTutorialSubtitle => _t({
        'en': 'Show the scanner walkthrough again',
        'pl': 'Pokaż ponownie samouczek skanera',
        'nl': 'Toon de uitleg van de scanner opnieuw',
        'es': 'Muestra de nuevo la guía del escáner',
        'de': 'Die Scanner-Einführung erneut anzeigen',
      });

  String get dataAndPrivacy => _t({
        'en': 'Data & Privacy',
        'pl': 'Dane i prywatność',
        'nl': 'Gegevens en privacy',
        'es': 'Datos y privacidad',
        'de': 'Daten & Datenschutz',
      });

  String get evaluationTools => _t({
        'en': 'Evaluation Tools',
        'pl': 'Narzędzia oceny',
        'nl': 'Evaluatiehulpmiddelen',
        'es': 'Herramientas de evaluación',
        'de': 'Bewertungswerkzeuge',
      });

  String get debug => _t({
        'en': 'Debug',
        'pl': 'Debugowanie',
        'nl': 'Foutopsporing',
        'es': 'Depuración',
        'de': 'Fehlersuche',
      });

  String get dataStoredLocally => _t({
        'en':
            'All data is stored locally on your device. No data is sent to any server.',
        'pl':
            'Wszystkie dane są przechowywane lokalnie na Twoim urządzeniu. Żadne dane nie są wysyłane na serwer.',
        'nl':
            'Alle gegevens worden lokaal op je apparaat opgeslagen. Er worden geen gegevens naar een server gestuurd.',
        'es':
            'Todos los datos se almacenan localmente en tu dispositivo. No se envían datos a ningún servidor.',
        'de':
            'Alle Daten werden lokal auf deinem Gerät gespeichert. Es werden keine Daten an einen Server gesendet.',
      });

  String get storage => _t({
        'en': 'Storage',
        'pl': 'Pamięć',
        'nl': 'Opslag',
        'es': 'Almacenamiento',
        'de': 'Speicher',
      });

  String get onDeviceOnly => _t({
        'en': 'On-device only',
        'pl': 'Tylko na urządzeniu',
        'nl': 'Alleen op apparaat',
        'es': 'Solo en el dispositivo',
        'de': 'Nur auf dem Gerät',
      });

  String get noneLabel => _t({
        'en': 'None',
        'pl': 'Brak',
        'nl': 'Geen',
        'es': 'Ninguno',
        'de': 'Keine',
      });

  String get clearAllScanHistory => _t({
        'en': 'Clear All Scan History',
        'pl': 'Wyczyść całą historię skanów',
        'nl': 'Alle scangeschiedenis wissen',
        'es': 'Borrar todo el historial de escaneos',
        'de': 'Gesamten Scan-Verlauf löschen',
      });

  String get evaluationToolsDesc => _t({
        'en': 'Scientific evaluation tools for thesis research.',
        'pl': 'Naukowe narzędzia oceny do badań w pracy dyplomowej.',
        'nl': 'Wetenschappelijke evaluatiehulpmiddelen voor scriptieonderzoek.',
        'es':
            'Herramientas de evaluación científica para la investigación de tesis.',
        'de': 'Wissenschaftliche Bewertungswerkzeuge für die Abschlussarbeit.',
      });

  /// Localized text for the in-app guided tour. Order must match the
  /// structural step list in `app_tutorial_overlay.dart`.
  List<({String title, String body})> get tourSteps => [
        // 0 – Welcome
        (
          title: _t({
            'en': 'Welcome to Pixels to Macros! 👋',
            'pl': 'Witaj w Pixels to Macros! 👋',
            'nl': 'Welkom bij Pixels to Macros! 👋',
            'es': '¡Bienvenido a Pixels to Macros! 👋',
            'de': 'Willkommen bei Pixels to Macros! 👋',
          }),
          body: _t({
            'en': "Let's take a quick tour so you know where everything is.",
            'pl':
                'Zróbmy krótką wycieczkę, abyś wiedział, gdzie wszystko się znajduje.',
            'nl':
                'Laten we een korte rondleiding doen zodat je weet waar alles staat.',
            'es': 'Hagamos un recorrido rápido para que sepas dónde está todo.',
            'de': 'Machen wir eine kurze Tour, damit du weißt, wo alles ist.',
          }),
        ),
        // 1 – AI Scan
        (
          title: _t({
            'en': 'AI Scan 📷',
            'pl': 'Skan AI 📷',
            'nl': 'AI-scan 📷',
            'es': 'Escaneo IA 📷',
            'de': 'KI-Scan 📷',
          }),
          body: _t({
            'en':
                'Tap AI Scan to open the camera.\nPoint at your plate and get instant calories & macros!\nIncludes flashlight toggle and low-light warnings.',
            'pl':
                'Dotknij Skan AI, aby otworzyć aparat.\nWyceluj w talerz i natychmiast poznaj kalorie i makroskładniki!\nZawiera przełącznik latarki i ostrzeżenia o słabym oświetleniu.',
            'nl':
                'Tik op AI-scan om de camera te openen.\nRicht op je bord en krijg direct calorieën en macro\'s!\nMet zaklamp-schakelaar en waarschuwingen bij weinig licht.',
            'es':
                'Toca Escaneo IA para abrir la cámara.\n¡Apunta a tu plato y obtén calorías y macros al instante!\nIncluye linterna y avisos de poca luz.',
            'de':
                'Tippe auf KI-Scan, um die Kamera zu öffnen.\nRichte sie auf deinen Teller und erhalte sofort Kalorien & Makros!\nInklusive Taschenlampe und Warnungen bei wenig Licht.',
          }),
        ),
        // 2 – AI Speech
        (
          title: _t({
            'en': 'AI Speech 🎤',
            'pl': 'Mowa AI 🎤',
            'nl': 'AI-spraak 🎤',
            'es': 'Voz IA 🎤',
            'de': 'KI-Sprache 🎤',
          }),
          body: _t({
            'en':
                'Tap AI Speech to log food by voice in English.\nSay "200 grams of chicken and a banana" — it matches your food database automatically.',
            'pl':
                'Dotknij Mowa AI, aby zapisać jedzenie głosem po angielsku.\nPowiedz „200 gramów kurczaka i banan" — automatycznie dopasuje to do Twojej bazy żywności.',
            'nl':
                'Tik op AI-spraak om eten met je stem in het Engels te loggen.\nZeg "200 gram kip en een banaan" — het matcht automatisch met je voedingsdatabase.',
            'es':
                'Toca Voz IA para registrar comida por voz en inglés.\nDi "200 gramos de pollo y un plátano" — coincide con tu base de datos de alimentos automáticamente.',
            'de':
                'Tippe auf KI-Sprache, um Essen per Stimme auf Englisch zu erfassen.\nSage "200 Gramm Hähnchen und eine Banane" — es wird automatisch mit deiner Lebensmitteldatenbank abgeglichen.',
          }),
        ),
        // 3 – Manual Log
        (
          title: _t({
            'en': 'Log Food Manually ✏️',
            'pl': 'Zapisz jedzenie ręcznie ✏️',
            'nl': 'Eten handmatig loggen ✏️',
            'es': 'Registrar comida manualmente ✏️',
            'de': 'Essen manuell erfassen ✏️',
          }),
          body: _t({
            'en':
                'Search foods, pick from My Meals, or scan a barcode.\nBarcode scanning shows a health score (0-100) before logging.',
            'pl':
                'Wyszukaj produkty, wybierz z Moich Posiłków lub zeskanuj kod kreskowy.\nSkanowanie kodu pokazuje ocenę zdrowotności (0-100) przed zapisem.',
            'nl':
                'Zoek voedsel, kies uit Mijn Maaltijden of scan een barcode.\nBarcode scannen toont een gezondheidsscore (0-100) vóór het loggen.',
            'es':
                'Busca alimentos, elige de Mis Comidas o escanea un código de barras.\nEl escaneo muestra una puntuación de salud (0-100) antes de registrar.',
            'de':
                'Suche Lebensmittel, wähle aus Meine Mahlzeiten oder scanne einen Barcode.\nDer Barcode-Scan zeigt vor dem Erfassen einen Gesundheitswert (0-100).',
          }),
        ),
        // 4 – Daily Streak
        (
          title: _t({
            'en': 'Daily Streak 🔥',
            'pl': 'Dzienna seria 🔥',
            'nl': 'Dagelijkse reeks 🔥',
            'es': 'Racha diaria 🔥',
            'de': 'Tagesserie 🔥',
          }),
          body: _t({
            'en':
                'Your streak badge is now bigger and easier to spot. Keep logging daily to build momentum.',
            'pl':
                'Twoja odznaka serii jest teraz większa i łatwiejsza do zauważenia. Zapisuj codziennie, aby utrzymać tempo.',
            'nl':
                'Je reeks-badge is nu groter en beter zichtbaar. Blijf dagelijks loggen om je momentum op te bouwen.',
            'es':
                'Tu insignia de racha ahora es más grande y fácil de ver. Sigue registrando a diario para mantener el impulso.',
            'de':
                'Dein Serien-Abzeichen ist jetzt größer und leichter zu erkennen. Erfasse täglich weiter, um den Schwung zu halten.',
          }),
        ),
        // 5 – Body Map
        (
          title: _t({
            'en': 'Body Map 🫀',
            'pl': 'Mapa ciała 🫀',
            'nl': 'Lichaamskaart 🫀',
            'es': 'Mapa corporal 🫀',
            'de': 'Körperkarte 🫀',
          }),
          body: _t({
            'en':
                'Tap the body icon to open the anatomy map.\nBrain, eyes, heart, lungs, gut, bones, muscles, skin, blood, and immune regions are tappable and color-coded from your nutrient intake.',
            'pl':
                'Dotknij ikony ciała, aby otworzyć mapę anatomii.\nMózg, oczy, serce, płuca, jelita, kości, mięśnie, skóra, krew i obszary odpornościowe są klikalne i oznaczone kolorami na podstawie spożycia składników odżywczych.',
            'nl':
                'Tik op het lichaamspictogram om de anatomiekaart te openen.\nHersenen, ogen, hart, longen, darmen, botten, spieren, huid, bloed en immuungebieden zijn aantikbaar en kleurgecodeerd op basis van je voedingsinname.',
            'es':
                'Toca el icono del cuerpo para abrir el mapa anatómico.\nCerebro, ojos, corazón, pulmones, intestino, huesos, músculos, piel, sangre y zonas inmunitarias son tocables y con colores según tu ingesta de nutrientes.',
            'de':
                'Tippe auf das Körpersymbol, um die Anatomiekarte zu öffnen.\nGehirn, Augen, Herz, Lunge, Darm, Knochen, Muskeln, Haut, Blut und Immunbereiche sind antippbar und je nach Nährstoffzufuhr farblich markiert.',
          }),
        ),
        // 6 – Today's Nutrition
        (
          title: _t({
            'en': "Today's Nutrition 🌿",
            'pl': 'Dzisiejsze odżywianie 🌿',
            'nl': 'Voeding van vandaag 🌿',
            'es': 'Nutrición de hoy 🌿',
            'de': 'Heutige Ernährung 🌿',
          }),
          body: _t({
            'en':
                'The leaf icon opens your full nutrition dashboard with macros, vitamins, minerals, and the upgraded micronutrient wheel.',
            'pl':
                'Ikona liścia otwiera pełny pulpit odżywiania z makroskładnikami, witaminami, minerałami i ulepszonym kołem mikroskładników.',
            'nl':
                'Het bladpictogram opent je volledige voedingsdashboard met macro\'s, vitamines, mineralen en het verbeterde micronutriëntenwiel.',
            'es':
                'El icono de la hoja abre tu panel de nutrición completo con macros, vitaminas, minerales y la rueda de micronutrientes mejorada.',
            'de':
                'Das Blattsymbol öffnet dein vollständiges Ernährungs-Dashboard mit Makros, Vitaminen, Mineralien und dem verbesserten Mikronährstoff-Rad.',
          }),
        ),
        // 7 – Hydration Tracking
        (
          title: _t({
            'en': 'Hydration Tracking 💧',
            'pl': 'Śledzenie nawodnienia 💧',
            'nl': 'Hydratatie bijhouden 💧',
            'es': 'Seguimiento de hidratación 💧',
            'de': 'Flüssigkeits-Tracking 💧',
          }),
          body: _t({
            'en':
                'The hydration card tracks your daily water intake.\nUse the + drink button to log water, coffee, tea, and more.',
            'pl':
                'Karta nawodnienia śledzi dzienne spożycie wody.\nUżyj przycisku + napój, aby zapisać wodę, kawę, herbatę i więcej.',
            'nl':
                'De hydratatiekaart houdt je dagelijkse waterinname bij.\nGebruik de + drankknop om water, koffie, thee en meer te loggen.',
            'es':
                'La tarjeta de hidratación registra tu consumo diario de agua.\nUsa el botón + bebida para registrar agua, café, té y más.',
            'de':
                'Die Flüssigkeitskarte verfolgt deine tägliche Wasseraufnahme.\nNutze die + Getränk-Taste, um Wasser, Kaffee, Tee und mehr zu erfassen.',
          }),
        ),
        // 8 – Quick Add +200 ml
        (
          title: _t({
            'en': 'Quick Add +200 ml',
            'pl': 'Szybkie dodanie +200 ml',
            'nl': 'Snel toevoegen +200 ml',
            'es': 'Añadir rápido +200 ml',
            'de': 'Schnell +200 ml',
          }),
          body: _t({
            'en':
                'Need a fast water log? Tap +200 ml for one-tap hydration updates.',
            'pl':
                'Potrzebujesz szybkiego zapisu wody? Dotknij +200 ml, aby zaktualizować nawodnienie jednym dotknięciem.',
            'nl':
                'Snel water loggen? Tik op +200 ml voor hydratatie-updates met één tik.',
            'es':
                '¿Necesitas registrar agua rápido? Toca +200 ml para actualizar la hidratación con un toque.',
            'de':
                'Schnell Wasser erfassen? Tippe auf +200 ml für Flüssigkeits-Updates mit einem Tipp.',
          }),
        ),
        // 9 – Smart Nutrition Coach
        (
          title: _t({
            'en': 'Smart Nutrition Coach 🧠',
            'pl': 'Inteligentny trener żywienia 🧠',
            'nl': 'Slimme voedingscoach 🧠',
            'es': 'Coach de nutrición inteligente 🧠',
            'de': 'Smarter Ernährungscoach 🧠',
          }),
          body: _t({
            'en':
                'Recommendations now adapt to your goal and nutrient gaps (like low iron, vitamin D, B12, calcium, and more).',
            'pl':
                'Rekomendacje dostosowują się teraz do Twojego celu i niedoborów składników (jak niski poziom żelaza, witaminy D, B12, wapnia i innych).',
            'nl':
                'Aanbevelingen passen zich nu aan je doel en voedingstekorten aan (zoals weinig ijzer, vitamine D, B12, calcium en meer).',
            'es':
                'Las recomendaciones ahora se adaptan a tu objetivo y a tus carencias de nutrientes (como hierro, vitamina D, B12, calcio y más).',
            'de':
                'Empfehlungen passen sich jetzt deinem Ziel und Nährstofflücken an (z. B. wenig Eisen, Vitamin D, B12, Kalzium und mehr).',
          }),
        ),
        // 10 – Analytics
        (
          title: _t({
            'en': 'Analytics 📊',
            'pl': 'Analityka 📊',
            'nl': 'Analyse 📊',
            'es': 'Análisis 📊',
            'de': 'Analyse 📊',
          }),
          body: _t({
            'en': 'Track weekly & monthly calorie and macro trends here.',
            'pl':
                'Śledź tutaj tygodniowe i miesięczne trendy kalorii i makroskładników.',
            'nl':
                'Volg hier wekelijkse en maandelijkse calorie- en macrotrends.',
            'es':
                'Sigue aquí las tendencias semanales y mensuales de calorías y macros.',
            'de':
                'Verfolge hier wöchentliche und monatliche Kalorien- und Makrotrends.',
          }),
        ),
        // 11 – Recipes
        (
          title: _t({
            'en': 'Recipes 🍽️',
            'pl': 'Przepisy 🍽️',
            'nl': 'Recepten 🍽️',
            'es': 'Recetas 🍽️',
            'de': 'Rezepte 🍽️',
          }),
          body: _t({
            'en':
                'Browse recipes tailored to your nutrition goal and log meals quickly.',
            'pl':
                'Przeglądaj przepisy dopasowane do Twojego celu żywieniowego i szybko zapisuj posiłki.',
            'nl':
                'Blader door recepten op maat van je voedingsdoel en log maaltijden snel.',
            'es':
                'Explora recetas adaptadas a tu objetivo nutricional y registra comidas rápidamente.',
            'de':
                'Durchstöbere Rezepte passend zu deinem Ernährungsziel und erfasse Mahlzeiten schnell.',
          }),
        ),
        // 12 – Recipe Search
        (
          title: _t({
            'en': 'Recipe Search',
            'pl': 'Wyszukiwanie przepisów',
            'nl': 'Recept zoeken',
            'es': 'Buscar recetas',
            'de': 'Rezeptsuche',
          }),
          body: _t({
            'en':
                'Use search + goal filters to find recipes that match your needs faster.',
            'pl':
                'Użyj wyszukiwania i filtrów celu, aby szybciej znaleźć przepisy pasujące do Twoich potrzeb.',
            'nl':
                'Gebruik zoeken + doelfilters om sneller recepten te vinden die bij je passen.',
            'es':
                'Usa la búsqueda y los filtros de objetivo para encontrar recetas que se ajusten a ti más rápido.',
            'de':
                'Nutze Suche + Zielfilter, um schneller passende Rezepte zu finden.',
          }),
        ),
        // 13 – Grocery List
        (
          title: _t({
            'en': 'Grocery List 🛒',
            'pl': 'Lista zakupów 🛒',
            'nl': 'Boodschappenlijst 🛒',
            'es': 'Lista de compras 🛒',
            'de': 'Einkaufsliste 🛒',
          }),
          body: _t({
            'en':
                'Add items manually or get smart suggestions based on your scan history.',
            'pl':
                'Dodawaj produkty ręcznie lub otrzymuj inteligentne sugestie na podstawie historii skanów.',
            'nl':
                'Voeg items handmatig toe of krijg slimme suggesties op basis van je scangeschiedenis.',
            'es':
                'Añade artículos manualmente u obtén sugerencias inteligentes según tu historial de escaneos.',
            'de':
                'Füge Artikel manuell hinzu oder erhalte smarte Vorschläge aus deinem Scan-Verlauf.',
          }),
        ),
        // 14 – Planner
        (
          title: _t({
            'en': 'Planner 🗓️',
            'pl': 'Planner 🗓️',
            'nl': 'Planner 🗓️',
            'es': 'Planificador 🗓️',
            'de': 'Planer 🗓️',
          }),
          body: _t({
            'en':
                'Build a weekly meal plan from goal-matched recipes, then shuffle individual meals when you want more variety.',
            'pl':
                'Ułóż tygodniowy plan posiłków z przepisów pasujących do celu, a potem tasuj pojedyncze posiłki, gdy chcesz więcej różnorodności.',
            'nl':
                'Maak een weekmenu met recepten die bij je doel passen en shuffle losse maaltijden wanneer je meer variatie wilt.',
            'es':
                'Crea un plan semanal con recetas según tu objetivo y cambia comidas individuales cuando quieras más variedad.',
            'de':
                'Erstelle einen Wochenplan aus ziel passenden Rezepten und mische einzelne Mahlzeiten neu, wenn du mehr Abwechslung möchtest.',
          }),
        ),
        // 15 – Settings
        (
          title: _t({
            'en': 'Settings ⚙️',
            'pl': 'Ustawienia ⚙️',
            'nl': 'Instellingen ⚙️',
            'es': 'Ajustes ⚙️',
            'de': 'Einstellungen ⚙️',
          }),
          body: _t({
            'en':
                'Change your nutrition goal, color theme, mascot, text size, weekly badge recap, and more.\nDiabetes users can set ICR for bolus calculations.',
            'pl':
                'Zmień cel żywieniowy, motyw kolorystyczny, maskotkę, rozmiar tekstu, cotygodniowe podsumowanie odznak i więcej.\nUżytkownicy z cukrzycą mogą ustawić ICR do obliczeń bolusa.',
            'nl':
                'Wijzig je voedingsdoel, kleurthema, mascotte, tekstgrootte, wekelijkse badge-samenvatting en meer.\nDiabetesgebruikers kunnen ICR instellen voor bolusberekeningen.',
            'es':
                'Cambia tu objetivo nutricional, tema de color, mascota, tamaño de texto, resumen semanal de insignias y más.\nLos usuarios con diabetes pueden configurar el ICR para el cálculo de bolos.',
            'de':
                'Ändere dein Ernährungsziel, Farbthema, Maskottchen, Textgröße, wöchentliche Abzeichen-Zusammenfassung und mehr.\nDiabetes-Nutzer können das KE-Verhältnis (ICR) für Bolusberechnungen festlegen.',
          }),
        ),
        // 16 – Weekly Badges
        (
          title: _t({
            'en': 'Weekly Badges 🏅',
            'pl': 'Cotygodniowe odznaki 🏅',
            'nl': 'Wekelijkse badges 🏅',
            'es': 'Insignias semanales 🏅',
            'de': 'Wöchentliche Abzeichen 🏅',
          }),
          body: _t({
            'en':
                'At the start of each week, the app can show the badges you earned last week.\nUse this setting to turn that recap on or off.',
            'pl':
                'Na początku każdego tygodnia aplikacja może pokazać odznaki zdobyte w zeszłym tygodniu.\nUżyj tego ustawienia, aby włączyć lub wyłączyć to podsumowanie.',
            'nl':
                'Aan het begin van elke week kan de app de badges tonen die je vorige week verdiende.\nGebruik deze instelling om die samenvatting aan of uit te zetten.',
            'es':
                'Al inicio de cada semana, la app puede mostrar las insignias que ganaste la semana pasada.\nUsa este ajuste para activar o desactivar ese resumen.',
            'de':
                'Zu Beginn jeder Woche kann die App die Abzeichen der letzten Woche anzeigen.\nMit dieser Einstellung schaltest du diese Zusammenfassung ein oder aus.',
          }),
        ),
        // 17 – Vacation Mode
        (
          title: _t({
            'en': 'Vacation Mode 🏖️',
            'pl': 'Tryb wakacyjny 🏖️',
            'nl': 'Vakantiemodus 🏖️',
            'es': 'Modo vacaciones 🏖️',
            'de': 'Urlaubsmodus 🏖️',
          }),
          body: _t({
            'en':
                'Protect your streak while you\'re away.\nTap the toggle to activate Vacation Mode.\nYou can also adjust your daily water goal and Glycemic Load settings here.',
            'pl':
                'Chroń swoją serię, gdy Cię nie ma.\nDotknij przełącznika, aby włączyć Tryb wakacyjny.\nMożesz tu również dostosować dzienny cel wody i ustawienia ładunku glikemicznego.',
            'nl':
                'Bescherm je reeks terwijl je weg bent.\nTik op de schakelaar om Vakantiemodus in te schakelen.\nJe kunt hier ook je dagelijkse waterdoel en glycemische lading-instellingen aanpassen.',
            'es':
                'Protege tu racha mientras estás fuera.\nToca el interruptor para activar el Modo vacaciones.\nTambién puedes ajustar aquí tu objetivo diario de agua y la carga glucémica.',
            'de':
                'Schütze deine Serie, während du weg bist.\nTippe auf den Schalter, um den Urlaubsmodus zu aktivieren.\nHier kannst du auch dein tägliches Wasserziel und die glykämische Last anpassen.',
          }),
        ),
        // 18 – Outro
        (
          title: _t({
            'en': "You're All Set! 🚀",
            'pl': 'Wszystko gotowe! 🚀',
            'nl': 'Je bent klaar! 🚀',
            'es': '¡Todo listo! 🚀',
            'de': 'Alles bereit! 🚀',
          }),
          body: _t({
            'en':
                'Start scanning your first meal — or speak it!\n\nTip: you can replay this tour anytime from Settings → About.',
            'pl':
                'Zacznij od zeskanowania pierwszego posiłku — lub powiedz go!\n\nWskazówka: możesz powtórzyć tę wycieczkę w dowolnym momencie w Ustawienia → Informacje.',
            'nl':
                'Begin met het scannen van je eerste maaltijd — of spreek het in!\n\nTip: je kunt deze rondleiding altijd opnieuw afspelen via Instellingen → Over.',
            'es':
                '¡Empieza escaneando tu primera comida o dícela!\n\nConsejo: puedes repetir este recorrido cuando quieras desde Ajustes → Acerca de.',
            'de':
                'Scanne deine erste Mahlzeit — oder sprich sie ein!\n\nTipp: Du kannst diese Tour jederzeit unter Einstellungen → Info erneut starten.',
          }),
        ),
      ];

  String get mascotAuto => _t({
        'en': 'Auto (matches goal)',
        'pl': 'Auto (dopasowane do celu)',
        'nl': 'Auto (past bij doel)',
        'es': 'Auto (según el objetivo)',
        'de': 'Auto (passt zum Ziel)',
      });

  String get mascotGorilla => _t({
        'en': 'Gorilla',
        'pl': 'Goryl',
        'nl': 'Gorilla',
        'es': 'Gorila',
        'de': 'Gorilla',
      });

  String get mascotPlant => _t({
        'en': 'Plant',
        'pl': 'Roślina',
        'nl': 'Plant',
        'es': 'Planta',
        'de': 'Pflanze',
      });

  String get mascotFlame => _t({
        'en': 'Flame',
        'pl': 'Płomień',
        'nl': 'Vlam',
        'es': 'Llama',
        'de': 'Flamme',
      });

  String get mascotSugarCube => _t({
        'en': 'Sugar Cube',
        'pl': 'Kostka cukru',
        'nl': 'Suikerklontje',
        'es': 'Cubo de azúcar',
        'de': 'Zuckerwürfel',
      });

  String get weeklyReview => _t({
        'en': 'Weekly Review',
        'pl': 'Przegląd tygodniowy',
        'nl': 'Wekelijks overzicht',
        'es': 'Revisión semanal',
        'de': 'Wöchentliche Übersicht',
      });

  // ── Camera / Scan UI ──

  String get cameraRequired => _t({
        'en': 'Camera Required',
        'pl': 'Wymagana kamera',
        'nl': 'Camera vereist',
        'es': 'Cámara requerida',
        'de': 'Kamera erforderlich',
      });

  String get openSettings => _t({
        'en': 'Open Settings',
        'pl': 'Otwórz ustawienia',
        'nl': 'Open instellingen',
        'es': 'Abrir ajustes',
        'de': 'Einstellungen öffnen',
      });

  String get flashlightUnavailable => _t({
        'en': 'Flashlight unavailable on this device.',
        'pl': 'Latarka niedostępna na tym urządzeniu.',
        'nl': 'Zaklamp niet beschikbaar op dit apparaat.',
        'es': 'Linterna no disponible en este dispositivo.',
        'de': 'Taschenlampe auf diesem Gerät nicht verfügbar.',
      });

  String get scanAgain => _t({
        'en': 'Scan Again',
        'pl': 'Skanuj ponownie',
        'nl': 'Opnieuw scannen',
        'es': 'Escanear de nuevo',
        'de': 'Erneut scannen',
      });

  String get noFoodDetectedTitle => _t({
        'en': 'No food detected',
        'pl': 'Nie wykryto jedzenia',
        'nl': 'Geen eten gedetecteerd',
        'es': 'No se detectó comida',
        'de': 'Kein Essen erkannt',
      });

  String get noFoodDetectedBody => _t({
        'en': 'Point the camera at a plate or food item and scan again.',
        'pl': 'Skieruj kamerę na talerz lub jedzenie i zeskanuj ponownie.',
        'nl': 'Richt de camera op een bord of voedsel en scan opnieuw.',
        'es': 'Apunta la cámara a un plato o alimento y escanea de nuevo.',
        'de':
            'Richte die Kamera auf einen Teller oder ein Lebensmittel und scanne erneut.',
      });

  String get scanAnalysisFailed => _t({
        'en': 'Scan analysis failed. Please rescan.',
        'pl': 'Analiza skanu nie powiodła się. Zeskanuj ponownie.',
        'nl': 'Scananalyse mislukt. Scan opnieuw.',
        'es': 'Falló el análisis del escaneo. Escanea de nuevo.',
        'de': 'Scananalyse fehlgeschlagen. Bitte erneut scannen.',
      });

  String get scan3dFailed => _t({
        'en': '3D scan failed. Please rescan.',
        'pl': 'Skan 3D nie powiódł się. Zeskanuj ponownie.',
        'nl': '3D-scan mislukt. Scan opnieuw.',
        'es': 'Falló el escaneo 3D. Escanea de nuevo.',
        'de': '3D-Scan fehlgeschlagen. Bitte erneut scannen.',
      });

  String get cameraSessionFailedTitle => _t({
        'en': 'Camera unavailable',
        'pl': 'Kamera niedostępna',
        'nl': 'Camera niet beschikbaar',
        'es': 'Cámara no disponible',
        'de': 'Kamera nicht verfügbar',
      });

  String get cameraSessionFailedBody => _t({
        'en':
            "We couldn't start the camera. Check app permissions and try again.",
        'pl':
            'Nie udało się uruchomić kamery. Sprawdź uprawnienia aplikacji i spróbuj ponownie.',
        'nl':
            'We konden de camera niet starten. Controleer de app-machtigingen en probeer het opnieuw.',
        'es':
            'No pudimos iniciar la cámara. Revisa los permisos de la app e inténtalo de nuevo.',
        'de':
            'Die Kamera konnte nicht gestartet werden. Überprüfe die App-Berechtigungen und versuche es erneut.',
      });

  String get scanModelErrorBody => _t({
        'en': 'Analysis error. Tap Scan Again to retry.',
        'pl':
            'Błąd analizy. Dotknij „Skanuj ponownie", aby spróbować ponownie.',
        'nl':
            'Analysefout. Tik op Opnieuw scannen om het nogmaals te proberen.',
        'es': 'Error de análisis. Toca Escanear de nuevo para reintentar.',
        'de':
            'Analysefehler. Tippe auf „Erneut scannen", um es erneut zu versuchen.',
      });

  String get scanErrorCopyTitle => _t({
        'en': 'Error - tap and hold to copy',
        'pl': 'Błąd - dotknij i przytrzymaj, aby skopiować',
        'nl': 'Fout - tik en houd vast om te kopiëren',
        'es': 'Error - mantén pulsado para copiar',
        'de': 'Fehler - zum Kopieren gedrückt halten',
      });

  String get copyError => _t({
        'en': 'Copy error',
        'pl': 'Kopiuj błąd',
        'nl': 'Fout kopiëren',
        'es': 'Copiar error',
        'de': 'Fehler kopieren',
      });

  String get building3dPreview => _t({
        'en': 'Building 3D scan preview',
        'pl': 'Budowanie podglądu skanu 3D',
        'nl': '3D-scanvoorbeeld maken',
        'es': 'Creando vista previa 3D',
        'de': '3D-Scanvorschau wird erstellt',
      });

  String get refining3dFoodModel => _t({
        'en': 'Refining generated 3D food model',
        'pl': 'Dopracowywanie wygenerowanego modelu 3D jedzenia',
        'nl': 'Gegenereerd 3D-voedselmodel verfijnen',
        'es': 'Refinando el modelo 3D de comida generado',
        'de': 'Generiertes 3D-Lebensmittelmodell wird verfeinert',
      });

  String get turnOffFlashlight => _t({
        'en': 'Turn off flashlight',
        'pl': 'Wyłącz latarkę',
        'nl': 'Zaklamp uitzetten',
        'es': 'Apagar linterna',
        'de': 'Taschenlampe ausschalten',
      });

  String get turnOnFlashlight => _t({
        'en': 'Turn on flashlight',
        'pl': 'Włącz latarkę',
        'nl': 'Zaklamp aanzetten',
        'es': 'Encender linterna',
        'de': 'Taschenlampe einschalten',
      });

  String get lowLightScanWarning => _t({
        'en': 'Low light - turn on the flashlight for better detection.',
        'pl': 'Słabe światło - włącz latarkę, aby poprawić wykrywanie.',
        'nl': 'Weinig licht - zet de zaklamp aan voor betere detectie.',
        'es': 'Poca luz - enciende la linterna para detectar mejor.',
        'de':
            'Wenig Licht - schalte die Taschenlampe für bessere Erkennung ein.',
      });

  String get generatingEstimated3dModel => _t({
        'en': 'Generating estimated 3D model...',
        'pl': 'Generowanie szacowanego modelu 3D...',
        'nl': 'Geschat 3D-model maken...',
        'es': 'Generando modelo 3D estimado...',
        'de': 'Geschätztes 3D-Modell wird erstellt...',
      });

  String get buildingLidar3dModel => _t({
        'en': 'Building LiDAR 3D model...',
        'pl': 'Budowanie modelu 3D LiDAR...',
        'nl': 'LiDAR 3D-model maken...',
        'es': 'Creando modelo 3D LiDAR...',
        'de': 'LiDAR-3D-Modell wird erstellt...',
      });

  String get tapToScan => _t({
        'en': 'Tap to scan',
        'pl': 'Dotknij, aby skanować',
        'nl': 'Tik om te scannen',
        'es': 'Toca para escanear',
        'de': 'Tippen zum Scannen',
      });

  String get startingCamera => _t({
        'en': 'Starting camera...',
        'pl': 'Uruchamianie kamery...',
        'nl': 'Camera starten...',
        'es': 'Iniciando cámara...',
        'de': 'Kamera wird gestartet...',
      });

  String secondsRemaining(int seconds) => _t({
        'en': '${seconds}s remaining',
        'pl': 'Pozostało ${seconds}s',
        'nl': '${seconds}s resterend',
        'es': 'Quedan ${seconds}s',
        'de': '${seconds}s verbleibend',
      });

  String get topViewDetectedStarting => _t({
        'en': 'Top view detected - starting...',
        'pl': 'Wykryto widok z góry - start...',
        'nl': 'Bovenaanzicht gedetecteerd - starten...',
        'es': 'Vista superior detectada - iniciando...',
        'de': 'Draufsicht erkannt - Start...',
      });

  String tiltPhoneDown(int degrees) => _t({
        'en': 'Tilt phone down (${degrees}°)',
        'pl': 'Pochyl telefon w dół (${degrees}°)',
        'nl': 'Kantel telefoon omlaag (${degrees}°)',
        'es': 'Inclina el teléfono hacia abajo (${degrees}°)',
        'de': 'Telefon nach unten neigen (${degrees}°)',
      });

  String get retry => _t({
        'en': 'Retry',
        'pl': 'Ponów',
        'nl': 'Opnieuw proberen',
        'es': 'Reintentar',
        'de': 'Wiederholen',
      });

  String get errorCopied => _t({
        'en': 'Error copied to clipboard',
        'pl': 'Błąd skopiowany do schowka',
        'nl': 'Fout gekopieerd naar klembord',
        'es': 'Error copiado al portapapeles',
        'de': 'Fehler in Zwischenablage kopiert',
      });

  // ── Scan Detail ──

  String get scanDetails => _t({
        'en': 'Scan Details',
        'pl': 'Szczegóły skanu',
        'nl': 'Scandetails',
        'es': 'Detalles del escaneo',
        'de': 'Scan-Details',
      });

  String get logFood => _t({
        'en': 'Log food',
        'pl': 'Zapisz jedzenie',
        'nl': 'Voedsel loggen',
        'es': 'Registrar comida',
        'de': 'Essen erfassen',
      });

  String get removeThisItem => _t({
        'en': 'Remove this item?',
        'pl': 'Usunąć ten element?',
        'nl': 'Dit item verwijderen?',
        'es': '¿Eliminar este elemento?',
        'de': 'Dieses Element entfernen?',
      });

  String get remove => _t({
        'en': 'Remove',
        'pl': 'Usuń',
        'nl': 'Verwijderen',
        'es': 'Eliminar',
        'de': 'Entfernen',
      });

  String get deleteScan => _t({
        'en': 'Delete scan?',
        'pl': 'Usunąć skan?',
        'nl': 'Scan verwijderen?',
        'es': '¿Eliminar escaneo?',
        'de': 'Scan löschen?',
      });

  String get deleteScanDesc => _t({
        'en': 'This will permanently remove this scan entry.',
        'pl': 'To trwale usunie ten wpis skanu.',
        'nl': 'Dit zal deze scaninvoer permanent verwijderen.',
        'es': 'Esto eliminará permanentemente esta entrada de escaneo.',
        'de': 'Dies wird diesen Scan-Eintrag dauerhaft entfernen.',
      });

  String get cool => _t({
        'en': 'Cool',
        'pl': 'Zimny',
        'nl': 'Koel',
        'es': 'Frío',
        'de': 'Kühl',
      });

  String get hot => _t({
        'en': 'Hot',
        'pl': 'Gorący',
        'nl': 'Heet',
        'es': 'Caliente',
        'de': 'Heiß',
      });

  String get noDepthData => _t({
        'en': 'No depth data available for point cloud',
        'pl': 'Brak danych głębi dla chmury punktów',
        'nl': 'Geen dieptedata beschikbaar voor puntenwolk',
        'es': 'No hay datos de profundidad disponibles',
        'de': 'Keine Tiefendaten für Punktwolke verfügbar',
      });

  String get plySaved => _t({
        'en': 'PLY saved',
        'pl': 'PLY zapisany',
        'nl': 'PLY opgeslagen',
        'es': 'PLY guardado',
        'de': 'PLY gespeichert',
      });

  // ── Settings extras ──

  String get csvCopied => _t({
        'en': 'CSV copied to clipboard',
        'pl': 'CSV skopiowany do schowka',
        'nl': 'CSV gekopieerd naar klembord',
        'es': 'CSV copiado al portapapeles',
        'de': 'CSV in Zwischenablage kopiert',
      });

  String get saveWaterGoal => _t({
        'en': 'Save Water Goal',
        'pl': 'Zapisz cel wody',
        'nl': 'Waterdoel opslaan',
        'es': 'Guardar objetivo de agua',
        'de': 'Wasserziel speichern',
      });

  String get exportDailySummary => _t({
        'en': 'Export Daily Summary (CSV)',
        'pl': 'Eksportuj dzienny raport (CSV)',
        'nl': 'Dagelijkse samenvatting exporteren (CSV)',
        'es': 'Exportar resumen diario (CSV)',
        'de': 'Tageszusammenfassung exportieren (CSV)',
      });

  String get exportDetailedData => _t({
        'en': 'Export Detailed Data (CSV)',
        'pl': 'Eksportuj szczegółowe dane (CSV)',
        'nl': 'Gedetailleerde data exporteren (CSV)',
        'es': 'Exportar datos detallados (CSV)',
        'de': 'Detaillierte Daten exportieren (CSV)',
      });

  String get clearScanHistory => _t({
        'en': 'Clear Scan History?',
        'pl': 'Wyczyścić historię skanów?',
        'nl': 'Scangeschiedenis wissen?',
        'es': '¿Borrar historial de escaneos?',
        'de': 'Scan-Verlauf löschen?',
      });

  String get scanHistoryCleared => _t({
        'en': 'Scan history cleared',
        'pl': 'Historia skanów wyczyszczona',
        'nl': 'Scangeschiedenis gewist',
        'es': 'Historial de escaneos borrado',
        'de': 'Scan-Verlauf gelöscht',
      });

  String get evaluationDashboard => _t({
        'en': 'Evaluation Dashboard',
        'pl': 'Panel ewaluacji',
        'nl': 'Evaluatiedashboard',
        'es': 'Panel de evaluación',
        'de': 'Auswertungs-Dashboard',
      });

  String get resetEntireApp => _t({
        'en': 'Reset Entire App?',
        'pl': 'Zresetować całą aplikację?',
        'nl': 'Hele app resetten?',
        'es': '¿Restablecer toda la app?',
        'de': 'Gesamte App zurücksetzen?',
      });

  String get resetEverything => _t({
        'en': 'Reset Everything',
        'pl': 'Resetuj wszystko',
        'nl': 'Alles resetten',
        'es': 'Restablecer todo',
        'de': 'Alles zurücksetzen',
      });

  String get signIn => _t({
        'en': 'Sign In / Create Account',
        'pl': 'Zaloguj się / Utwórz konto',
        'nl': 'Inloggen / Account aanmaken',
        'es': 'Iniciar sesión / Crear cuenta',
        'de': 'Anmelden / Konto erstellen',
      });

  String get signOut => _t({
        'en': 'Sign Out',
        'pl': 'Wyloguj',
        'nl': 'Uitloggen',
        'es': 'Cerrar sesión',
        'de': 'Abmelden',
      });

  String get deleteAccount => _t({
        'en': 'Delete Account',
        'pl': 'Usuń konto',
        'nl': 'Account verwijderen',
        'es': 'Eliminar cuenta',
        'de': 'Konto löschen',
      });

  String get mealReminder => _t({
        'en': 'Meal reminder',
        'pl': 'Przypomnienie o posiłku',
        'nl': 'Maaltijdherinnering',
        'es': 'Recordatorio de comida',
        'de': 'Mahlzeiterinnerung',
      });

  String get mealReminderDesc => _t({
        'en': 'Remind me to log breakfast, lunch & dinner if I forget',
        'pl': 'Przypomnij o śniadaniu, obiedzie i kolacji, jeśli zapomnę',
        'nl': 'Herinner me aan ontbijt, lunch en diner als ik het vergeet',
        'es': 'Recordarme registrar desayuno, almuerzo y cena si lo olvido',
        'de': 'Erinnere mich an Frühstück, Mittag- & Abendessen, falls ich es vergesse',
      });

  String get mealReminderBreakfastTitle => _t({
        'en': 'Good morning! 🍳',
        'pl': 'Dzień dobry! 🍳',
        'nl': 'Goedemorgen! 🍳',
        'es': '¡Buenos días! 🍳',
        'de': 'Guten Morgen! 🍳',
      });

  String get mealReminderLunchTitle => _t({
        'en': 'Lunchtime! 🍽️',
        'pl': 'Pora na obiad! 🍽️',
        'nl': 'Lunchtijd! 🍽️',
        'es': '¡Hora de almorzar! 🍽️',
        'de': 'Zeit fürs Mittagessen! 🍽️',
      });

  String get mealReminderDinnerTitle => _t({
        'en': 'Dinnertime 🌙',
        'pl': 'Pora na kolację 🌙',
        'nl': 'Tijd voor het diner 🌙',
        'es': 'Hora de cenar 🌙',
        'de': 'Zeit fürs Abendessen 🌙',
      });

  String get mealReminderBreakfastBody => _t({
        'en': 'Don\'t forget to log your breakfast.',
        'pl': 'Nie zapomnij zapisać śniadania.',
        'nl': 'Vergeet niet je ontbijt te loggen.',
        'es': 'No olvides registrar tu desayuno.',
        'de': 'Vergiss nicht, dein Frühstück zu loggen.',
      });

  String get mealReminderLunchBody => _t({
        'en': 'Have you logged your lunch yet?',
        'pl': 'Czy zapisałeś już swój obiad?',
        'nl': 'Heb je je lunch al gelogd?',
        'es': '¿Ya registraste tu almuerzo?',
        'de': 'Hast du dein Mittagessen schon geloggt?',
      });

  String get mealReminderDinnerBody => _t({
        'en': 'Round off your day — log your dinner.',
        'pl': 'Zakończ dzień — zapisz swoją kolację.',
        'nl': 'Sluit je dag af — log je diner.',
        'es': 'Cierra tu día: registra tu cena.',
        'de': 'Runde deinen Tag ab — logge dein Abendessen.',
      });

  String get waterReminder => _t({
        'en': 'Water reminder',
        'pl': 'Przypomnienie o wodzie',
        'nl': 'Waterherinnering',
        'es': 'Recordatorio de agua',
        'de': 'Wassererinnerung',
      });

  String get waterReminderDesc => _t({
        'en': 'Remind me to drink water every 2 hours',
        'pl': 'Przypomnij mi o piciu wody co 2 godziny',
        'nl': 'Herinner me elke 2 uur water te drinken',
        'es': 'Recordarme beber agua cada 2 horas',
        'de': 'Erinnere mich alle 2 Stunden Wasser zu trinken',
      });

  // ── Auth ──

  String get continueWithApple => _t({
        'en': 'Continue with Apple',
        'pl': 'Kontynuuj z Apple',
        'nl': 'Doorgaan met Apple',
        'es': 'Continuar con Apple',
        'de': 'Mit Apple fortfahren',
      });

  String get or => _t({
        'en': 'or',
        'pl': 'lub',
        'nl': 'of',
        'es': 'o',
        'de': 'oder',
      });

  String get passwordResetSent => _t({
        'en': 'Password reset email sent',
        'pl': 'E-mail do resetowania hasła wysłany',
        'nl': 'Wachtwoord reset e-mail verzonden',
        'es': 'Correo de restablecimiento enviado',
        'de': 'Passwort-Reset-E-Mail gesendet',
      });

  String get enterEmailFirst => _t({
        'en': 'Enter your email first',
        'pl': 'Najpierw wpisz swój e-mail',
        'nl': 'Voer eerst je e-mail in',
        'es': 'Ingresa tu correo primero',
        'de': 'Gib zuerst deine E-Mail ein',
      });

  String get forgotPassword => _t({
        'en': 'Forgot password?',
        'pl': 'Zapomniałeś hasła?',
        'nl': 'Wachtwoord vergeten?',
        'es': '¿Olvidaste tu contraseña?',
        'de': 'Passwort vergessen?',
      });

  // ── Voice entry extras ──

  String get enterMealName => _t({
        'en': 'Please enter a name for the meal.',
        'pl': 'Proszę podać nazwę posiłku.',
        'nl': 'Voer een naam in voor de maaltijd.',
        'es': 'Por favor ingresa un nombre para la comida.',
        'de': 'Bitte gib einen Namen für die Mahlzeit ein.',
      });

  // ── Meal planner extras ──

  String get clearWeekPlan => _t({
        'en': 'Clear Week Plan?',
        'pl': 'Wyczyścić plan tygodnia?',
        'nl': 'Weekplan wissen?',
        'es': '¿Borrar plan semanal?',
        'de': 'Wochenplan löschen?',
      });

  String get ingredientsFromPlan => _t({
        'en': 'ingredients from your meal plan',
        'pl': 'składniki z Twojego planu posiłków',
        'nl': 'ingrediënten uit je maaltijdplan',
        'es': 'ingredientes de tu plan de comidas',
        'de': 'Zutaten aus deinem Mahlzeitenplan',
      });

  String groceryUsesThisWeek(String amount) => _t({
        'en': 'uses $amount this week',
        'pl': 'zużywa $amount w tym tygodniu',
        'nl': 'gebruikt deze week $amount',
        'es': 'usa $amount esta semana',
        'de': 'verbraucht diese Woche $amount',
      });

  String get groceryInStock => _t({
        'en': 'already in stock from last shop',
        'pl': 'już w zapasie z poprzednich zakupów',
        'nl': 'al op voorraad van vorige keer',
        'es': 'ya disponible de la compra anterior',
        'de': 'bereits vom letzten Einkauf vorrätig',
      });

  String pickRecipe(String meal) => _t({
        'en': 'Pick a ${meal.toLowerCase()} recipe',
        'pl': 'Wybierz przepis na ${meal.toLowerCase()}',
        'nl': 'Kies een ${meal.toLowerCase()} recept',
        'es': 'Elige una receta de ${meal.toLowerCase()}',
        'de': 'Wähle ein $meal-Rezept',
      });

  String get searchRecipes => _t({
        'en': 'Search recipes...',
        'pl': 'Szukaj przepisów...',
        'nl': 'Recepten zoeken...',
        'es': 'Buscar recetas...',
        'de': 'Rezepte suchen...',
      });

  String addItemsToGroceryList(int n) => _t({
        'en': 'Add $n Items to Grocery List',
        'pl': 'Dodaj $n pozycji do listy zakupów',
        'nl': 'Voeg $n items toe aan boodschappenlijst',
        'es': 'Añadir $n artículos a la lista de compras',
        'de': '$n Artikel zur Einkaufsliste hinzufügen',
      });

  String usedCount(int n) => _t({
        'en': 'used ${n}x',
        'pl': 'użyto ${n}x',
        'nl': '${n}x gebruikt',
        'es': 'usado ${n}x',
        'de': '${n}x verwendet',
      });

  String gramsTotal(int grams) => _t({
        'en': 'about $grams g total',
        'pl': 'około $grams g łącznie',
        'nl': 'ongeveer $grams g totaal',
        'es': 'aprox. $grams g en total',
        'de': 'ca. $grams g gesamt',
      });

  // ── Manual entry ──

  String get noIngredients => _t({
        'en': 'This meal has no ingredients.',
        'pl': 'Ten posiłek nie ma składników.',
        'nl': 'Deze maaltijd heeft geen ingrediënten.',
        'es': 'Esta comida no tiene ingredientes.',
        'de': 'Diese Mahlzeit hat keine Zutaten.',
      });

  String get logMeal => _t({
        'en': 'Log Meal',
        'pl': 'Zaloguj posiłek',
        'nl': 'Maaltijd loggen',
        'es': 'Registrar comida',
        'de': 'Mahlzeit loggen',
      });

  String get unhealthy => _t({
        'en': 'Unhealthy',
        'pl': 'Niezdrowy',
        'nl': 'Ongezond',
        'es': 'No saludable',
        'de': 'Ungesund',
      });

  String get healthy => _t({
        'en': 'Healthy',
        'pl': 'Zdrowy',
        'nl': 'Gezond',
        'es': 'Saludable',
        'de': 'Gesund',
      });

  String get addToLog => _t({
        'en': 'Add to Log',
        'pl': 'Dodaj do dziennika',
        'nl': 'Toevoegen aan logboek',
        'es': 'Agregar al registro',
        'de': 'Zum Tagebuch hinzufügen',
      });

  String get logFoodManually => _t({
        'en': 'Log Food Manually',
        'pl': 'Loguj jedzenie ręcznie',
        'nl': 'Handmatig voedsel loggen',
        'es': 'Registrar comida manualmente',
        'de': 'Essen manuell loggen',
      });

  String get noSavedMeals => _t({
        'en': 'No saved meals yet',
        'pl': 'Brak zapisanych posiłków',
        'nl': 'Nog geen opgeslagen maaltijden',
        'es': 'Aún no hay comidas guardadas',
        'de': 'Noch keine gespeicherten Mahlzeiten',
      });

  String get createMealDesc => _t({
        'en': 'Create a meal to quickly log it next time.',
        'pl': 'Utwórz posiłek, aby szybko go zalogować następnym razem.',
        'nl': 'Maak een maaltijd om die de volgende keer snel te loggen.',
        'es': 'Crea una comida para registrarla rápidamente la próxima vez.',
        'de': 'Erstelle eine Mahlzeit, um sie nächstes Mal schnell zu loggen.',
      });

  String get createMeal => _t({
        'en': 'Create Meal',
        'pl': 'Utwórz posiłek',
        'nl': 'Maaltijd maken',
        'es': 'Crear comida',
        'de': 'Mahlzeit erstellen',
      });

  String get deleteMeal => _t({
        'en': 'Delete meal?',
        'pl': 'Usunąć posiłek?',
        'nl': 'Maaltijd verwijderen?',
        'es': '¿Eliminar comida?',
        'de': 'Mahlzeit löschen?',
      });

  String get createNewMeal => _t({
        'en': 'Create New Meal',
        'pl': 'Utwórz nowy posiłek',
        'nl': 'Nieuwe maaltijd maken',
        'es': 'Crear nueva comida',
        'de': 'Neue Mahlzeit erstellen',
      });

  // ── Body Map extras ──

  String get howBodyMapWorks => _t({
        'en': 'How the Body Map works',
        'pl': 'Jak działa mapa ciała',
        'nl': 'Hoe de lichaamskaart werkt',
        'es': 'Cómo funciona el mapa corporal',
        'de': 'Wie die Körperkarte funktioniert',
      });

  String get gotIt => _t({
        'en': 'Got it',
        'pl': 'Rozumiem',
        'nl': 'Begrepen',
        'es': 'Entendido',
        'de': 'Verstanden',
      });

  // ── Calculation provenance (info cards) ──

  String get howThisIsCalculated => _t({
        'en': 'How this is calculated',
        'pl': 'Jak to jest obliczane',
        'nl': 'Hoe dit wordt berekend',
        'es': 'Cómo se calcula esto',
        'de': 'Wie das berechnet wird',
      });

  String get calcWhyTrust => _t({
        'en': 'Why you can trust this',
        'pl': 'Dlaczego można temu ufać',
        'nl': 'Waarom je dit kunt vertrouwen',
        'es': 'Por qué puedes confiar en esto',
        'de': 'Warum du dem vertrauen kannst',
      });

  String get calcSource => _t({
        'en': 'Source',
        'pl': 'Źródło',
        'nl': 'Bron',
        'es': 'Fuente',
        'de': 'Quelle',
      });

  String get calcCaloriesTitle => _t({
        'en': 'Daily calorie target',
        'pl': 'Dzienny cel kaloryczny',
        'nl': 'Dagelijks caloriedoel',
        'es': 'Objetivo de calorías diario',
        'de': 'Tägliches Kalorienziel',
      });

  String get calcCaloriesExplain => _t({
        'en':
            'Your maintenance calories are estimated from your weight, height, sex and self-reported muscle mass (about 30–33 kcal per kg, adjusted for build). Your goal then adds a surplus for muscle growth or a deficit for weight loss, kept within safe limits.',
        'pl':
            'Twoje kalorie podtrzymujące są szacowane na podstawie wagi, wzrostu, płci i deklarowanej masy mięśniowej (około 30–33 kcal na kg, z korektą na budowę ciała). Następnie cel dodaje nadwyżkę przy budowie mięśni lub deficyt przy odchudzaniu, w bezpiecznych granicach.',
        'nl':
            'Je onderhoudscalorieën worden geschat op basis van je gewicht, lengte, geslacht en opgegeven spiermassa (ongeveer 30–33 kcal per kg, aangepast aan je bouw). Je doel voegt dan een overschot toe voor spiergroei of een tekort voor gewichtsverlies, binnen veilige grenzen.',
        'es':
            'Tus calorías de mantenimiento se estiman a partir de tu peso, estatura, sexo y masa muscular declarada (unas 30–33 kcal por kg, ajustadas a tu complexión). Luego tu objetivo añade un superávit para ganar músculo o un déficit para perder peso, dentro de límites seguros.',
        'de':
            'Deine Erhaltungskalorien werden aus Gewicht, Größe, Geschlecht und angegebener Muskelmasse geschätzt (etwa 30–33 kcal pro kg, an den Körperbau angepasst). Dein Ziel ergänzt dann einen Überschuss für Muskelaufbau oder ein Defizit zum Abnehmen, innerhalb sicherer Grenzen.',
      });

  String get calcCaloriesWhy => _t({
        'en':
            'It follows established energy-requirement methods and caps deficits and surpluses to evidence-based ranges so your target stays safe and sustainable.',
        'pl':
            'Opiera się na uznanych metodach szacowania zapotrzebowania energetycznego i ogranicza deficyty oraz nadwyżki do zakresów opartych na dowodach, aby cel był bezpieczny i możliwy do utrzymania.',
        'nl':
            'Het volgt erkende methoden voor energiebehoefte en beperkt tekorten en overschotten tot wetenschappelijk onderbouwde bereiken, zodat je doel veilig en haalbaar blijft.',
        'es':
            'Sigue métodos reconocidos de necesidades energéticas y limita los déficits y superávits a rangos basados en evidencia para que tu objetivo sea seguro y sostenible.',
        'de':
            'Sie folgt anerkannten Methoden zum Energiebedarf und begrenzt Defizite und Überschüsse auf evidenzbasierte Bereiche, damit dein Ziel sicher und nachhaltig bleibt.',
      });

  String get calcMacrosTitle => _t({
        'en': 'Protein, carb & fat targets',
        'pl': 'Cele białka, węglowodanów i tłuszczu',
        'nl': 'Doelen voor eiwit, koolhydraten en vet',
        'es': 'Objetivos de proteínas, carbohidratos y grasas',
        'de': 'Ziele für Eiweiß, Kohlenhydrate und Fett',
      });

  String get calcMacrosExplain => _t({
        'en':
            'Your calories are split into protein, carbohydrate and fat based on your goal (for example higher protein for weight loss, lower carbs for diabetes). Grams use 4 kcal per gram of protein and carbs and 9 kcal per gram of fat.',
        'pl':
            'Twoje kalorie są dzielone na białko, węglowodany i tłuszcz w zależności od celu (np. więcej białka przy odchudzaniu, mniej węglowodanów przy cukrzycy). Gramy liczone są jako 4 kcal na gram białka i węglowodanów oraz 9 kcal na gram tłuszczu.',
        'nl':
            'Je calorieën worden verdeeld over eiwit, koolhydraten en vet op basis van je doel (bijvoorbeeld meer eiwit bij gewichtsverlies, minder koolhydraten bij diabetes). Grammen gebruiken 4 kcal per gram eiwit en koolhydraten en 9 kcal per gram vet.',
        'es':
            'Tus calorías se reparten entre proteínas, carbohidratos y grasas según tu objetivo (por ejemplo, más proteína para perder peso, menos carbohidratos para la diabetes). Los gramos usan 4 kcal por gramo de proteína y carbohidratos y 9 kcal por gramo de grasa.',
        'de':
            'Deine Kalorien werden je nach Ziel auf Eiweiß, Kohlenhydrate und Fett aufgeteilt (z. B. mehr Eiweiß zum Abnehmen, weniger Kohlenhydrate bei Diabetes). Gramm werden mit 4 kcal pro Gramm Eiweiß und Kohlenhydrate und 9 kcal pro Gramm Fett berechnet.',
      });

  String get calcMacrosWhy => _t({
        'en':
            'The splits stay within the macronutrient reference intake ranges published by the European Food Safety Authority (EFSA) and follow goal-specific clinical guidance.',
        'pl':
            'Proporcje mieszczą się w referencyjnych zakresach spożycia makroskładników opublikowanych przez Europejski Urząd ds. Bezpieczeństwa Żywności (EFSA) i są zgodne z wytycznymi klinicznymi dla danego celu.',
        'nl':
            'De verdelingen blijven binnen de referentie-innamebereiken voor macronutriënten van de Europese Autoriteit voor voedselveiligheid (EFSA) en volgen doelgerichte klinische richtlijnen.',
        'es':
            'Las proporciones se mantienen dentro de los rangos de ingesta de referencia de macronutrientes publicados por la Autoridad Europea de Seguridad Alimentaria (EFSA) y siguen pautas clínicas según tu objetivo.',
        'de':
            'Die Aufteilungen bleiben innerhalb der von der Europäischen Behörde für Lebensmittelsicherheit (EFSA) veröffentlichten Referenzbereiche für die Makronährstoffzufuhr und folgen zielspezifischen klinischen Leitlinien.',
      });

  String get calcMicroTitle => _t({
        'en': 'Vitamin & mineral targets',
        'pl': 'Cele witamin i minerałów',
        'nl': 'Doelen voor vitamines en mineralen',
        'es': 'Objetivos de vitaminas y minerales',
        'de': 'Ziele für Vitamine und Mineralstoffe',
      });

  String get calcMicroExplain => _t({
        'en':
            'Each micronutrient target is the EFSA Dietary Reference Value for your sex, fine-tuned for your goal (for example more iron and B12 on a vegan diet, more fibre for diabetes).',
        'pl':
            'Każdy cel mikroskładnika to referencyjna wartość spożycia EFSA (DRV) dla Twojej płci, dostosowana do celu (np. więcej żelaza i witaminy B12 na diecie wegańskiej, więcej błonnika przy cukrzycy).',
        'nl':
            'Elk micronutriëntdoel is de EFSA-referentiewaarde (DRV) voor jouw geslacht, afgestemd op je doel (bijvoorbeeld meer ijzer en B12 bij een veganistisch dieet, meer vezels bij diabetes).',
        'es':
            'Cada objetivo de micronutriente es el Valor Dietético de Referencia de la EFSA para tu sexo, ajustado a tu objetivo (por ejemplo, más hierro y B12 en una dieta vegana, más fibra para la diabetes).',
        'de':
            'Jeder Mikronährstoff-Zielwert ist der EFSA-Referenzwert (DRV) für dein Geschlecht, abgestimmt auf dein Ziel (z. B. mehr Eisen und B12 bei veganer Ernährung, mehr Ballaststoffe bei Diabetes).',
      });

  String get calcMicroWhy => _t({
        'en':
            'Values come from the European Food Safety Authority (EFSA) Dietary Reference Values, the standard reference used by dietitians and public-health bodies across the EU.',
        'pl':
            'Wartości pochodzą z referencyjnych wartości spożycia (DRV) Europejskiego Urzędu ds. Bezpieczeństwa Żywności (EFSA) — standardu używanego przez dietetyków i instytucje zdrowia publicznego w UE.',
        'nl':
            'De waarden komen uit de Dietary Reference Values van de Europese Autoriteit voor voedselveiligheid (EFSA), de standaardreferentie van diëtisten en volksgezondheidsinstanties in de EU.',
        'es':
            'Los valores provienen de los Valores Dietéticos de Referencia de la Autoridad Europea de Seguridad Alimentaria (EFSA), la referencia estándar que usan dietistas y organismos de salud pública en la UE.',
        'de':
            'Die Werte stammen aus den Dietary Reference Values der Europäischen Behörde für Lebensmittelsicherheit (EFSA), der Standardreferenz von Ernährungsfachkräften und Gesundheitsbehörden in der EU.',
      });

  String get calcPlateTitle => _t({
        'en': 'Plate score',
        'pl': 'Ocena talerza',
        'nl': 'Bordscore',
        'es': 'Puntuación del plato',
        'de': 'Teller-Bewertung',
      });

  String get calcPlateExplain => _t({
        'en':
            'A 0–100 quality score for a meal. It rewards a balanced calorie portion, enough protein and fibre, food variety and a low glycemic load, and lowers points for high saturated fat and sodium.',
        'pl':
            'Ocena jakości posiłku od 0 do 100. Nagradza zrównoważoną porcję kalorii, odpowiednią ilość białka i błonnika, różnorodność produktów i niski ładunek glikemiczny, a obniża punkty za dużo tłuszczów nasyconych i sodu.',
        'nl':
            'Een kwaliteitsscore van 0–100 voor een maaltijd. Het beloont een gebalanceerde calorieportie, voldoende eiwit en vezels, afwisseling en een lage glykemische lading, en trekt punten af voor veel verzadigd vet en natrium.',
        'es':
            'Una puntuación de calidad de 0 a 100 para una comida. Premia una porción calórica equilibrada, suficiente proteína y fibra, variedad de alimentos y una carga glucémica baja, y resta puntos por exceso de grasa saturada y sodio.',
        'de':
            'Eine Qualitätsbewertung von 0–100 für eine Mahlzeit. Sie belohnt eine ausgewogene Kalorienportion, genug Eiweiß und Ballaststoffe, Vielfalt und eine niedrige glykämische Last und zieht Punkte für viel gesättigtes Fett und Natrium ab.',
      });

  String get calcPlateWhy => _t({
        'en':
            'The components reflect the EU food-based dietary guidelines and widely used diet-quality indices. It is a helpful guide, not a medical diagnosis.',
        'pl':
            'Składowe odzwierciedlają unijne wytyczne żywieniowe oparte na żywności i powszechnie stosowane wskaźniki jakości diety. To pomocna wskazówka, a nie diagnoza medyczna.',
        'nl':
            'De onderdelen weerspiegelen de EU-voedingsrichtlijnen op basis van voedingsmiddelen en veelgebruikte indexen voor dieetkwaliteit. Het is een handige richtlijn, geen medische diagnose.',
        'es':
            'Los componentes reflejan las guías alimentarias de la UE basadas en alimentos e índices de calidad de la dieta ampliamente usados. Es una guía útil, no un diagnóstico médico.',
        'de':
            'Die Bestandteile orientieren sich an den lebensmittelbasierten Ernährungsrichtlinien der EU und gängigen Indizes zur Ernährungsqualität. Es ist eine hilfreiche Orientierung, keine medizinische Diagnose.',
      });

  String get calcBodyMapTitle => _t({
        'en': 'Body map coverage',
        'pl': 'Pokrycie mapy ciała',
        'nl': 'Dekking lichaamskaart',
        'es': 'Cobertura del mapa corporal',
        'de': 'Abdeckung der Körperkarte',
      });

  String get calcBodyMapExplain => _t({
        'en':
            'Each organ is coloured by how well your recent intake of the nutrients it relies on matches your targets. Green means you are meeting the target; red means well below — or far above a safe upper limit.',
        'pl':
            'Każdy narząd jest kolorowany w zależności od tego, jak Twoje ostatnie spożycie potrzebnych mu składników odpowiada celom. Zielony oznacza realizację celu, a czerwony — znacznie poniżej lub znacznie powyżej bezpiecznego limitu.',
        'nl':
            'Elk orgaan krijgt een kleur op basis van hoe goed je recente inname van de benodigde voedingsstoffen overeenkomt met je doelen. Groen betekent dat je het doel haalt; rood betekent ver eronder — of ver boven een veilige bovengrens.',
        'es':
            'Cada órgano se colorea según qué tan bien tu ingesta reciente de los nutrientes que necesita coincide con tus objetivos. Verde significa que cumples el objetivo; rojo, muy por debajo o muy por encima de un límite superior seguro.',
        'de':
            'Jedes Organ wird danach eingefärbt, wie gut deine jüngste Zufuhr der benötigten Nährstoffe deinen Zielen entspricht. Grün bedeutet Ziel erreicht; Rot bedeutet deutlich darunter – oder weit über einer sicheren Obergrenze.',
      });

  String get calcBodyMapWhy => _t({
        'en':
            'Coverage is measured against the Dietary Reference Values (European Food Safety Authority, EFSA), including tolerable upper intake levels where they exist.',
        'pl':
            'Pokrycie jest mierzone względem referencyjnych wartości spożycia (DRV, EFSA), w tym tolerowanych górnych limitów spożycia, jeśli istnieją.',
        'nl':
            'De dekking wordt gemeten ten opzichte van de Dietary Reference Values (Europese Autoriteit voor voedselveiligheid, EFSA), inclusief aanvaardbare bovengrenzen waar die bestaan.',
        'es':
            'La cobertura se mide frente a los Valores Dietéticos de Referencia (Autoridad Europea de Seguridad Alimentaria, EFSA), incluidos los niveles máximos tolerables de ingesta cuando existen.',
        'de':
            'Die Abdeckung wird an den Dietary Reference Values (Europäische Behörde für Lebensmittelsicherheit, EFSA) gemessen, einschließlich tolerierbarer oberer Aufnahmemengen, sofern vorhanden.',
      });

  String get calcGlTitle => _t({
        'en': 'Glycemic load',
        'pl': 'Ładunek glikemiczny',
        'nl': 'Glykemische lading',
        'es': 'Carga glucémica',
        'de': 'Glykämische Last',
      });

  String get calcGlExplain => _t({
        'en':
            'Glycemic load estimates how much a food is likely to raise blood sugar. It combines the food\'s glycemic index with the grams of carbohydrate in the portion (GI × carbs ÷ 100).',
        'pl':
            'Ładunek glikemiczny szacuje, jak bardzo dany produkt może podnieść poziom cukru we krwi. Łączy indeks glikemiczny produktu z liczbą gramów węglowodanów w porcji (IG × węglowodany ÷ 100).',
        'nl':
            'De glykemische lading schat in hoeveel een voedingsmiddel je bloedsuiker waarschijnlijk laat stijgen. Het combineert de glykemische index met het aantal gram koolhydraten in de portie (GI × koolhydraten ÷ 100).',
        'es':
            'La carga glucémica estima cuánto puede elevar un alimento el azúcar en sangre. Combina el índice glucémico del alimento con los gramos de carbohidrato de la porción (IG × carbohidratos ÷ 100).',
        'de':
            'Die glykämische Last schätzt, wie stark ein Lebensmittel den Blutzucker voraussichtlich erhöht. Sie kombiniert den glykämischen Index mit den Gramm Kohlenhydrate der Portion (GI × Kohlenhydrate ÷ 100).',
      });

  String get calcGlWhy => _t({
        'en':
            'It uses the internationally recognised glycemic index/load method used by the European Association for the Study of Diabetes (EASD) in diabetes research.',
        'pl':
            'Wykorzystuje uznaną na świecie metodę indeksu/ładunku glikemicznego stosowaną przez Europejskie Towarzystwo Badań nad Cukrzycą (EASD) w badaniach nad cukrzycą.',
        'nl':
            'Het gebruikt de internationaal erkende methode voor glykemische index/lading die de Europese Vereniging voor de Studie van Diabetes (EASD) in diabetesonderzoek gebruikt.',
        'es':
            'Utiliza el método de índice/carga glucémica reconocido internacionalmente que usa la Asociación Europea para el Estudio de la Diabetes (EASD) en la investigación sobre diabetes.',
        'de':
            'Sie verwendet die international anerkannte Methode des glykämischen Index/der glykämischen Last, die die Europäische Diabetes-Gesellschaft (EASD) in der Diabetesforschung nutzt.',
      });

  String get calcBolusTitle => _t({
        'en': 'Meal insulin estimate',
        'pl': 'Szacunek insuliny do posiłku',
        'nl': 'Schatting maaltijdinsuline',
        'es': 'Estimación de insulina para la comida',
        'de': 'Schätzung Mahlzeiteninsulin',
      });

  String get calcBolusExplain => _t({
        'en':
            'An estimate only. Meal insulin = carbs ÷ your insulin-to-carb ratio, plus a correction = (current glucose − target) ÷ your sensitivity factor, minus any insulin still active (insulin on board).',
        'pl':
            'Tylko szacunek. Insulina do posiłku = węglowodany ÷ Twój przelicznik insulina–węglowodany, plus korekta = (aktualna glikemia − cel) ÷ Twój współczynnik wrażliwości, minus insulina nadal aktywna (insulina aktywna).',
        'nl':
            'Alleen een schatting. Maaltijdinsuline = koolhydraten ÷ jouw insuline-koolhydraatratio, plus een correctie = (huidige glucose − streefwaarde) ÷ jouw gevoeligheidsfactor, min nog actieve insuline (insuline aan boord).',
        'es':
            'Solo una estimación. Insulina de la comida = carbohidratos ÷ tu ratio insulina-carbohidratos, más una corrección = (glucosa actual − objetivo) ÷ tu factor de sensibilidad, menos la insulina aún activa (insulina activa).',
        'de':
            'Nur eine Schätzung. Mahlzeiteninsulin = Kohlenhydrate ÷ dein Insulin-Kohlenhydrat-Verhältnis, plus eine Korrektur = (aktueller Blutzucker − Zielwert) ÷ dein Empfindlichkeitsfaktor, minus noch aktives Insulin (aktives Insulin).',
      });

  String get calcBolusWhy => _t({
        'en':
            'It uses standard carb-counting maths, but every value must be set by your diabetes care team. Always confirm with them — never dose on this number alone.',
        'pl':
            'Wykorzystuje standardowe obliczenia liczenia węglowodanów, ale każdą wartość musi ustalić Twój zespół leczenia cukrzycy. Zawsze potwierdzaj z nimi — nigdy nie dawkuj wyłącznie na podstawie tej liczby.',
        'nl':
            'Het gebruikt standaard koolhydraat-telwiskunde, maar elke waarde moet door je diabetesteam worden ingesteld. Bevestig het altijd met hen — dien nooit insuline toe op alleen dit getal.',
        'es':
            'Usa las matemáticas estándar del conteo de carbohidratos, pero tu equipo de diabetes debe fijar cada valor. Confírmalo siempre con ellos: nunca te dosifiques solo con este número.',
        'de':
            'Sie verwendet die übliche Mathematik der Kohlenhydratzählung, aber jeder Wert muss von deinem Diabetes-Team festgelegt werden. Bestätige ihn immer mit ihnen – dosiere niemals allein anhand dieser Zahl.',
      });

  String get calcIobTitle => _t({
        'en': 'Insulin on board',
        'pl': 'Insulina aktywna',
        'nl': 'Insuline aan boord',
        'es': 'Insulina activa',
        'de': 'Aktives Insulin',
      });

  String get calcIobExplain => _t({
        'en':
            'An estimate of how much of your earlier rapid-acting insulin is still working. It decays steadily from each dose over your set insulin action time, and the remaining amounts are added together.',
        'pl':
            'Szacunek, ile z wcześniejszej insuliny szybko działającej nadal działa. Maleje stopniowo od każdej dawki przez ustawiony czas działania insuliny, a pozostałe ilości są sumowane.',
        'nl':
            'Een schatting van hoeveel van je eerdere snelwerkende insuline nog werkt. Het neemt vanaf elke dosis geleidelijk af over je ingestelde insulinewerkingsduur, en de resterende hoeveelheden worden bij elkaar opgeteld.',
        'es':
            'Una estimación de cuánta de tu insulina rápida anterior sigue actuando. Disminuye de forma constante desde cada dosis durante el tiempo de acción de la insulina que configuraste, y las cantidades restantes se suman.',
        'de':
            'Eine Schätzung, wie viel deines früheren schnell wirkenden Insulins noch wirkt. Es nimmt von jeder Dosis über deine eingestellte Insulinwirkdauer stetig ab, und die verbleibenden Mengen werden addiert.',
      });

  String get calcIobWhy => _t({
        'en':
            'Subtracting active insulin to avoid stacking doses is standard bolus-advisor practice, but your insulin action time must be set with your diabetes care team.',
        'pl':
            'Odejmowanie aktywnej insuliny, aby unikać nakładania się dawek, to standardowa praktyka kalkulatorów bolusa, ale czas działania insuliny musi ustalić Twój zespół leczenia cukrzycy.',
        'nl':
            'Actieve insuline aftrekken om dosissen niet te stapelen is standaard bij bolusadviseurs, maar je insulinewerkingsduur moet met je diabetesteam worden ingesteld.',
        'es':
            'Restar la insulina activa para evitar acumular dosis es práctica estándar de los calculadores de bolo, pero el tiempo de acción de tu insulina debe fijarlo tu equipo de diabetes.',
        'de':
            'Aktives Insulin abzuziehen, um Dosen nicht zu stapeln, ist gängige Praxis von Bolusrechnern, aber deine Insulinwirkdauer muss mit deinem Diabetes-Team festgelegt werden.',
      });

  String get calcRatiosTitle => _t({
        'en': 'Carb ratio & sensitivity factor',
        'pl': 'Przelicznik węglowodanowy i współczynnik wrażliwości',
        'nl': 'Koolhydraatratio & gevoeligheidsfactor',
        'es': 'Ratio de carbohidratos y factor de sensibilidad',
        'de': 'KH-Faktor & Korrekturfaktor',
      });

  String get calcRatiosExplain => _t({
        'en':
            'Your insulin-to-carb ratio is how many grams of carbohydrate one unit of insulin covers. Your sensitivity factor is how much one unit lowers your glucose. You enter these per time of day; the app does not invent them.',
        'pl':
            'Przelicznik insulina–węglowodany to liczba gramów węglowodanów pokrywanych przez jedną jednostkę insuliny. Współczynnik wrażliwości to spadek glikemii po jednej jednostce. Wpisujesz je dla pór dnia; aplikacja ich nie wymyśla.',
        'nl':
            'Je insuline-koolhydraatratio is hoeveel gram koolhydraten één eenheid insuline dekt. Je gevoeligheidsfactor is hoeveel één eenheid je glucose verlaagt. Je voert deze per tijdstip in; de app verzint ze niet.',
        'es':
            'Tu ratio insulina-carbohidratos es cuántos gramos de carbohidrato cubre una unidad de insulina. Tu factor de sensibilidad es cuánto baja la glucosa una unidad. Los introduces por franja horaria; la app no los inventa.',
        'de':
            'Dein Insulin-Kohlenhydrat-Verhältnis gibt an, wie viele Gramm Kohlenhydrate eine Einheit Insulin abdeckt. Dein Korrekturfaktor gibt an, wie stark eine Einheit deinen Blutzucker senkt. Du gibst diese je Tageszeit ein; die App erfindet sie nicht.',
      });

  String get calcRatiosWhy => _t({
        'en':
            'These individualised settings come from your diabetes care team and follow standard carb-counting therapy. Review and confirm them regularly with your clinician.',
        'pl':
            'Te indywidualne ustawienia pochodzą od Twojego zespołu leczenia cukrzycy i są zgodne ze standardową terapią liczenia węglowodanów. Regularnie sprawdzaj je z lekarzem.',
        'nl':
            'Deze persoonlijke instellingen komen van je diabetesteam en volgen standaard koolhydraat-teltherapie. Bespreek en bevestig ze regelmatig met je arts.',
        'es':
            'Estos ajustes individualizados provienen de tu equipo de diabetes y siguen la terapia estándar de conteo de carbohidratos. Revísalos y confírmalos con tu médico con regularidad.',
        'de':
            'Diese individuellen Einstellungen stammen von deinem Diabetes-Team und folgen der üblichen Kohlenhydratzähl-Therapie. Überprüfe und bestätige sie regelmäßig mit deiner Ärztin oder deinem Arzt.',
      });

  String get calcRecsTitle => _t({
        'en': 'Daily recommendations',
        'pl': 'Codzienne zalecenia',
        'nl': 'Dagelijkse aanbevelingen',
        'es': 'Recomendaciones diarias',
        'de': 'Tägliche Empfehlungen',
      });

  String get calcRecsExplain => _t({
        'en':
            'These nudges compare today\'s intake with your goal-specific targets. When protein, carbs, calories or hydration cross 50%, 80% or 100% of your target, a matching tip appears.',
        'pl':
            'Te wskazówki porównują dzisiejsze spożycie z celami dla Twojego celu. Gdy białko, węglowodany, kalorie lub nawodnienie przekroczą 50%, 80% lub 100% celu, pojawia się odpowiednia podpowiedź.',
        'nl':
            'Deze tips vergelijken je inname van vandaag met je doelgerichte targets. Als eiwit, koolhydraten, calorieën of hydratatie 50%, 80% of 100% van je doel passeren, verschijnt een passende tip.',
        'es':
            'Estos consejos comparan tu ingesta de hoy con los objetivos de tu meta. Cuando la proteína, los carbohidratos, las calorías o la hidratación cruzan el 50%, 80% o 100% de tu objetivo, aparece un consejo acorde.',
        'de':
            'Diese Hinweise vergleichen die heutige Zufuhr mit deinen zielspezifischen Vorgaben. Wenn Eiweiß, Kohlenhydrate, Kalorien oder Flüssigkeit 50%, 80% oder 100% deines Ziels überschreiten, erscheint ein passender Tipp.',
      });

  String get calcRecsWhy => _t({
        'en':
            'The thresholds and priorities reflect the EU food-based dietary guidelines. Tips are general guidance, not medical advice.',
        'pl':
            'Progi i priorytety odzwierciedlają unijne wytyczne żywieniowe oparte na żywności. Wskazówki to ogólne porady, a nie porada medyczna.',
        'nl':
            'De drempels en prioriteiten weerspiegelen de EU-voedingsrichtlijnen op basis van voedingsmiddelen. Tips zijn algemene richtlijnen, geen medisch advies.',
        'es':
            'Los umbrales y prioridades reflejan las guías alimentarias de la UE basadas en alimentos. Los consejos son orientación general, no consejo médico.',
        'de':
            'Die Schwellen und Prioritäten orientieren sich an den lebensmittelbasierten Ernährungsrichtlinien der EU. Tipps sind allgemeine Orientierung, kein medizinischer Rat.',
      });

  String get calcStreakTitle => _t({
        'en': 'Logging streak',
        'pl': 'Seria rejestrowania',
        'nl': 'Logreeks',
        'es': 'Racha de registro',
        'de': 'Logging-Serie',
      });

  String get calcStreakExplain => _t({
        'en':
            'Your streak counts consecutive days on which you logged at least one item. Vacation mode keeps a streak alive on days you choose to pause.',
        'pl':
            'Seria liczy kolejne dni, w których zarejestrowano co najmniej jedną pozycję. Tryb wakacyjny utrzymuje serię w dni, które wybierzesz na pauzę.',
        'nl':
            'Je reeks telt opeenvolgende dagen waarop je minstens één item hebt gelogd. Vakantiemodus houdt een reeks in stand op dagen die je pauzeert.',
        'es':
            'Tu racha cuenta los días consecutivos en los que registraste al menos un elemento. El modo vacaciones mantiene la racha en los días que decides pausar.',
        'de':
            'Deine Serie zählt aufeinanderfolgende Tage, an denen du mindestens einen Eintrag erfasst hast. Der Urlaubsmodus hält die Serie an Tagen aufrecht, die du pausierst.',
      });

  String get calcStreakWhy => _t({
        'en':
            'Regular self-monitoring is linked to better dietary adherence in the evidence behind the EU food-based dietary guidelines. The streak is a motivator, not a health measure.',
        'pl':
            'Regularne samokontrolowanie wiąże się z lepszym przestrzeganiem diety w dowodach stojących za unijnymi wytycznymi żywieniowymi. Seria to motywator, a nie miara zdrowia.',
        'nl':
            'Regelmatige zelfmonitoring hangt samen met betere dieettrouw in het bewijs achter de EU-voedingsrichtlijnen. De reeks is een motivator, geen gezondheidsmaat.',
        'es':
            'El autocontrol regular se asocia con una mejor adherencia dietética en la evidencia de las guías alimentarias de la UE. La racha es un motivador, no una medida de salud.',
        'de':
            'Regelmäßige Selbstkontrolle ist in der Evidenz hinter den EU-Ernährungsrichtlinien mit besserer Ernährungstreue verbunden. Die Serie ist ein Motivator, kein Gesundheitsmaß.',
      });

  String get calcBadgesTitle => _t({
        'en': 'Weekly badges',
        'pl': 'Cotygodniowe odznaki',
        'nl': 'Wekelijkse badges',
        'es': 'Insignias semanales',
        'de': 'Wöchentliche Abzeichen',
      });

  String get calcBadgesExplain => _t({
        'en':
            'Badges are awarded for last week\'s habits — for example logging every day, hitting your protein target on several days, or building balanced plates. Each badge has a clear, fixed threshold.',
        'pl':
            'Odznaki przyznawane są za nawyki z ubiegłego tygodnia — np. codzienne rejestrowanie, osiągnięcie celu białkowego w kilku dniach lub komponowanie zbilansowanych talerzy. Każda odznaka ma jasny, stały próg.',
        'nl':
            'Badges worden toegekend voor de gewoonten van vorige week — bijvoorbeeld elke dag loggen, je eiwitdoel op meerdere dagen halen of gebalanceerde borden samenstellen. Elke badge heeft een duidelijke, vaste drempel.',
        'es':
            'Las insignias se otorgan por los hábitos de la semana pasada, por ejemplo registrar cada día, alcanzar tu objetivo de proteína varios días o crear platos equilibrados. Cada insignia tiene un umbral claro y fijo.',
        'de':
            'Abzeichen werden für die Gewohnheiten der letzten Woche vergeben — etwa tägliches Erfassen, das Erreichen deines Eiweißziels an mehreren Tagen oder ausgewogene Teller. Jedes Abzeichen hat eine klare, feste Schwelle.',
      });

  String get calcBadgesWhy => _t({
        'en':
            'The criteria reward the consistency and balance encouraged by the EU food-based dietary guidelines. Badges celebrate habits and are not a health assessment.',
        'pl':
            'Kryteria nagradzają regularność i równowagę zalecane przez unijne wytyczne żywieniowe. Odznaki świętują nawyki i nie są oceną zdrowia.',
        'nl':
            'De criteria belonen de consistentie en balans die de EU-voedingsrichtlijnen aanmoedigen. Badges vieren gewoonten en zijn geen gezondheidsbeoordeling.',
        'es':
            'Los criterios premian la constancia y el equilibrio que fomentan las guías alimentarias de la UE. Las insignias celebran hábitos y no son una evaluación de salud.',
        'de':
            'Die Kriterien belohnen die von den EU-Ernährungsrichtlinien geförderte Beständigkeit und Ausgewogenheit. Abzeichen würdigen Gewohnheiten und sind keine Gesundheitsbewertung.',
      });

  String get calcRecipeMatchTitle => _t({
        'en': 'Why this recipe fits',
        'pl': 'Dlaczego ten przepis pasuje',
        'nl': 'Waarom dit recept past',
        'es': 'Por qué encaja esta receta',
        'de': 'Warum dieses Rezept passt',
      });

  String get calcRecipeMatchExplain => _t({
        'en':
            'Recipes are filtered to your goal: weight loss favours lower-calorie, higher-protein meals; muscle growth needs more protein; diabetes limits carbs and glycemic load; keto caps net carbs; vegan and vegetarian filter by ingredients.',
        'pl':
            'Przepisy są filtrowane pod Twój cel: odchudzanie preferuje posiłki o niższej kaloryczności i wyższej zawartości białka; budowa mięśni wymaga więcej białka; cukrzyca ogranicza węglowodany i ładunek glikemiczny; keto ogranicza węglowodany netto; wegańskie i wegetariańskie filtrują po składnikach.',
        'nl':
            'Recepten worden gefilterd op je doel: gewichtsverlies kiest caloriearmere, eiwitrijkere maaltijden; spiergroei vraagt meer eiwit; diabetes beperkt koolhydraten en glykemische lading; keto begrenst netto koolhydraten; veganistisch en vegetarisch filteren op ingrediënten.',
        'es':
            'Las recetas se filtran según tu objetivo: perder peso prefiere comidas con menos calorías y más proteína; ganar músculo necesita más proteína; la diabetes limita carbohidratos y carga glucémica; keto limita los carbohidratos netos; vegano y vegetariano filtran por ingredientes.',
        'de':
            'Rezepte werden nach deinem Ziel gefiltert: Abnehmen bevorzugt kalorienärmere, eiweißreichere Mahlzeiten; Muskelaufbau braucht mehr Eiweiß; Diabetes begrenzt Kohlenhydrate und glykämische Last; Keto begrenzt Netto-Kohlenhydrate; vegan und vegetarisch filtern nach Zutaten.',
      });

  String get calcRecipeMatchWhy => _t({
        'en':
            'The thresholds follow goal-specific guidance from the EU food-based dietary guidelines and standard clinical nutrition. They help you browse, but you can still see every recipe.',
        'pl':
            'Progi są zgodne z zaleceniami dla danego celu z unijnych wytycznych żywieniowych i standardowej dietetyki klinicznej. Pomagają przeglądać, ale nadal widzisz wszystkie przepisy.',
        'nl':
            'De drempels volgen doelgerichte richtlijnen uit de EU-voedingsrichtlijnen en standaard klinische voeding. Ze helpen je bladeren, maar je ziet nog steeds elk recept.',
        'es':
            'Los umbrales siguen las pautas específicas por objetivo de las guías alimentarias de la UE y la nutrición clínica estándar. Te ayudan a explorar, pero aún puedes ver todas las recetas.',
        'de':
            'Die Schwellen folgen zielspezifischen Vorgaben der lebensmittelbasierten Ernährungsrichtlinien der EU und der üblichen klinischen Ernährung. Sie helfen beim Stöbern, aber du siehst weiterhin jedes Rezept.',
      });

  String get foodUpdated => _t({
        'en': 'Food updated',
        'pl': 'Żywność zaktualizowana',
        'nl': 'Voedsel bijgewerkt',
        'es': 'Alimento actualizado',
        'de': 'Lebensmittel aktualisiert',
      });

  String get editFood => _t({
        'en': 'Edit Food',
        'pl': 'Edytuj żywność',
        'nl': 'Voedsel bewerken',
        'es': 'Editar alimento',
        'de': 'Lebensmittel bearbeiten',
      });

  String get editIngredients => _t({
        'en': 'Edit ingredients',
        'pl': 'Edytuj składniki',
        'nl': 'Ingrediënten bewerken',
        'es': 'Editar ingredientes',
        'de': 'Zutaten bearbeiten',
      });

  String get kcalPer100g => _t({
        'en': 'kcal/100g',
        'pl': 'kcal/100g',
        'nl': 'kcal/100g',
        'es': 'kcal/100g',
        'de': 'kcal/100g',
      });

  // ── Home extras ──

  String get removeFood => _t({
        'en': 'Remove Food',
        'pl': 'Usuń jedzenie',
        'nl': 'Voedsel verwijderen',
        'es': 'Eliminar alimento',
        'de': 'Lebensmittel entfernen',
      });

  String get dailyWaterGoal => _t({
        'en': 'Daily Water Goal',
        'pl': 'Dzienny cel wody',
        'nl': 'Dagelijks waterdoel',
        'es': 'Objetivo de agua diario',
        'de': 'Tägliches Wasserziel',
      });

  String get caloriesKcal => _t({
        'en': 'Calories (kcal)',
        'pl': 'Kalorie (kcal)',
        'nl': 'Calorieën (kcal)',
        'es': 'Calorías (kcal)',
        'de': 'Kalorien (kcal)',
      });

  String get todaysFoods => _t({
        'en': "Today's Foods",
        'pl': 'Dzisiejsze jedzenie',
        'nl': 'Voeding van vandaag',
        'es': 'Comidas de hoy',
        'de': 'Heutige Mahlzeiten',
      });

  String get scanHistory => _t({
        'en': 'Scan History',
        'pl': 'Historia skanów',
        'nl': 'Scangeschiedenis',
        'es': 'Historial de escaneos',
        'de': 'Scan-Verlauf',
      });

  String get waterMinMax => _t({
        'en': 'Min 2.0 L · Max 3.5 L',
        'pl': 'Min 2,0 L · Maks 3,5 L',
        'nl': 'Min 2,0 L · Max 3,5 L',
        'es': 'Mín 2,0 L · Máx 3,5 L',
        'de': 'Min 2,0 L · Max 3,5 L',
      });

  String waterLogged(int ml, String label) => _t({
        'en': '$ml ml $label logged',
        'pl': 'Zapisano $ml ml $label',
        'nl': '$ml ml $label gelogd',
        'es': '$ml ml de $label registrado',
        'de': '$ml ml $label erfasst',
      });

  String waterRemoved(int ml) => _t({
        'en': '-$ml ml removed',
        'pl': 'Usunięto -$ml ml',
        'nl': '-$ml ml verwijderd',
        'es': '-$ml ml eliminado',
        'de': '-$ml ml entfernt',
      });

  String waterAdded(int ml) => _t({
        'en': '+$ml ml added',
        'pl': 'Dodano +$ml ml',
        'nl': '+$ml ml toegevoegd',
        'es': '+$ml ml añadido',
        'de': '+$ml ml hinzugefügt',
      });

  // ── Food Database ──

  String get foodDatabase => _t({
        'en': 'Food Database',
        'pl': 'Baza żywności',
        'nl': 'Voedingsdatabase',
        'es': 'Base de alimentos',
        'de': 'Lebensmittel-Datenbank',
      });

  String get fillAllFields => _t({
        'en': 'Please fill all fields',
        'pl': 'Wypełnij wszystkie pola',
        'nl': 'Vul alle velden in',
        'es': 'Por favor completa todos los campos',
        'de': 'Bitte alle Felder ausfüllen',
      });

  String get addedToDatabase => _t({
        'en': 'added to database',
        'pl': 'dodano do bazy danych',
        'nl': 'toegevoegd aan database',
        'es': 'agregado a la base de datos',
        'de': 'zur Datenbank hinzugefügt',
      });

  String get addCustomFood => _t({
        'en': 'Add Custom Food',
        'pl': 'Dodaj własne jedzenie',
        'nl': 'Aangepast voedsel toevoegen',
        'es': 'Agregar alimento personalizado',
        'de': 'Eigenes Lebensmittel hinzufügen',
      });

  String get addFood => _t({
        'en': 'Add Food',
        'pl': 'Dodaj jedzenie',
        'nl': 'Voedsel toevoegen',
        'es': 'Agregar alimento',
        'de': 'Lebensmittel hinzufügen',
      });

  // ── Ground Truth ──

  String get groundTruth => _t({
        'en': 'Ground Truth',
        'pl': 'Dane referencyjne',
        'nl': 'Ground Truth',
        'es': 'Datos de referencia',
        'de': 'Referenzdaten',
      });

  String get enterValidWeight => _t({
        'en': 'Please enter a valid weight in grams',
        'pl': 'Proszę podać prawidłową wagę w gramach',
        'nl': 'Voer een geldig gewicht in grammen in',
        'es': 'Por favor ingresa un peso válido en gramos',
        'de': 'Bitte gib ein gültiges Gewicht in Gramm ein',
      });

  // ── Create Meal ──

  String get takePhoto => _t({
        'en': 'Take a photo',
        'pl': 'Zrób zdjęcie',
        'nl': 'Maak een foto',
        'es': 'Tomar una foto',
        'de': 'Foto machen',
      });

  String get chooseFromGallery => _t({
        'en': 'Choose from gallery',
        'pl': 'Wybierz z galerii',
        'nl': 'Kies uit galerij',
        'es': 'Elegir de la galería',
        'de': 'Aus Galerie wählen',
      });

  String get removePhoto => _t({
        'en': 'Remove photo',
        'pl': 'Usuń zdjęcie',
        'nl': 'Foto verwijderen',
        'es': 'Eliminar foto',
        'de': 'Foto entfernen',
      });

  String get addIngredient => _t({
        'en': 'Add at least one ingredient.',
        'pl': 'Dodaj przynajmniej jeden składnik.',
        'nl': 'Voeg minstens één ingrediënt toe.',
        'es': 'Agrega al menos un ingrediente.',
        'de': 'Füge mindestens eine Zutat hinzu.',
      });

  String get noIngredientsYet => _t({
        'en': 'No ingredients yet',
        'pl': 'Brak składników',
        'nl': 'Nog geen ingrediënten',
        'es': 'Aún no hay ingredientes',
        'de': 'Noch keine Zutaten',
      });

  // ── Nutrition Dashboard ──

  String get todaysNutrition => _t({
        'en': 'Today\'s Nutrition',
        'pl': 'Dzisiejsze odżywianie',
        'nl': 'Voeding van vandaag',
        'es': 'Nutrición de hoy',
        'de': 'Heutige Ernährung',
      });

  // ── Common UI ──

  String get continueBtn => _t({
        'en': 'Continue',
        'pl': 'Kontynuuj',
        'nl': 'Doorgaan',
        'es': 'Continuar',
        'de': 'Weiter',
      });

  String get skip => _t({
        'en': 'Skip',
        'pl': 'Pomiń',
        'nl': 'Overslaan',
        'es': 'Omitir',
        'de': 'Überspringen',
      });

  String get log => _t({
        'en': 'Log',
        'pl': 'Zaloguj',
        'nl': 'Loggen',
        'es': 'Registrar',
        'de': 'Loggen',
      });

  String nMeals(int n) {
    if (_lang == 'pl') return '$n posiłków';
    if (_lang == 'nl') return '$n maaltijden';
    if (_lang == 'es') return '$n comidas';
    if (_lang == 'de') return '$n Mahlzeiten';
    return '$n meals';
  }

  String itemsAdded(int n) {
    if (_lang == 'pl') return '$n elementów dodanych do listy zakupów!';
    if (_lang == 'nl') return '$n items toegevoegd aan boodschappenlijst!';
    if (_lang == 'es') return '¡$n artículos añadidos a la lista de compras!';
    if (_lang == 'de') return '$n Artikel zur Einkaufsliste hinzugefügt!';
    return '$n items added to your grocery list!';
  }

  // ── Body map ──

  String get bestFoodFocus => _t({
        'en': 'Best food focus',
        'pl': 'Najlepszy wybór żywności',
        'nl': 'Beste voedingsfocus',
        'es': 'Mejor enfoque alimentario',
        'de': 'Bester Ernährungsfokus',
      });

  String get todaysSignal => _t({
        'en': "Today's signal",
        'pl': 'Dzisiejszy sygnał',
        'nl': 'Signaal van vandaag',
        'es': 'Señal de hoy',
        'de': 'Heutiges Signal',
      });

  String get keyNutrientsToday => _t({
        'en': 'Key nutrients today',
        'pl': 'Kluczowe składniki dziś',
        'nl': 'Belangrijkste voedingsstoffen vandaag',
        'es': 'Nutrientes clave hoy',
        'de': 'Wichtige Nährstoffe heute',
      });

  String percentNourished(int pct) => _t({
        'en': '$pct% nourished today',
        'pl': '$pct% odżywienia dziś',
        'nl': '$pct% gevoed vandaag',
        'es': '$pct% nutrido hoy',
        'de': '$pct% genährt heute',
      });

  String organLabel(String key) {
    switch (key) {
      case 'brain':
        return _t({'en': 'Brain', 'pl': 'Mózg', 'nl': 'Hersenen', 'es': 'Cerebro', 'de': 'Gehirn'});
      case 'eyes':
        return _t({'en': 'Eyes', 'pl': 'Oczy', 'nl': 'Ogen', 'es': 'Ojos', 'de': 'Augen'});
      case 'lungs':
        return _t({'en': 'Lungs', 'pl': 'Płuca', 'nl': 'Longen', 'es': 'Pulmones', 'de': 'Lunge'});
      case 'heart':
        return _t({'en': 'Heart', 'pl': 'Serce', 'nl': 'Hart', 'es': 'Corazón', 'de': 'Herz'});
      case 'liver':
        return _t({'en': 'Liver', 'pl': 'Wątroba', 'nl': 'Lever', 'es': 'Hígado', 'de': 'Leber'});
      case 'stomach':
        return _t({'en': 'Stomach', 'pl': 'Żołądek', 'nl': 'Maag', 'es': 'Estómago', 'de': 'Magen'});
      case 'intestines':
        return _t({'en': 'Intestines', 'pl': 'Jelita', 'nl': 'Darmen', 'es': 'Intestinos', 'de': 'Darm'});
      case 'kidneys':
        return _t({'en': 'Kidneys', 'pl': 'Nerki', 'nl': 'Nieren', 'es': 'Riñones', 'de': 'Nieren'});
      case 'bones':
        return _t({'en': 'Bones', 'pl': 'Kości', 'nl': 'Botten', 'es': 'Huesos', 'de': 'Knochen'});
      case 'muscles':
        return _t({'en': 'Muscles', 'pl': 'Mięśnie', 'nl': 'Spieren', 'es': 'Músculos', 'de': 'Muskeln'});
      case 'skin':
        return _t({'en': 'Skin', 'pl': 'Skóra', 'nl': 'Huid', 'es': 'Piel', 'de': 'Haut'});
      case 'blood':
        return _t({'en': 'Blood', 'pl': 'Krew', 'nl': 'Bloed', 'es': 'Sangre', 'de': 'Blut'});
      default:
        return key;
    }
  }

  String organExplanation(String key) {
    switch (key) {
      case 'brain':
        return _t({
          'en': 'B12 and folate keep nerves firing. Iron carries oxygen to brain tissue and supports focus and memory.',
          'pl': 'B12 i kwas foliowy utrzymują pracę nerwów. Żelazo dostarcza tlen do mózgu i wspiera koncentrację i pamięć.',
          'nl': 'B12 en foliumzuur houden de zenuwen actief. IJzer brengt zuurstof naar hersenweefsel en ondersteunt focus en geheugen.',
          'es': 'La B12 y el folato mantienen activos los nervios. El hierro lleva oxígeno al cerebro y favorece la concentración y la memoria.',
          'de': 'B12 und Folat halten die Nerven aktiv. Eisen transportiert Sauerstoff ins Hirngewebe und unterstützt Konzentration und Gedächtnis.',
        });
      case 'eyes':
        return _t({
          'en': 'Vitamin A is essential for night vision. Vitamin C and zinc protect against age-related macular degeneration.',
          'pl': 'Witamina A jest niezbędna do widzenia w nocy. Witamina C i cynk chronią przed zwyrodnieniem plamki żółtej.',
          'nl': 'Vitamine A is essentieel voor nachtzicht. Vitamine C en zink beschermen tegen leeftijdsgebonden maculadegeneratie.',
          'es': 'La vitamina A es esencial para la visión nocturna. La vitamina C y el zinc protegen contra la degeneración macular.',
          'de': 'Vitamin A ist wichtig für das Nachtsehen. Vitamin C und Zink schützen vor altersbedingter Makuladegeneration.',
        });
      case 'lungs':
        return _t({
          'en': 'Antioxidants like vitamin C, E and A defend lung tissue against oxidative stress and inflammation.',
          'pl': 'Antyoksydanty jak witamina C, E i A chronią tkankę płuc przed stresem oksydacyjnym i stanem zapalnym.',
          'nl': 'Antioxidanten zoals vitamine C, E en A beschermen longweefsel tegen oxidatieve stress en ontsteking.',
          'es': 'Antioxidantes como las vitaminas C, E y A defienden el tejido pulmonar del estrés oxidativo y la inflamación.',
          'de': 'Antioxidantien wie Vitamin C, E und A schützen das Lungengewebe vor oxidativem Stress und Entzündungen.',
        });
      case 'heart':
        return _t({
          'en': 'Potassium regulates heartbeat, magnesium relaxes blood vessels, and vitamin E protects cells from oxidative damage.',
          'pl': 'Potas reguluje rytm serca, magnez rozluźnia naczynia, a witamina E chroni komórki przed uszkodzeniem oksydacyjnym.',
          'nl': 'Kalium reguleert de hartslag, magnesium ontspant bloedvaten en vitamine E beschermt cellen tegen oxidatieve schade.',
          'es': 'El potasio regula el latido, el magnesio relaja los vasos y la vitamina E protege las células del daño oxidativo.',
          'de': 'Kalium reguliert den Herzschlag, Magnesium entspannt die Gefäße und Vitamin E schützt Zellen vor oxidativen Schäden.',
        });
      case 'liver':
        return _t({
          'en': 'The liver stores fat-soluble vitamins. Vitamin K supports clotting; B12 is processed and stored here.',
          'pl': 'Wątroba magazynuje witaminy rozpuszczalne w tłuszczach. Witamina K wspiera krzepnięcie; B12 jest tu przetwarzana i magazynowana.',
          'nl': 'De lever slaat vetoplosbare vitamines op. Vitamine K ondersteunt de bloedstolling; B12 wordt hier verwerkt en opgeslagen.',
          'es': 'El hígado almacena vitaminas liposolubles. La vitamina K favorece la coagulación; la B12 se procesa y almacena aquí.',
          'de': 'Die Leber speichert fettlösliche Vitamine. Vitamin K unterstützt die Gerinnung; B12 wird hier verarbeitet und gespeichert.',
        });
      case 'stomach':
        return _t({
          'en': 'Zinc maintains the stomach lining. B-vitamins support the production of digestive enzymes.',
          'pl': 'Cynk utrzymuje błonę śluzową żołądka. Witaminy z grupy B wspierają produkcję enzymów trawiennych.',
          'nl': 'Zink onderhoudt de maagwand. B-vitamines ondersteunen de aanmaak van spijsverteringsenzymen.',
          'es': 'El zinc mantiene la mucosa del estómago. Las vitaminas B apoyan la producción de enzimas digestivas.',
          'de': 'Zink erhält die Magenschleimhaut. B-Vitamine unterstützen die Bildung von Verdauungsenzymen.',
        });
      case 'intestines':
        return _t({
          'en': 'Dietary fiber feeds healthy gut bacteria. Magnesium and potassium keep intestinal muscles contracting smoothly.',
          'pl': 'Błonnik odżywia zdrowe bakterie jelitowe. Magnez i potas zapewniają płynne skurcze mięśni jelit.',
          'nl': 'Vezels voeden gezonde darmbacteriën. Magnesium en kalium houden de darmspieren soepel samentrekken.',
          'es': 'La fibra alimenta las bacterias intestinales sanas. El magnesio y el potasio mantienen los músculos intestinales en movimiento.',
          'de': 'Ballaststoffe nähren gesunde Darmbakterien. Magnesium und Kalium halten die Darmmuskulatur geschmeidig in Bewegung.',
        });
      case 'kidneys':
        return _t({
          'en': 'Potassium and magnesium balance helps the kidneys filter waste; staying hydrated reduces kidney load.',
          'pl': 'Równowaga potasu i magnezu pomaga nerkom filtrować odpady; nawodnienie zmniejsza obciążenie nerek.',
          'nl': 'Een balans van kalium en magnesium helpt de nieren afval te filteren; goed hydrateren verlaagt de nierbelasting.',
          'es': 'El equilibrio de potasio y magnesio ayuda a los riñones a filtrar desechos; hidratarse reduce su carga.',
          'de': 'Ein Gleichgewicht von Kalium und Magnesium hilft den Nieren beim Filtern; ausreichend trinken entlastet die Nieren.',
        });
      case 'bones':
        return _t({
          'en': 'Calcium builds bone density. Vitamin D drives calcium absorption. Vitamin K guides calcium into bone, not arteries.',
          'pl': 'Wapń buduje gęstość kości. Witamina D napędza wchłanianie wapnia. Witamina K kieruje wapń do kości, a nie do tętnic.',
          'nl': 'Calcium bouwt botdichtheid op. Vitamine D stimuleert calciumopname. Vitamine K leidt calcium naar bot, niet naar slagaders.',
          'es': 'El calcio aumenta la densidad ósea. La vitamina D impulsa su absorción. La vitamina K dirige el calcio al hueso, no a las arterias.',
          'de': 'Kalzium baut Knochendichte auf. Vitamin D fördert die Aufnahme. Vitamin K lenkt Kalzium in die Knochen, nicht in die Arterien.',
        });
      case 'muscles':
        return _t({
          'en': 'Magnesium and potassium prevent cramps. Calcium triggers contraction. Adequate protein repairs muscle fibers.',
          'pl': 'Magnez i potas zapobiegają skurczom. Wapń wyzwala skurcz. Odpowiednia ilość białka naprawia włókna mięśniowe.',
          'nl': 'Magnesium en kalium voorkomen kramp. Calcium zet de samentrekking in gang. Voldoende eiwit herstelt spiervezels.',
          'es': 'El magnesio y el potasio previenen calambres. El calcio activa la contracción. Suficiente proteína repara las fibras musculares.',
          'de': 'Magnesium und Kalium verhindern Krämpfe. Kalzium löst die Kontraktion aus. Genug Protein repariert Muskelfasern.',
        });
      case 'skin':
        return _t({
          'en': 'Vitamin C builds collagen, vitamin E shields against UV damage, and zinc accelerates wound healing.',
          'pl': 'Witamina C buduje kolagen, witamina E chroni przed promieniowaniem UV, a cynk przyspiesza gojenie ran.',
          'nl': 'Vitamine C bouwt collageen op, vitamine E beschermt tegen UV-schade en zink versnelt wondgenezing.',
          'es': 'La vitamina C forma colágeno, la vitamina E protege del daño UV y el zinc acelera la cicatrización.',
          'de': 'Vitamin C bildet Kollagen, Vitamin E schützt vor UV-Schäden und Zink beschleunigt die Wundheilung.',
        });
      case 'blood':
        return _t({
          'en': 'Iron is the core of haemoglobin. B12 and folate are required to produce healthy red blood cells.',
          'pl': 'Żelazo jest rdzeniem hemoglobiny. B12 i kwas foliowy są potrzebne do produkcji zdrowych czerwonych krwinek.',
          'nl': 'IJzer is de kern van hemoglobine. B12 en foliumzuur zijn nodig om gezonde rode bloedcellen te maken.',
          'es': 'El hierro es el núcleo de la hemoglobina. La B12 y el folato son necesarios para producir glóbulos rojos sanos.',
          'de': 'Eisen ist der Kern des Hämoglobins. B12 und Folat werden für gesunde rote Blutkörperchen benötigt.',
        });
      default:
        return '';
    }
  }

  String organFoodFocus(String key) {
    switch (key) {
      case 'brain':
        return _t({
          'en': 'Prioritise eggs, fish, dairy, lean meat, legumes, leafy greens, and iron-rich foods paired with vitamin C.',
          'pl': 'Stawiaj na jajka, ryby, nabiał, chude mięso, rośliny strączkowe, zielone warzywa i produkty bogate w żelazo z witaminą C.',
          'nl': 'Geef prioriteit aan eieren, vis, zuivel, mager vlees, peulvruchten, bladgroenten en ijzerrijke voeding met vitamine C.',
          'es': 'Prioriza huevos, pescado, lácteos, carne magra, legumbres, verduras de hoja y alimentos ricos en hierro con vitamina C.',
          'de': 'Bevorzuge Eier, Fisch, Milchprodukte, mageres Fleisch, Hülsenfrüchte, Blattgemüse und eisenreiche Lebensmittel mit Vitamin C.',
        });
      case 'eyes':
        return _t({
          'en': 'Look for carrots, sweet potato, spinach, bell pepper, citrus, eggs, shellfish, seeds, and zinc-rich proteins.',
          'pl': 'Wybieraj marchew, bataty, szpinak, paprykę, cytrusy, jajka, owoce morza, nasiona i białka bogate w cynk.',
          'nl': 'Kies voor wortels, zoete aardappel, spinazie, paprika, citrus, eieren, schaaldieren, zaden en zinkrijke eiwitten.',
          'es': 'Busca zanahorias, batata, espinacas, pimiento, cítricos, huevos, mariscos, semillas y proteínas ricas en zinc.',
          'de': 'Achte auf Karotten, Süßkartoffeln, Spinat, Paprika, Zitrusfrüchte, Eier, Meeresfrüchte, Samen und zinkreiche Proteine.',
        });
      case 'lungs':
        return _t({
          'en': 'Colourful fruit, leafy greens, nuts, seeds, olive oil, and vitamin C-rich produce help cover antioxidant needs.',
          'pl': 'Kolorowe owoce, zielone warzywa, orzechy, nasiona, oliwa i produkty bogate w witaminę C pokrywają potrzeby antyoksydacyjne.',
          'nl': 'Kleurrijk fruit, bladgroenten, noten, zaden, olijfolie en vitamine C-rijke producten dekken de antioxidantbehoefte.',
          'es': 'Frutas coloridas, verduras de hoja, frutos secos, semillas, aceite de oliva y productos ricos en vitamina C cubren los antioxidantes.',
          'de': 'Buntes Obst, Blattgemüse, Nüsse, Samen, Olivenöl und Vitamin-C-reiche Produkte decken den Antioxidantienbedarf.',
        });
      case 'heart':
        return _t({
          'en': 'Potassium-rich fruit and vegetables, legumes, nuts, seeds, whole grains, and magnesium-rich foods are most useful.',
          'pl': 'Najlepsze są owoce i warzywa bogate w potas, rośliny strączkowe, orzechy, nasiona, pełne ziarna i produkty bogate w magnez.',
          'nl': 'Kaliumrijk fruit en groenten, peulvruchten, noten, zaden, volle granen en magnesiumrijke voeding zijn het nuttigst.',
          'es': 'Frutas y verduras ricas en potasio, legumbres, frutos secos, semillas, granos integrales y alimentos ricos en magnesio son lo más útil.',
          'de': 'Kaliumreiches Obst und Gemüse, Hülsenfrüchte, Nüsse, Samen, Vollkorn und magnesiumreiche Lebensmittel sind am nützlichsten.',
        });
      case 'liver':
        return _t({
          'en': 'Use eggs, leafy greens, fermented dairy, fish, nuts, seeds, and varied proteins to cover K, E, and B12.',
          'pl': 'Jedz jajka, zielone warzywa, fermentowany nabiał, ryby, orzechy, nasiona i różne białka, aby pokryć K, E i B12.',
          'nl': 'Gebruik eieren, bladgroenten, gefermenteerde zuivel, vis, noten, zaden en gevarieerde eiwitten voor K, E en B12.',
          'es': 'Usa huevos, verduras de hoja, lácteos fermentados, pescado, frutos secos, semillas y proteínas variadas para cubrir K, E y B12.',
          'de': 'Nutze Eier, Blattgemüse, fermentierte Milchprodukte, Fisch, Nüsse, Samen und vielfältige Proteine für K, E und B12.',
        });
      case 'stomach':
        return _t({
          'en': 'Zinc-rich seafood, meat, legumes, dairy, eggs, and B-vitamin foods support the stomach lining and digestion.',
          'pl': 'Owoce morza bogate w cynk, mięso, strączki, nabiał, jajka i produkty z witaminami B wspierają błonę żołądka i trawienie.',
          'nl': 'Zinkrijke zeevruchten, vlees, peulvruchten, zuivel, eieren en B-vitamine voeding ondersteunen de maagwand en spijsvertering.',
          'es': 'Mariscos ricos en zinc, carne, legumbres, lácteos, huevos y alimentos con vitamina B apoyan la mucosa gástrica y la digestión.',
          'de': 'Zinkreiche Meeresfrüchte, Fleisch, Hülsenfrüchte, Milchprodukte, Eier und B-Vitamin-Lebensmittel unterstützen Magenschleimhaut und Verdauung.',
        });
      case 'intestines':
        return _t({
          'en': 'Beans, lentils, oats, whole grains, vegetables, fruit, nuts, seeds, and enough fluids are the strongest levers.',
          'pl': 'Fasola, soczewica, owies, pełne ziarna, warzywa, owoce, orzechy, nasiona i dość płynów to najsilniejsze dźwignie.',
          'nl': 'Bonen, linzen, haver, volle granen, groenten, fruit, noten, zaden en voldoende vocht zijn de sterkste hefbomen.',
          'es': 'Frijoles, lentejas, avena, granos integrales, verduras, fruta, frutos secos, semillas y suficientes líquidos son las mayores palancas.',
          'de': 'Bohnen, Linsen, Hafer, Vollkorn, Gemüse, Obst, Nüsse, Samen und ausreichend Flüssigkeit sind die stärksten Hebel.',
        });
      case 'kidneys':
        return _t({
          'en': 'Hydration plus balanced potassium and magnesium from fruit, vegetables, legumes, and nuts supports filtering.',
          'pl': 'Nawodnienie oraz zbilansowany potas i magnez z owoców, warzyw, strączków i orzechów wspierają filtrację.',
          'nl': 'Hydratatie plus uitgebalanceerd kalium en magnesium uit fruit, groenten, peulvruchten en noten ondersteunt de filtering.',
          'es': 'La hidratación más un equilibrio de potasio y magnesio de fruta, verduras, legumbres y frutos secos apoya el filtrado.',
          'de': 'Flüssigkeit sowie ausgewogenes Kalium und Magnesium aus Obst, Gemüse, Hülsenfrüchten und Nüssen unterstützen die Filterung.',
        });
      case 'bones':
        return _t({
          'en': 'Dairy or fortified alternatives, sardines, tofu, leafy greens, eggs, fish, and vitamin K vegetables support bone strength.',
          'pl': 'Nabiał lub wzbogacone zamienniki, sardynki, tofu, zielone warzywa, jajka, ryby i warzywa z witaminą K wspierają kości.',
          'nl': 'Zuivel of verrijkte alternatieven, sardines, tofu, bladgroenten, eieren, vis en vitamine K-groenten ondersteunen sterke botten.',
          'es': 'Lácteos o alternativas fortificadas, sardinas, tofu, verduras de hoja, huevos, pescado y verduras con vitamina K fortalecen los huesos.',
          'de': 'Milchprodukte oder angereicherte Alternativen, Sardinen, Tofu, Blattgemüse, Eier, Fisch und Vitamin-K-Gemüse stärken die Knochen.',
        });
      case 'muscles':
        return _t({
          'en': 'Pair protein with magnesium, potassium, and calcium from dairy, legumes, potatoes, bananas, nuts, and greens.',
          'pl': 'Łącz białko z magnezem, potasem i wapniem z nabiału, strączków, ziemniaków, bananów, orzechów i zielonych warzyw.',
          'nl': 'Combineer eiwit met magnesium, kalium en calcium uit zuivel, peulvruchten, aardappelen, bananen, noten en groenten.',
          'es': 'Combina proteína con magnesio, potasio y calcio de lácteos, legumbres, patatas, plátanos, frutos secos y verduras.',
          'de': 'Kombiniere Protein mit Magnesium, Kalium und Kalzium aus Milchprodukten, Hülsenfrüchten, Kartoffeln, Bananen, Nüssen und Grünzeug.',
        });
      case 'skin':
        return _t({
          'en': 'Vitamin C fruit, nuts, seeds, avocado, olive oil, seafood, legumes, and zinc-rich proteins help collagen and repair.',
          'pl': 'Owoce z witaminą C, orzechy, nasiona, awokado, oliwa, owoce morza, strączki i białka bogate w cynk wspierają kolagen i regenerację.',
          'nl': 'Vitamine C-fruit, noten, zaden, avocado, olijfolie, zeevruchten, peulvruchten en zinkrijke eiwitten helpen collageen en herstel.',
          'es': 'Frutas con vitamina C, frutos secos, semillas, aguacate, aceite de oliva, mariscos, legumbres y proteínas ricas en zinc ayudan al colágeno y la reparación.',
          'de': 'Vitamin-C-Obst, Nüsse, Samen, Avocado, Olivenöl, Meeresfrüchte, Hülsenfrüchte und zinkreiche Proteine fördern Kollagen und Heilung.',
        });
      case 'blood':
        return _t({
          'en': 'Iron, B12, and folate come from red meat, fish, eggs, dairy, legumes, spinach, fortified grains, and citrus pairings.',
          'pl': 'Żelazo, B12 i kwas foliowy pochodzą z czerwonego mięsa, ryb, jaj, nabiału, strączków, szpinaku, wzbogaconych zbóż i cytrusów.',
          'nl': 'IJzer, B12 en foliumzuur komen uit rood vlees, vis, eieren, zuivel, peulvruchten, spinazie, verrijkte granen en citrus.',
          'es': 'El hierro, la B12 y el folato vienen de carne roja, pescado, huevos, lácteos, legumbres, espinacas, granos fortificados y cítricos.',
          'de': 'Eisen, B12 und Folat stammen aus rotem Fleisch, Fisch, Eiern, Milchprodukten, Hülsenfrüchten, Spinat, angereichertem Getreide und Zitrusfrüchten.',
        });
      default:
        return '';
    }
  }

  String organCoverageNoData(String organLower) => _t({
        'en': 'No meaningful nutrient data has been logged yet, so $organLower cannot be assessed today.',
        'pl': 'Nie zarejestrowano jeszcze istotnych danych o składnikach, więc $organLower nie można dziś ocenić.',
        'nl': 'Er zijn nog geen relevante voedingsgegevens gelogd, dus $organLower kan vandaag niet worden beoordeeld.',
        'es': 'Aún no se han registrado datos de nutrientes relevantes, así que $organLower no se puede evaluar hoy.',
        'de': 'Es wurden noch keine aussagekräftigen Nährstoffdaten erfasst, daher kann $organLower heute nicht bewertet werden.',
      });

  String organCoverageLow(int pct) => _t({
        'en': '$pct% coverage: this area is missing several key nutrients today. Add one or two food sources from the list above.',
        'pl': '$pct% pokrycia: temu obszarowi brakuje dziś kilku kluczowych składników. Dodaj jedno lub dwa źródła z listy powyżej.',
        'nl': '$pct% dekking: dit gebied mist vandaag enkele belangrijke voedingsstoffen. Voeg een of twee bronnen uit de lijst hierboven toe.',
        'es': '$pct% de cobertura: a esta zona le faltan hoy varios nutrientes clave. Añade una o dos fuentes de la lista anterior.',
        'de': '$pct% Abdeckung: Diesem Bereich fehlen heute mehrere wichtige Nährstoffe. Füge ein oder zwei Quellen aus der Liste oben hinzu.',
      });

  String organCoverageImproving(int pct) => _t({
        'en': '$pct% coverage: improving, but still below the target range for this body part.',
        'pl': '$pct% pokrycia: poprawia się, ale wciąż poniżej zakresu docelowego dla tej części ciała.',
        'nl': '$pct% dekking: verbetert, maar nog onder het streefbereik voor dit lichaamsdeel.',
        'es': '$pct% de cobertura: mejorando, pero aún por debajo del rango objetivo para esta parte del cuerpo.',
        'de': '$pct% Abdeckung: verbessert sich, liegt aber noch unter dem Zielbereich für diesen Körperteil.',
      });

  String organCoverageHealthy(int pct) => _t({
        'en': '$pct% coverage: this is in the healthy target zone for today.',
        'pl': '$pct% pokrycia: to mieści się dziś w zdrowej strefie docelowej.',
        'nl': '$pct% dekking: dit zit vandaag in de gezonde streefzone.',
        'es': '$pct% de cobertura: esto está hoy en la zona objetivo saludable.',
        'de': '$pct% Abdeckung: das liegt heute in der gesunden Zielzone.',
      });

  String organCoverageAbove(int pct) => _t({
        'en': '$pct% coverage: above target. Usually okay short term, but the map starts warning when intake keeps rising.',
        'pl': '$pct% pokrycia: powyżej celu. Zwykle okej na krótko, ale mapa ostrzega, gdy spożycie wciąż rośnie.',
        'nl': '$pct% dekking: boven het doel. Meestal kortdurend prima, maar de kaart waarschuwt als de inname blijft stijgen.',
        'es': '$pct% de cobertura: por encima del objetivo. Suele estar bien a corto plazo, pero el mapa avisa si la ingesta sigue subiendo.',
        'de': '$pct% Abdeckung: über dem Ziel. Kurzfristig meist okay, aber die Karte warnt, wenn die Zufuhr weiter steigt.',
      });

  String organCoverageVeryHigh(int pct) => _t({
        'en': '$pct% coverage: very high today. Repeated high intake can become unhealthy, especially for fat-soluble vitamins and minerals.',
        'pl': '$pct% pokrycia: bardzo wysokie dziś. Powtarzające się wysokie spożycie może być niezdrowe, zwłaszcza witamin rozpuszczalnych w tłuszczach i minerałów.',
        'nl': '$pct% dekking: vandaag erg hoog. Herhaaldelijk hoge inname kan ongezond worden, vooral voor vetoplosbare vitamines en mineralen.',
        'es': '$pct% de cobertura: muy alta hoy. Una ingesta alta repetida puede volverse poco saludable, sobre todo de vitaminas liposolubles y minerales.',
        'de': '$pct% Abdeckung: heute sehr hoch. Wiederholt hohe Zufuhr kann ungesund werden, besonders bei fettlöslichen Vitaminen und Mineralstoffen.',
      });

  // ── Nutrition dashboard ──

  String get micronutrientWheel => _t({
        'en': 'Micronutrient Wheel',
        'pl': 'Koło mikroskładników',
        'nl': 'Micronutriëntenwiel',
        'es': 'Rueda de micronutrientes',
        'de': 'Mikronährstoff-Rad',
      });

  String get macronutrients => _t({
        'en': 'Macronutrients',
        'pl': 'Makroskładniki',
        'nl': 'Macronutriënten',
        'es': 'Macronutrientes',
        'de': 'Makronährstoffe',
      });

  String get vitamins => _t({
        'en': 'Vitamins',
        'pl': 'Witaminy',
        'nl': 'Vitamines',
        'es': 'Vitaminas',
        'de': 'Vitamine',
      });

  String get minerals => _t({
        'en': 'Minerals',
        'pl': 'Minerały',
        'nl': 'Mineralen',
        'es': 'Minerales',
        'de': 'Mineralien',
      });

  String get essentialFatsTraceMinerals => _t({
        'en': 'Essential Fats & Trace Minerals',
        'pl': 'Niezbędne tłuszcze i mikroelementy',
        'nl': 'Essentiële vetten & sporenmineralen',
        'es': 'Grasas esenciales y oligominerales',
        'de': 'Essentielle Fette & Spurenelemente',
      });

  String get nutritionDisclaimer => _t({
        'en': '* Targets shown are goal- and gender-adjusted Dietary Reference Values (European Food Safety Authority, EFSA). Micronutrient values are estimated from European food composition databases (EuroFIR). For personalised advice, consult a registered dietitian.',
        'pl': '* Pokazane cele to referencyjne wartości spożycia dostosowane do celu i płci (Europejski Urząd ds. Bezpieczeństwa Żywności, EFSA). Wartości mikroskładników szacowane są na podstawie europejskich baz składu żywności (EuroFIR). Po indywidualną poradę zwróć się do dietetyka.',
        'nl': '* De getoonde doelen zijn op doel en geslacht afgestemde Dietary Reference Values (Europese Autoriteit voor voedselveiligheid, EFSA). Micronutriëntwaarden zijn geschat op basis van Europese voedingsmiddelendatabases (EuroFIR). Raadpleeg voor persoonlijk advies een diëtist.',
        'es': '* Los objetivos mostrados son valores dietéticos de referencia ajustados por meta y sexo (Autoridad Europea de Seguridad Alimentaria, EFSA). Los valores de micronutrientes se estiman a partir de bases de datos europeas de composición de alimentos (EuroFIR). Para asesoramiento personalizado, consulta a un dietista.',
        'de': '* Die angezeigten Ziele sind ziel- und geschlechtsangepasste Dietary Reference Values (Europäische Behörde für Lebensmittelsicherheit, EFSA). Mikronährstoffwerte werden aus europäischen Lebensmittel-Zusammensetzungsdatenbanken (EuroFIR) geschätzt. Für persönliche Beratung wende dich an eine Ernährungsfachkraft.',
      });

  // ── Analytics ──

  String get calorieTrend => _t({
        'en': 'Calorie trend',
        'pl': 'Trend kalorii',
        'nl': 'Calorietrend',
        'es': 'Tendencia de calorías',
        'de': 'Kalorientrend',
      });

  String get noDataYet => _t({
        'en': 'No data yet',
        'pl': 'Brak danych',
        'nl': 'Nog geen gegevens',
        'es': 'Aún no hay datos',
        'de': 'Noch keine Daten',
      });

  String analyticsConsistencyLow(int pct) => _t({
        'en': 'You logged only $pct% of days. Scanning more often makes these analytics much more accurate.',
        'pl': 'Zarejestrowałeś tylko $pct% dni. Częstsze skanowanie znacznie zwiększa dokładność tych statystyk.',
        'nl': 'Je hebt slechts $pct% van de dagen gelogd. Vaker scannen maakt deze analyses veel nauwkeuriger.',
        'es': 'Solo registraste el $pct% de los días. Escanear con más frecuencia hace estos análisis mucho más precisos.',
        'de': 'Du hast nur $pct% der Tage erfasst. Häufigeres Scannen macht diese Auswertungen viel genauer.',
      });

  String analyticsConsistencyHigh(int logged, int total) => _t({
        'en': 'Excellent consistency — you logged $logged of $total days. Trends here are reliable.',
        'pl': 'Świetna regularność — zarejestrowałeś $logged z $total dni. Trendy są wiarygodne.',
        'nl': 'Uitstekende consistentie — je hebt $logged van $total dagen gelogd. Deze trends zijn betrouwbaar.',
        'es': 'Excelente constancia: registraste $logged de $total días. Estas tendencias son fiables.',
        'de': 'Ausgezeichnete Beständigkeit — du hast $logged von $total Tagen erfasst. Diese Trends sind verlässlich.',
      });

  String get analyticsAvgMatchesGoal => _t({
        'en': 'Your daily average matches your goal almost exactly. Nice work staying on plan.',
        'pl': 'Twoja dzienna średnia niemal dokładnie pokrywa się z celem. Świetna robota, trzymasz plan.',
        'nl': 'Je dagelijkse gemiddelde komt bijna precies overeen met je doel. Goed bezig met je plan.',
        'es': 'Tu promedio diario coincide casi exactamente con tu objetivo. Buen trabajo siguiendo el plan.',
        'de': 'Dein Tagesdurchschnitt entspricht fast genau deinem Ziel. Gut gemacht, du bleibst am Plan.',
      });

  String analyticsAvgOverGoal(int delta, int goal, int dropKcal) => _t({
        'en': "You're averaging $delta kcal/day over your $goal kcal goal. If your goal is fat-loss, drop ~$dropKcal kcal of fast carbs first.",
        'pl': 'Średnio jesz $delta kcal/dzień ponad cel $goal kcal. Jeśli celem jest redukcja, najpierw odejmij ~$dropKcal kcal szybkich węglowodanów.',
        'nl': 'Je zit gemiddeld $delta kcal/dag boven je doel van $goal kcal. Als vetverlies je doel is, schrap eerst ~$dropKcal kcal snelle koolhydraten.',
        'es': 'Promedias $delta kcal/día por encima de tu objetivo de $goal kcal. Si tu meta es perder grasa, reduce primero ~$dropKcal kcal de carbohidratos rápidos.',
        'de': 'Du liegst im Schnitt $delta kcal/Tag über deinem Ziel von $goal kcal. Wenn Fettabbau dein Ziel ist, streiche zuerst ~$dropKcal kcal schnelle Kohlenhydrate.',
      });

  String analyticsAvgUnderGoal(int deficit, int goal) => _t({
        'en': "You're $deficit kcal/day under your $goal kcal goal. If you're tired, add a protein-rich snack.",
        'pl': 'Jesz $deficit kcal/dzień poniżej celu $goal kcal. Jeśli czujesz zmęczenie, dodaj przekąskę bogatą w białko.',
        'nl': 'Je zit $deficit kcal/dag onder je doel van $goal kcal. Als je moe bent, voeg een eiwitrijke snack toe.',
        'es': 'Estás $deficit kcal/día por debajo de tu objetivo de $goal kcal. Si te sientes cansado, añade un snack rico en proteína.',
        'de': 'Du liegst $deficit kcal/Tag unter deinem Ziel von $goal kcal. Wenn du müde bist, füge einen proteinreichen Snack hinzu.',
      });

  String analyticsTrendUp(String pct) => _t({
        'en': 'Calories are trending up by $pct% recently — worth checking which days.',
        'pl': 'Kalorie ostatnio rosną o $pct% — warto sprawdzić, które dni.',
        'nl': 'Calorieën stijgen de laatste tijd met $pct% — de moeite waard om te kijken welke dagen.',
        'es': 'Las calorías están subiendo un $pct% últimamente — conviene revisar qué días.',
        'de': 'Die Kalorien steigen zuletzt um $pct% — es lohnt sich zu prüfen, an welchen Tagen.',
      });

  String analyticsTrendDown(String pct) => _t({
        'en': "Calories are trending down by $pct% recently — make sure you're still hitting protein targets.",
        'pl': 'Kalorie ostatnio spadają o $pct% — upewnij się, że wciąż realizujesz cele białkowe.',
        'nl': 'Calorieën dalen de laatste tijd met $pct% — zorg dat je je eiwitdoelen blijft halen.',
        'es': 'Las calorías están bajando un $pct% últimamente — asegúrate de seguir alcanzando tus objetivos de proteína.',
        'de': 'Die Kalorien sinken zuletzt um $pct% — achte darauf, dass du deine Proteinziele weiter erreichst.',
      });

  String analyticsProteinShareLow(int pct) => _t({
        'en': 'Protein is only $pct% of your average intake. Aim for 20–30% for satiety and muscle support.',
        'pl': 'Białko to tylko $pct% Twojego średniego spożycia. Celuj w 20–30% dla sytości i wsparcia mięśni.',
        'nl': 'Eiwit is slechts $pct% van je gemiddelde inname. Streef naar 20–30% voor verzadiging en spierondersteuning.',
        'es': 'La proteína es solo el $pct% de tu ingesta media. Apunta al 20–30% para saciedad y apoyo muscular.',
        'de': 'Protein macht nur $pct% deiner durchschnittlichen Zufuhr aus. Ziele auf 20–30% für Sättigung und Muskelunterstützung.',
      });

  // ── Recipe meal types & nutrition goals ──

  String recipeMealTypeLabel(String key) {
    switch (key) {
      case 'breakfast':
        return breakfast;
      case 'lunch':
        return lunch;
      case 'dinner':
        return dinner;
      case 'snack':
        return snack;
      case 'dessert':
        return dessert;
      default:
        return key;
    }
  }

  String nutritionGoalLabel(String key) {
    switch (key) {
      case 'muscleGrowth':
        return _t({
          'en': 'Muscle Growth',
          'pl': 'Budowa mięśni',
          'nl': 'Spiergroei',
          'es': 'Crecimiento muscular',
          'de': 'Muskelaufbau',
        });
      case 'diabetes':
        return _t({
          'en': 'Diabetes',
          'pl': 'Cukrzyca',
          'nl': 'Diabetes',
          'es': 'Diabetes',
          'de': 'Diabetes',
        });
      case 'vegan':
        return _t({
          'en': 'Vegan Diet',
          'pl': 'Dieta wegańska',
          'nl': 'Veganistisch dieet',
          'es': 'Dieta vegana',
          'de': 'Vegane Ernährung',
        });
      case 'vegetarian':
        return _t({
          'en': 'Vegetarian Diet',
          'pl': 'Dieta wegetariańska',
          'nl': 'Vegetarisch dieet',
          'es': 'Dieta vegetariana',
          'de': 'Vegetarische Ernährung',
        });
      case 'pescatarian':
        return _t({
          'en': 'Pescatarian',
          'pl': 'Pesketarianizm',
          'nl': 'Pescotarisch',
          'es': 'Pescetariano',
          'de': 'Pescetarisch',
        });
      case 'mediterranean':
        return _t({
          'en': 'Mediterranean',
          'pl': 'Śródziemnomorska',
          'nl': 'Mediterraan',
          'es': 'Mediterránea',
          'de': 'Mediterran',
        });
      case 'weightLoss':
        return _t({
          'en': 'Weight Loss',
          'pl': 'Utrata wagi',
          'nl': 'Gewichtsverlies',
          'es': 'Pérdida de peso',
          'de': 'Gewichtsverlust',
        });
      case 'keto':
        return _t({
          'en': 'Keto',
          'pl': 'Keto',
          'nl': 'Keto',
          'es': 'Keto',
          'de': 'Keto',
        });
      case 'maintain':
        return _t({
          'en': 'Maintain Weight',
          'pl': 'Utrzymanie wagi',
          'nl': 'Gewicht behouden',
          'es': 'Mantener peso',
          'de': 'Gewicht halten',
        });
      default:
        return key;
    }
  }

  String nutritionGoalDescription(String key) {
    switch (key) {
      case 'muscleGrowth':
        return _t({
          'en': 'Build muscle with a calorie surplus and high protein intake.',
          'pl': 'Buduj mięśnie dzięki nadwyżce kalorycznej i wysokiemu spożyciu białka.',
          'nl': 'Bouw spieren op met een calorieoverschot en een hoge eiwitinname.',
          'es': 'Desarrolla músculo con un superávit calórico y una alta ingesta de proteínas.',
          'de': 'Baue Muskeln mit einem Kalorienüberschuss und hoher Proteinzufuhr auf.',
        });
      case 'diabetes':
        return _t({
          'en': 'Keep blood sugar stable by managing your daily carbohydrate intake.',
          'pl': 'Utrzymuj stabilny poziom cukru we krwi, kontrolując dzienne spożycie węglowodanów.',
          'nl': 'Houd je bloedsuiker stabiel door je dagelijkse koolhydraatinname te beheren.',
          'es': 'Mantén estable el azúcar en sangre gestionando tu ingesta diaria de carbohidratos.',
          'de': 'Halte deinen Blutzucker stabil, indem du deine tägliche Kohlenhydratzufuhr steuerst.',
        });
      case 'vegan':
        return _t({
          'en': 'Track nutrients often missing from plant-based diets: protein, B12, iron, vitamin D.',
          'pl': 'Śledź składniki często brakujące w dietach roślinnych: białko, B12, żelazo, witaminę D.',
          'nl': 'Volg voedingsstoffen die vaak ontbreken in plantaardige diëten: eiwit, B12, ijzer, vitamine D.',
          'es': 'Controla los nutrientes que suelen faltar en las dietas vegetales: proteína, B12, hierro, vitamina D.',
          'de': 'Verfolge Nährstoffe, die in pflanzlichen Ernährungsformen oft fehlen: Protein, B12, Eisen, Vitamin D.',
        });
      case 'vegetarian':
        return _t({
          'en': 'Avoid meat and seafood while allowing dairy, eggs, and honey when they fit your plan.',
          'pl': 'Unikaj mięsa i owoców morza, dopuszczając nabiał, jaja i miód, gdy pasują do planu.',
          'nl': 'Vermijd vlees en zeevruchten en sta zuivel, eieren en honing toe wanneer ze in je plan passen.',
          'es': 'Evita la carne y el marisco, permitiendo lácteos, huevos y miel cuando encajen en tu plan.',
          'de': 'Verzichte auf Fleisch und Meeresfrüchte und erlaube Milchprodukte, Eier und Honig, wenn sie zu deinem Plan passen.',
        });
      case 'pescatarian':
        return _t({
          'en': 'Vegetarian-style eating that includes fish and seafood for omega-3 fats, iodine, selenium, and complete protein.',
          'pl': 'Sposób odżywiania w stylu wegetariańskim z rybami i owocami morza dla kwasów omega-3, jodu, selenu i pełnowartościowego białka.',
          'nl': 'Vegetarisch eten met vis en zeevruchten voor omega 3-vetten, jodium, selenium en complete eiwitten.',
          'es': 'Alimentación de estilo vegetariano que incluye pescado y marisco para grasas omega-3, yodo, selenio y proteína completa.',
          'de': 'Vegetarische Ernährung, die Fisch und Meeresfrüchte für Omega-3-Fette, Jod, Selen und vollständiges Protein einschließt.',
        });
      case 'mediterranean':
        return _t({
          'en': 'A cardiometabolic pattern built around vegetables, legumes, whole grains, fruit, olive oil, nuts, fish, and modest dairy.',
          'pl': 'Wzorzec kardiometaboliczny oparty na warzywach, roślinach strączkowych, pełnych ziarnach, owocach, oliwie, orzechach, rybach i niewielkiej ilości nabiału.',
          'nl': 'Een cardiometabool patroon rond groenten, peulvruchten, volle granen, fruit, olijfolie, noten, vis en weinig zuivel.',
          'es': 'Un patrón cardiometabólico basado en verduras, legumbres, cereales integrales, fruta, aceite de oliva, frutos secos, pescado y lácteos moderados.',
          'de': 'Ein kardiometabolisches Muster mit Gemüse, Hülsenfrüchten, Vollkorn, Obst, Olivenöl, Nüssen, Fisch und wenig Milchprodukten.',
        });
      case 'weightLoss':
        return _t({
          'en': 'Lose weight sustainably with a moderate calorie deficit and high protein.',
          'pl': 'Chudnij trwale dzięki umiarkowanemu deficytowi kalorycznemu i wysokiemu spożyciu białka.',
          'nl': 'Val duurzaam af met een matig calorietekort en veel eiwit.',
          'es': 'Pierde peso de forma sostenible con un déficit calórico moderado y mucha proteína.',
          'de': 'Nimm nachhaltig ab mit einem moderaten Kaloriendefizit und viel Protein.',
        });
      case 'keto':
        return _t({
          'en': 'Enter and stay in ketosis. Keep daily carbs under 25 g while eating healthy fats.',
          'pl': 'Wejdź i pozostań w ketozie. Utrzymuj dzienne węglowodany poniżej 25 g, jedząc zdrowe tłuszcze.',
          'nl': 'Kom in ketose en blijf erin. Houd dagelijkse koolhydraten onder 25 g en eet gezonde vetten.',
          'es': 'Entra y mantente en cetosis. Mantén los carbohidratos diarios por debajo de 25 g comiendo grasas saludables.',
          'de': 'Komm in die Ketose und bleib dort. Halte die täglichen Kohlenhydrate unter 25 g und iss gesunde Fette.',
        });
      case 'maintain':
        return _t({
          'en': 'Maintain your current weight with balanced macros.',
          'pl': 'Utrzymuj obecną wagę dzięki zbilansowanym makroskładnikom.',
          'nl': 'Behoud je huidige gewicht met gebalanceerde macro\'s.',
          'es': 'Mantén tu peso actual con macros equilibrados.',
          'de': 'Halte dein aktuelles Gewicht mit ausgewogenen Makros.',
        });
      default:
        return key;
    }
  }

  String muscleMassLevelLabel(String key) {
    switch (key) {
      case 'low':
        return _t({
          'en': 'Low',
          'pl': 'Niska',
          'nl': 'Laag',
          'es': 'Baja',
          'de': 'Niedrig',
        });
      case 'average':
        return _t({
          'en': 'Average',
          'pl': 'Przeciętna',
          'nl': 'Gemiddeld',
          'es': 'Media',
          'de': 'Durchschnittlich',
        });
      case 'high':
        return _t({
          'en': 'High',
          'pl': 'Wysoka',
          'nl': 'Hoog',
          'es': 'Alta',
          'de': 'Hoch',
        });
      case 'veryHigh':
        return _t({
          'en': 'Very high',
          'pl': 'Bardzo wysoka',
          'nl': 'Zeer hoog',
          'es': 'Muy alta',
          'de': 'Sehr hoch',
        });
      default:
        return key;
    }
  }

  String muscleMassLevelDescription(String key) {
    switch (key) {
      case 'low':
        return _t({
          'en': 'Lower lean mass or mostly sedentary right now.',
          'pl': 'Niższa masa beztłuszczowa lub obecnie głównie siedzący tryb życia.',
          'nl': 'Lagere vetvrije massa of momenteel vooral zittend.',
          'es': 'Masa magra baja o vida mayormente sedentaria ahora mismo.',
          'de': 'Geringere Magermasse oder derzeit überwiegend sitzend.',
        });
      case 'average':
        return _t({
          'en': 'Typical lean mass for your weight and height.',
          'pl': 'Typowa masa beztłuszczowa dla Twojej wagi i wzrostu.',
          'nl': 'Typische vetvrije massa voor je gewicht en lengte.',
          'es': 'Masa magra típica para tu peso y altura.',
          'de': 'Typische Magermasse für dein Gewicht und deine Größe.',
        });
      case 'high':
        return _t({
          'en': 'Clearly muscular or strength training regularly.',
          'pl': 'Wyraźnie umięśniony lub regularnie trenujący siłowo.',
          'nl': 'Duidelijk gespierd of regelmatig krachttraining.',
          'es': 'Claramente musculoso o entrenas fuerza con regularidad.',
          'de': 'Deutlich muskulös oder regelmäßiges Krafttraining.',
        });
      case 'veryHigh':
        return _t({
          'en': 'Very muscular athlete/bodybuilding profile.',
          'pl': 'Profil bardzo umięśnionego sportowca/kulturysty.',
          'nl': 'Zeer gespierd atleet-/bodybuildingprofiel.',
          'es': 'Perfil de atleta muy musculoso/culturismo.',
          'de': 'Sehr muskulöses Athleten-/Bodybuilding-Profil.',
        });
      default:
        return key;
    }
  }

  // ── Recipe detail / cards ──

  String get newBadge => _t({
        'en': 'New',
        'pl': 'Nowy',
        'nl': 'Nieuw',
        'es': 'Nuevo',
        'de': 'Neu',
      });

  String get myMeal => _t({
        'en': 'My Meal',
        'pl': 'Mój posiłek',
        'nl': 'Mijn maaltijd',
        'es': 'Mi comida',
        'de': 'Meine Mahlzeit',
      });

  String ingredientCount(int n) => _t({
        'en': '$n ingredient${n == 1 ? '' : 's'}',
        'pl': n == 1 ? '$n składnik' : '$n składników',
        'nl': '$n ingrediënt${n == 1 ? '' : 'en'}',
        'es': '$n ingrediente${n == 1 ? '' : 's'}',
        'de': '$n Zutat${n == 1 ? '' : 'en'}',
      });

  String get perPerson => _t({
        'en': 'Per person',
        'pl': 'Na osobę',
        'nl': 'Per persoon',
        'es': 'Por persona',
        'de': 'Pro Person',
      });

  String get preparation => _t({
        'en': 'Preparation',
        'pl': 'Przygotowanie',
        'nl': 'Bereiding',
        'es': 'Preparación',
        'de': 'Zubereitung',
      });

  String get swap => _t({
        'en': 'Swap',
        'pl': 'Zamień',
        'nl': 'Wisselen',
        'es': 'Cambiar',
        'de': 'Tauschen',
      });

  String get scanBarcode => _t({
        'en': 'Scan Barcode',
        'pl': 'Skanuj kod kreskowy',
        'nl': 'Streepjescode scannen',
        'es': 'Escanear código',
        'de': 'Barcode scannen',
      });

  String get addManually => _t({
        'en': 'Add Manually',
        'pl': 'Dodaj ręcznie',
        'nl': 'Handmatig toevoegen',
        'es': 'Añadir manualmente',
        'de': 'Manuell hinzufügen',
      });

  String get vitaminsAndMinerals => _t({
        'en': 'Vitamins & minerals',
        'pl': 'Witaminy i minerały',
        'nl': 'Vitaminen & mineralen',
        'es': 'Vitaminas y minerales',
        'de': 'Vitamine & Mineralstoffe',
      });

  String get showLess => _t({
        'en': 'Show less',
        'pl': 'Pokaż mniej',
        'nl': 'Minder tonen',
        'es': 'Mostrar menos',
        'de': 'Weniger anzeigen',
      });

  String get betterAlternatives => _t({
        'en': 'Better alternatives',
        'pl': 'Lepsze alternatywy',
        'nl': 'Betere alternatieven',
        'es': 'Mejores alternativas',
        'de': 'Bessere Alternativen',
      });

  String get noBetterAlternatives => _t({
        'en': 'No better alternatives found for this recipe.',
        'pl': 'Nie znaleziono lepszych alternatyw dla tego przepisu.',
        'nl': 'Geen betere alternatieven gevonden voor dit recept.',
        'es': 'No se encontraron mejores alternativas para esta receta.',
        'de': 'Keine besseren Alternativen für dieses Rezept gefunden.',
      });

  String get currentLabel => _t({
        'en': 'Current',
        'pl': 'Obecny',
        'nl': 'Huidig',
        'es': 'Actual',
        'de': 'Aktuell',
      });

  String get cookingFor => _t({
        'en': 'Cooking for',
        'pl': 'Gotuję dla',
        'nl': 'Koken voor',
        'es': 'Cocinar para',
        'de': 'Kochen für',
      });

  String get dismissKeyboard => _t({
        'en': 'Dismiss keyboard',
        'pl': 'Ukryj klawiaturę',
        'nl': 'Toetsenbord sluiten',
        'es': 'Ocultar teclado',
        'de': 'Tastatur ausblenden',
      });

  String get barcodeNeedsInternet => _t({
        'en': 'Barcode scanning requires an internet connection.',
        'pl': 'Skanowanie kodu kreskowego wymaga połączenia z internetem.',
        'nl': 'Streepjescode scannen vereist een internetverbinding.',
        'es': 'Escanear el código de barras requiere conexión a internet.',
        'de': 'Das Scannen von Barcodes erfordert eine Internetverbindung.',
      });

  String get noIngredientsToLog => _t({
        'en': 'No ingredients to log.',
        'pl': 'Brak składników do zarejestrowania.',
        'nl': 'Geen ingrediënten om te loggen.',
        'es': 'No hay ingredientes para registrar.',
        'de': 'Keine Zutaten zum Loggen.',
      });

  String get noIngredientAmounts => _t({
        'en': 'No ingredient amounts provided.',
        'pl': 'Nie podano ilości składników.',
        'nl': 'Geen hoeveelheden ingrediënten opgegeven.',
        'es': 'No se indicaron cantidades de ingredientes.',
        'de': 'Keine Zutatenmengen angegeben.',
      });

  String get loggedRecipe => _t({
        'en': 'Logged recipe.',
        'pl': 'Zarejestrowano przepis.',
        'nl': 'Recept gelogd.',
        'es': 'Receta registrada.',
        'de': 'Rezept geloggt.',
      });

  String failedToLogRecipe(String error) => _t({
        'en': 'Failed to log recipe: $error',
        'pl': 'Nie udało się zarejestrować przepisu: $error',
        'nl': 'Recept loggen mislukt: $error',
        'es': 'No se pudo registrar la receta: $error',
        'de': 'Rezept konnte nicht geloggt werden: $error',
      });

  String loggedItemNamed(String name) => _t({
        'en': 'Logged "$name".',
        'pl': 'Zarejestrowano „$name".',
        'nl': '"$name" gelogd.',
        'es': 'Se registró "$name".',
        'de': '"$name" geloggt.',
      });

  String removeMealConfirm(String name) => _t({
        'en': 'Remove "$name" from your saved meals?',
        'pl': 'Usunąć „$name" z zapisanych posiłków?',
        'nl': '"$name" uit je opgeslagen maaltijden verwijderen?',
        'es': '¿Eliminar "$name" de tus comidas guardadas?',
        'de': '"$name" aus deinen gespeicherten Mahlzeiten entfernen?',
      });

  String logRecipeTitle(String name) => _t({
        'en': 'Log: $name',
        'pl': 'Zarejestruj: $name',
        'nl': 'Loggen: $name',
        'es': 'Registrar: $name',
        'de': 'Loggen: $name',
      });

  String get ingredientNameHint => _t({
        'en': 'Ingredient name',
        'pl': 'Nazwa składnika',
        'nl': 'Naam ingrediënt',
        'es': 'Nombre del ingrediente',
        'de': 'Name der Zutat',
      });

  String totalKcalLabel(int kcal) => _t({
        'en': 'Total: $kcal kcal',
        'pl': 'Razem: $kcal kcal',
        'nl': 'Totaal: $kcal kcal',
        'es': 'Total: $kcal kcal',
        'de': 'Gesamt: $kcal kcal',
      });

  String errorWithMessage(String error) => _t({
        'en': 'Error: $error',
        'pl': 'Błąd: $error',
        'nl': 'Fout: $error',
        'es': 'Error: $error',
        'de': 'Fehler: $error',
      });

  String adjustGramsCookingFor(int servings) => _t({
        'en': 'Adjust grams per ingredient (cooking for $servings)',
        'pl': 'Dostosuj gramy na składnik (gotujesz dla $servings)',
        'nl': 'Pas grammen per ingrediënt aan (koken voor $servings)',
        'es': 'Ajusta los gramos por ingrediente (cocinas para $servings)',
        'de': 'Gramm pro Zutat anpassen (Kochen für $servings)',
      });

  String get multipleServingsBolusWarning => _t({
        'en': 'Multiple servings: verify portion accuracy before bolusing.',
        'pl': 'Wiele porcji: zweryfikuj dokładność porcji przed podaniem bolusa.',
        'nl': 'Meerdere porties: controleer de portienauwkeurigheid vóór het bolussen.',
        'es': 'Varias porciones: verifica la exactitud de la porción antes de administrar el bolo.',
        'de': 'Mehrere Portionen: Prüfe die Portionsgenauigkeit vor dem Bolus.',
      });

  String get icrNotSetWarning => _t({
        'en': 'Your ICR is not set. Bolus calculations will be inaccurate.\nGo to Settings → Diabetes to set your personal ICR.',
        'pl': 'Twój wskaźnik ICR nie jest ustawiony. Obliczenia bolusa będą niedokładne.\nPrzejdź do Ustawienia → Cukrzyca, aby ustawić własny ICR.',
        'nl': 'Je ICR is niet ingesteld. Bolusberekeningen zullen onnauwkeurig zijn.\nGa naar Instellingen → Diabetes om je persoonlijke ICR in te stellen.',
        'es': 'Tu ICR no está configurado. Los cálculos del bolo serán inexactos.\nVe a Ajustes → Diabetes para configurar tu ICR personal.',
        'de': 'Dein ICR ist nicht eingestellt. Bolusberechnungen werden ungenau sein.\nGehe zu Einstellungen → Diabetes, um deinen persönlichen ICR festzulegen.',
      });

  // ── Scan / voice / manual entry ──

  String get editTooltip => _t({
        'en': 'Edit',
        'pl': 'Edytuj',
        'nl': 'Bewerken',
        'es': 'Editar',
        'de': 'Bearbeiten',
      });

  String get mealNameLabel => _t({
        'en': 'Meal name',
        'pl': 'Nazwa posiłku',
        'nl': 'Naam maaltijd',
        'es': 'Nombre de la comida',
        'de': 'Name der Mahlzeit',
      });

  String get mealNameExampleHint => _t({
        'en': 'e.g. My post-workout lunch',
        'pl': 'np. Mój obiad po treningu',
        'nl': 'bijv. Mijn lunch na het sporten',
        'es': 'p. ej. Mi almuerzo post-entrenamiento',
        'de': 'z. B. Mein Mittagessen nach dem Training',
      });

  String get searchFoodHint => _t({
        'en': 'Search food…',
        'pl': 'Szukaj jedzenia…',
        'nl': 'Zoek voedsel…',
        'es': 'Buscar alimento…',
        'de': 'Lebensmittel suchen…',
      });

  String get searchFoodLabel => _t({
        'en': 'Search Food',
        'pl': 'Szukaj jedzenia',
        'nl': 'Voedsel zoeken',
        'es': 'Buscar alimento',
        'de': 'Lebensmittel suchen',
      });

  String get searchFoodTooltip => _t({
        'en': 'Search food',
        'pl': 'Szukaj jedzenia',
        'nl': 'Voedsel zoeken',
        'es': 'Buscar alimento',
        'de': 'Lebensmittel suchen',
      });

  String get noMatchingFood => _t({
        'en': 'No matching food',
        'pl': 'Brak pasującego jedzenia',
        'nl': 'Geen overeenkomend voedsel',
        'es': 'No hay alimentos coincidentes',
        'de': 'Kein passendes Lebensmittel',
      });

  String get view3d => _t({
        'en': 'View 3D',
        'pl': 'Zobacz 3D',
        'nl': 'Bekijk 3D',
        'es': 'Ver 3D',
        'de': '3D ansehen',
      });

  String get view3dScan => _t({
        'en': 'View 3D Scan',
        'pl': 'Zobacz skan 3D',
        'nl': 'Bekijk 3D-scan',
        'es': 'Ver escaneo 3D',
        'de': '3D-Scan ansehen',
      });

  String get export3dPointCloud => _t({
        'en': 'Export 3D point cloud',
        'pl': 'Eksportuj chmurę punktów 3D',
        'nl': '3D-puntenwolk exporteren',
        'es': 'Exportar nube de puntos 3D',
        'de': '3D-Punktwolke exportieren',
      });

  String get tapToAddPhotoOptional => _t({
        'en': 'Tap to add a photo (optional)',
        'pl': 'Dotknij, aby dodać zdjęcie (opcjonalnie)',
        'nl': 'Tik om een foto toe te voegen (optioneel)',
        'es': 'Toca para añadir una foto (opcional)',
        'de': 'Tippen, um ein Foto hinzuzufügen (optional)',
      });

  String get barcodeNeedsInternetShort => _t({
        'en': 'Barcode scanning requires internet.',
        'pl': 'Skanowanie kodu kreskowego wymaga internetu.',
        'nl': 'Streepjescode scannen vereist internet.',
        'es': 'Escanear el código requiere internet.',
        'de': 'Barcode-Scannen erfordert Internet.',
      });

  String get minimum => _t({
        'en': 'Minimum',
        'pl': 'Minimum',
        'nl': 'Minimum',
        'es': 'Mínimo',
        'de': 'Minimum',
      });

  String get average => _t({
        'en': 'Average',
        'pl': 'Średnia',
        'nl': 'Gemiddeld',
        'es': 'Promedio',
        'de': 'Durchschnitt',
      });

  String get maximum => _t({
        'en': 'Maximum',
        'pl': 'Maksimum',
        'nl': 'Maximum',
        'es': 'Máximo',
        'de': 'Maximum',
      });

  String get topPosition => _t({
        'en': 'Top position',
        'pl': 'Pozycja z góry',
        'nl': 'Bovenpositie',
        'es': 'Posición superior',
        'de': 'Position von oben',
      });

  String get sidePosition => _t({
        'en': 'Side position',
        'pl': 'Pozycja z boku',
        'nl': 'Zijpositie',
        'es': 'Posición lateral',
        'de': 'Seitliche Position',
      });

  String get cameraPose => _t({
        'en': 'Camera Pose',
        'pl': 'Pozycja kamery',
        'nl': 'Camerapositie',
        'es': 'Pose de cámara',
        'de': 'Kamerapose',
      });

  String get fullTransformNote => _t({
        'en': 'Full 4×4 transform stored for geometry reconstruction',
        'pl': 'Pełna transformacja 4×4 zapisana do rekonstrukcji geometrii',
        'nl': 'Volledige 4×4-transformatie opgeslagen voor geometriereconstructie',
        'es': 'Transformación 4×4 completa almacenada para la reconstrucción geométrica',
        'de': 'Vollständige 4×4-Transformation für die Geometrierekonstruktion gespeichert',
      });

  String get mealNameOatmealHint => _t({
        'en': 'e.g. My morning oatmeal',
        'pl': 'np. Moja poranna owsianka',
        'nl': 'bijv. Mijn ochtendhavermout',
        'es': 'p. ej. Mis avenas de la mañana',
        'de': 'z. B. Mein Morgen-Haferbrei',
      });

  String get addIngredientButton => _t({
        'en': 'Add Ingredient',
        'pl': 'Dodaj składnik',
        'nl': 'Ingrediënt toevoegen',
        'es': 'Añadir ingrediente',
        'de': 'Zutat hinzufügen',
      });

  String get editMealTitle => _t({
        'en': 'Edit Meal',
        'pl': 'Edytuj posiłek',
        'nl': 'Maaltijd bewerken',
        'es': 'Editar comida',
        'de': 'Mahlzeit bearbeiten',
      });

  // ── Settings: diabetes & account ──

  String get scannerDiagnostics => _t({
        'en': 'Scanner Diagnostics',
        'pl': 'Diagnostyka skanera',
        'nl': 'Scannerdiagnostiek',
        'es': 'Diagnóstico del escáner',
        'de': 'Scanner-Diagnose',
      });

  String get bloodGlucoseUnit => _t({
        'en': 'Blood glucose unit',
        'pl': 'Jednostka glukozy we krwi',
        'nl': 'Bloedglucose-eenheid',
        'es': 'Unidad de glucosa en sangre',
        'de': 'Blutzucker-Einheit',
      });

  String get insulinToCarbRatio => _t({
        'en': 'Insulin-to-Carb Ratio (ICR)',
        'pl': 'Współczynnik insulina-węglowodany (ICR)',
        'nl': 'Insuline-koolhydraatratio (ICR)',
        'es': 'Ratio insulina-carbohidratos (ICR)',
        'de': 'Insulin-Kohlenhydrat-Verhältnis (ICR)',
      });

  String get icrHelp => _t({
        'en': '1 unit of insulin covers how many grams of carbs?',
        'pl': '1 jednostka insuliny pokrywa ile gramów węglowodanów?',
        'nl': '1 eenheid insuline dekt hoeveel gram koolhydraten?',
        'es': '¿1 unidad de insulina cubre cuántos gramos de carbohidratos?',
        'de': '1 Einheit Insulin deckt wie viele Gramm Kohlenhydrate ab?',
      });

  String get insulinSensitivityFactor => _t({
        'en': 'Insulin Sensitivity Factor (ISF)',
        'pl': 'Współczynnik wrażliwości na insulinę (ISF)',
        'nl': 'Insulinegevoeligheidsfactor (ISF)',
        'es': 'Factor de sensibilidad a la insulina (ISF)',
        'de': 'Insulinempfindlichkeitsfaktor (ISF)',
      });

  String isfHelp(String unitLabel) => _t({
        'en': '1 unit of insulin lowers your blood glucose by how much ($unitLabel)? Used for correction doses.',
        'pl': '1 jednostka insuliny obniża poziom glukozy o ile ($unitLabel)? Używane do dawek korekcyjnych.',
        'nl': '1 eenheid insuline verlaagt je bloedglucose met hoeveel ($unitLabel)? Gebruikt voor correctiedoses.',
        'es': '¿1 unidad de insulina reduce tu glucosa en cuánto ($unitLabel)? Se usa para dosis de corrección.',
        'de': '1 Einheit Insulin senkt deinen Blutzucker um wie viel ($unitLabel)? Wird für Korrekturdosen verwendet.',
      });

  String get targetBloodGlucose => _t({
        'en': 'Target blood glucose',
        'pl': 'Docelowy poziom glukozy',
        'nl': 'Streefwaarde bloedglucose',
        'es': 'Glucosa en sangre objetivo',
        'de': 'Ziel-Blutzucker',
      });

  String get targetBloodGlucoseHelp => _t({
        'en': 'Your goal blood glucose for correction calculations.',
        'pl': 'Twój docelowy poziom glukozy do obliczeń korekcyjnych.',
        'nl': 'Je streefwaarde bloedglucose voor correctieberekeningen.',
        'es': 'Tu glucosa objetivo para los cálculos de corrección.',
        'de': 'Dein Ziel-Blutzucker für Korrekturberechnungen.',
      });

  String get diabetesSafetyWarning => _t({
        'en': 'Confirm your ICR, ISF and target with your healthcare provider and review them regularly — they change over time. Always measure your blood glucose correctly and double-check every dose before injecting.',
        'pl': 'Potwierdź ICR, ISF i wartość docelową ze swoim lekarzem i regularnie je weryfikuj — zmieniają się z czasem. Zawsze prawidłowo mierz poziom glukozy i sprawdzaj każdą dawkę przed wstrzyknięciem.',
        'nl': 'Bevestig je ICR, ISF en streefwaarde met je zorgverlener en controleer ze regelmatig — ze veranderen na verloop van tijd. Meet je bloedglucose altijd correct en controleer elke dosis vóór het injecteren.',
        'es': 'Confirma tu ICR, ISF y objetivo con tu profesional de salud y revísalos con regularidad: cambian con el tiempo. Mide siempre tu glucosa correctamente y verifica cada dosis antes de inyectar.',
        'de': 'Bestätige deinen ICR, ISF und Zielwert mit deinem medizinischen Fachpersonal und überprüfe sie regelmäßig — sie ändern sich mit der Zeit. Miss deinen Blutzucker immer korrekt und überprüfe jede Dosis vor dem Injizieren.',
      });

  String get bolusCalculatorMode => _t({
        'en': 'Bolus Calculator Mode',
        'pl': 'Tryb kalkulatora bolusa',
        'nl': 'Bolusrekenmachine-modus',
        'es': 'Modo calculadora de bolo',
        'de': 'Bolusrechner-Modus',
      });

  String get bolusCalculatorModeHelp => _t({
        'en': 'An optional, safety-gated insulin estimate. Off by default. Requires a settings survey, consent, and review every 90 days.',
        'pl': 'Opcjonalne, zabezpieczone oszacowanie insuliny. Domyślnie wyłączone. Wymaga ankiety ustawień, zgody i przeglądu co 90 dni.',
        'nl': 'Een optionele, beveiligde insulineschatting. Standaard uit. Vereist een instellingenquête, toestemming en een controle elke 90 dagen.',
        'es': 'Una estimación de insulina opcional y con controles de seguridad. Desactivada por defecto. Requiere una encuesta de ajustes, consentimiento y revisión cada 90 días.',
        'de': 'Eine optionale, sicherheitsgeprüfte Insulinschätzung. Standardmäßig aus. Erfordert eine Einstellungsumfrage, Zustimmung und Überprüfung alle 90 Tage.',
      });

  String get premium => _t({
        'en': 'Premium',
        'pl': 'Premium',
        'nl': 'Premium',
        'es': 'Premium',
        'de': 'Premium',
      });

  String get standard => _t({
        'en': 'Standard',
        'pl': 'Standardowy',
        'nl': 'Standaard',
        'es': 'Estándar',
        'de': 'Standard',
      });

  String get premiumThemeAppearance => _t({
        'en': 'Appearance',
        'pl': 'Wygląd',
        'nl': 'Weergave',
        'es': 'Apariencia',
        'de': 'Darstellung',
      });

  String get premiumThemeLightMode => _t({
        'en': 'Light',
        'pl': 'Jasny',
        'nl': 'Licht',
        'es': 'Claro',
        'de': 'Hell',
      });

  String get premiumThemeDarkMode => _t({
        'en': 'Dark',
        'pl': 'Ciemny',
        'nl': 'Donker',
        'es': 'Oscuro',
        'de': 'Dunkel',
      });

  // ── Premium theme paywall ────────────────────────────────────────────────

  String get premiumThemesTitle => _t({
        'en': 'Premium Themes',
        'pl': 'Motywy Premium',
        'nl': "Premium thema's",
        'es': 'Temas Premium',
        'de': 'Premium-Designs',
      });

  String get premiumThemesSubtitle => _t({
        'en': 'Unlock a pack of animated, glowing app themes.',
        'pl': 'Odblokuj pakiet animowanych, świecących motywów aplikacji.',
        'nl': "Ontgrendel een pakket geanimeerde, gloeiende app-thema's.",
        'es': 'Desbloquea un paquete de temas animados y brillantes.',
        'de': 'Schalte ein Paket animierter, leuchtender App-Designs frei.',
      });

  String get premiumFeatureAnimated => _t({
        'en': 'Living animated backgrounds',
        'pl': 'Żywe animowane tła',
        'nl': 'Levende geanimeerde achtergronden',
        'es': 'Fondos animados con vida',
        'de': 'Lebendige animierte Hintergründe',
      });

  String get premiumFeatureGlow => _t({
        'en': 'Glowing accents across the app',
        'pl': 'Świecące akcenty w całej aplikacji',
        'nl': 'Gloeiende accenten in de hele app',
        'es': 'Acentos brillantes en toda la app',
        'de': 'Leuchtende Akzente in der ganzen App',
      });

  String get premiumFeaturePacks => _t({
        'en': '8 exclusive theme styles',
        'pl': '8 ekskluzywnych stylów motywów',
        'nl': '8 exclusieve themastijlen',
        'es': '8 estilos de tema exclusivos',
        'de': '8 exklusive Design-Stile',
      });

  String get premiumUnlockCta => _t({
        'en': 'Unlock Premium',
        'pl': 'Odblokuj Premium',
        'nl': 'Premium ontgrendelen',
        'es': 'Desbloquear Premium',
        'de': 'Premium freischalten',
      });

  String get premiumRestore => _t({
        'en': 'Restore purchase',
        'pl': 'Przywróć zakup',
        'nl': 'Aankoop herstellen',
        'es': 'Restaurar compra',
        'de': 'Kauf wiederherstellen',
      });

  String get premiumMaybeLater => _t({
        'en': 'Maybe later',
        'pl': 'Może później',
        'nl': 'Misschien later',
        'es': 'Quizás más tarde',
        'de': 'Vielleicht später',
      });

  String get premiumComingSoon => _t({
        'en': 'In-app purchases aren\'t available yet — coming soon.',
        'pl': 'Zakupy w aplikacji nie są jeszcze dostępne — wkrótce.',
        'nl': 'In-app-aankopen zijn nog niet beschikbaar — binnenkort.',
        'es': 'Las compras dentro de la app aún no están disponibles — próximamente.',
        'de': 'In-App-Käufe sind noch nicht verfügbar — demnächst.',
      });

  String get premiumUnlockedToast => _t({
        'en': 'Premium themes unlocked! 🎉',
        'pl': 'Motywy premium odblokowane! 🎉',
        'nl': "Premium thema's ontgrendeld! 🎉",
        'es': '¡Temas premium desbloqueados! 🎉',
        'de': 'Premium-Designs freigeschaltet! 🎉',
      });

  String get premiumDevUnlock => _t({
        'en': 'Dev unlock (debug only)',
        'pl': 'Odblokowanie deweloperskie (tylko debug)',
        'nl': 'Dev-ontgrendeling (alleen debug)',
        'es': 'Desbloqueo de desarrollo (solo debug)',
        'de': 'Dev-Freischaltung (nur Debug)',
      });

  String get premiumLockedHint => _t({
        'en': 'Premium theme — tap to unlock',
        'pl': 'Motyw premium — dotknij, aby odblokować',
        'nl': 'Premium thema — tik om te ontgrendelen',
        'es': 'Tema premium — toca para desbloquear',
        'de': 'Premium-Design — zum Freischalten tippen',
      });

  // ── Badge collection ─────────────────────────────────────────────────────

  String get badgeCollectionTitle => _t({
        'en': 'Badge Collection',
        'pl': 'Kolekcja odznak',
        'nl': 'Badgeverzameling',
        'es': 'Colección de insignias',
        'de': 'Abzeichensammlung',
      });

  String get badgeCollectionEmpty => _t({
        'en': 'No badges yet. Log meals through the week to start earning them.',
        'pl': 'Brak odznak. Zapisuj posiłki w ciągu tygodnia, aby zacząć je zdobywać.',
        'nl': 'Nog geen badges. Log maaltijden door de week heen om ze te verdienen.',
        'es': 'Aún no hay insignias. Registra comidas durante la semana para empezar a ganarlas.',
        'de': 'Noch keine Abzeichen. Logge Mahlzeiten über die Woche, um sie zu verdienen.',
      });

  String badgeCollectionCount(int earned, int total) => _t({
        'en': '$earned of $total earned',
        'pl': 'Zdobyto $earned z $total',
        'nl': '$earned van $total verdiend',
        'es': '$earned de $total ganadas',
        'de': '$earned von $total verdient',
      });

  String get lastWeekBadges => _t({
        'en': 'Last Week Badges',
        'pl': 'Odznaki z zeszłego tygodnia',
        'nl': 'Badges van vorige week',
        'es': 'Insignias de la semana pasada',
        'de': 'Abzeichen der letzten Woche',
      });

  /// Localized title + subtitle for a badge id (see WeeklyBadgeService /
  /// kBadgeCatalog). Falls back to the id if unknown.
  ({String title, String subtitle}) weeklyBadgeText(String id) {
    switch (id) {
      case 'perfect_log_week':
        return (
          title: _t({
            'en': 'Perfect Log Week',
            'pl': 'Idealny tydzień zapisów',
            'nl': 'Perfecte logweek',
            'es': 'Semana de registro perfecta',
            'de': 'Perfekte Log-Woche',
          }),
          subtitle: _t({
            'en': 'You logged food every day last week.',
            'pl': 'W zeszłym tygodniu zapisywałeś jedzenie każdego dnia.',
            'nl': 'Je hebt vorige week elke dag eten gelogd.',
            'es': 'Registraste comida todos los días la semana pasada.',
            'de': 'Du hast letzte Woche jeden Tag Essen geloggt.',
          }),
        );
      case 'steady_tracker':
        return (
          title: _t({
            'en': 'Steady Tracker',
            'pl': 'Wytrwały tropiciel',
            'nl': 'Stabiele tracker',
            'es': 'Seguimiento constante',
            'de': 'Beständiger Tracker',
          }),
          subtitle: _t({
            'en': 'You kept nutrition tracking consistent.',
            'pl': 'Konsekwentnie śledziłeś odżywianie.',
            'nl': 'Je hield het voedingsregistratie consistent.',
            'es': 'Mantuviste el seguimiento nutricional constante.',
            'de': 'Du hast die Ernährungserfassung konstant gehalten.',
          }),
        );
      case 'streak_builder':
        return (
          title: _t({
            'en': 'Streak Builder',
            'pl': 'Budowniczy serii',
            'nl': 'Reeksbouwer',
            'es': 'Constructor de rachas',
            'de': 'Serien-Baumeister',
          }),
          subtitle: _t({
            'en': 'Your logging rhythm held for consecutive days.',
            'pl': 'Twój rytm zapisów utrzymał się przez kolejne dni.',
            'nl': 'Je logritme hield meerdere dagen op rij stand.',
            'es': 'Tu ritmo de registro se mantuvo días seguidos.',
            'de': 'Dein Log-Rhythmus hielt mehrere Tage in Folge.',
          }),
        );
      case 'scanner_momentum':
        return (
          title: _t({
            'en': 'Scanner Momentum',
            'pl': 'Rozpęd skanera',
            'nl': 'Scannermomentum',
            'es': 'Impulso de escaneo',
            'de': 'Scanner-Schwung',
          }),
          subtitle: _t({
            'en': 'You used the app often enough to build a useful record.',
            'pl': 'Używałeś aplikacji wystarczająco często, aby zbudować przydatny zapis.',
            'nl': 'Je gebruikte de app vaak genoeg voor een nuttig overzicht.',
            'es': 'Usaste la app lo suficiente para crear un registro útil.',
            'de': 'Du hast die App oft genug für eine nützliche Aufzeichnung genutzt.',
          }),
        );
      case 'protein_focus':
        return (
          title: _t({
            'en': 'Protein Focus',
            'pl': 'Skupienie na białku',
            'nl': 'Eiwitfocus',
            'es': 'Enfoque en proteínas',
            'de': 'Protein-Fokus',
          }),
          subtitle: _t({
            'en': 'You stayed close to your protein target most of the week.',
            'pl': 'Przez większość tygodnia byłeś blisko celu białkowego.',
            'nl': 'Je zat het grootste deel van de week dicht bij je eiwitdoel.',
            'es': 'Estuviste cerca de tu objetivo de proteína casi toda la semana.',
            'de': 'Du warst die meiste Woche nah an deinem Proteinziel.',
          }),
        );
      case 'balanced_plate':
        return (
          title: _t({
            'en': 'Balanced Plate',
            'pl': 'Zrównoważony talerz',
            'nl': 'Gebalanceerd bord',
            'es': 'Plato equilibrado',
            'de': 'Ausgewogener Teller',
          }),
          subtitle: _t({
            'en': 'Your calorie and protein pattern stayed in a healthy range.',
            'pl': 'Twój wzorzec kalorii i białka pozostał w zdrowym zakresie.',
            'nl': 'Je calorie- en eiwitpatroon bleef in een gezond bereik.',
            'es': 'Tu patrón de calorías y proteína se mantuvo saludable.',
            'de': 'Dein Kalorien- und Proteinmuster blieb im gesunden Bereich.',
          }),
        );
      case 'micronutrient_pro':
        return (
          title: _t({
            'en': 'Micronutrient Pro',
            'pl': 'Mistrz mikroskładników',
            'nl': 'Micronutriënt-pro',
            'es': 'Pro de micronutrientes',
            'de': 'Mikronährstoff-Profi',
          }),
          subtitle: _t({
            'en': 'You reached broad vitamin and mineral coverage.',
            'pl': 'Osiągnąłeś szerokie pokrycie witamin i minerałów.',
            'nl': 'Je bereikte een brede vitamine- en mineralendekking.',
            'es': 'Alcanzaste una amplia cobertura de vitaminas y minerales.',
            'de': 'Du hast eine breite Vitamin- und Mineralstoffabdeckung erreicht.',
          }),
        );
      case 'hydration_rhythm':
        return (
          title: _t({
            'en': 'Hydration Rhythm',
            'pl': 'Rytm nawodnienia',
            'nl': 'Hydratatieritme',
            'es': 'Ritmo de hidratación',
            'de': 'Hydration-Rhythmus',
          }),
          subtitle: _t({
            'en': 'You logged drinks across the week.',
            'pl': 'Zapisywałeś napoje przez cały tydzień.',
            'nl': 'Je logde drankjes door de week heen.',
            'es': 'Registraste bebidas durante la semana.',
            'de': 'Du hast Getränke über die Woche geloggt.',
          }),
        );
      default:
        return (title: id, subtitle: '');
    }
  }

  /// How a badge is earned, phrased as a goal (used for locked badges).
  String weeklyBadgeHowTo(String id) {
    switch (id) {
      case 'perfect_log_week':
        return _t({
          'en': 'Log food every day for a full week.',
          'pl': 'Zapisuj jedzenie codziennie przez cały tydzień.',
          'nl': 'Log elke dag eten, een hele week lang.',
          'es': 'Registra comida todos los días durante una semana completa.',
          'de': 'Logge eine ganze Woche lang jeden Tag Essen.',
        });
      case 'steady_tracker':
        return _t({
          'en': 'Log food on at least 5 days in a week.',
          'pl': 'Zapisuj jedzenie przez co najmniej 5 dni w tygodniu.',
          'nl': 'Log eten op minstens 5 dagen in een week.',
          'es': 'Registra comida al menos 5 días en una semana.',
          'de': 'Logge an mindestens 5 Tagen pro Woche Essen.',
        });
      case 'streak_builder':
        return _t({
          'en': 'Log food 3 or more days in a row.',
          'pl': 'Zapisuj jedzenie przez 3 lub więcej dni z rzędu.',
          'nl': 'Log eten 3 of meer dagen op rij.',
          'es': 'Registra comida 3 o más días seguidos.',
          'de': 'Logge an 3 oder mehr Tagen in Folge Essen.',
        });
      case 'scanner_momentum':
        return _t({
          'en': 'Record at least 10 food logs in a week.',
          'pl': 'Zarejestruj co najmniej 10 wpisów jedzenia w tygodniu.',
          'nl': 'Registreer minstens 10 voedingslogs in een week.',
          'es': 'Registra al menos 10 comidas en una semana.',
          'de': 'Erfasse mindestens 10 Essenseinträge in einer Woche.',
        });
      case 'protein_focus':
        return _t({
          'en': 'Hit your protein target on 4 or more days.',
          'pl': 'Osiągnij cel białkowy przez 4 lub więcej dni.',
          'nl': 'Haal je eiwitdoel op 4 of meer dagen.',
          'es': 'Alcanza tu objetivo de proteína 4 o más días.',
          'de': 'Erreiche dein Proteinziel an 4 oder mehr Tagen.',
        });
      case 'balanced_plate':
        return _t({
          'en': 'Keep calories and protein balanced on 3 or more days.',
          'pl': 'Utrzymaj zrównoważone kalorie i białko przez 3 lub więcej dni.',
          'nl': 'Houd calorieën en eiwit in balans op 3 of meer dagen.',
          'es': 'Mantén calorías y proteína equilibradas 3 o más días.',
          'de': 'Halte Kalorien und Protein an 3 oder mehr Tagen ausgewogen.',
        });
      case 'micronutrient_pro':
        return _t({
          'en': 'Reach broad vitamin and mineral coverage on 3 or more days.',
          'pl': 'Osiągnij szerokie pokrycie witamin i minerałów przez 3 lub więcej dni.',
          'nl': 'Bereik brede vitamine- en mineralendekking op 3 of meer dagen.',
          'es': 'Alcanza amplia cobertura de vitaminas y minerales 3 o más días.',
          'de': 'Erreiche an 3 oder mehr Tagen breite Vitamin- und Mineralstoffabdeckung.',
        });
      case 'hydration_rhythm':
        return _t({
          'en': 'Log drinks on 4 or more days in a week.',
          'pl': 'Zapisuj napoje przez 4 lub więcej dni w tygodniu.',
          'nl': 'Log drankjes op 4 of meer dagen in een week.',
          'es': 'Registra bebidas 4 o más días en una semana.',
          'de': 'Logge an 4 oder mehr Tagen pro Woche Getränke.',
        });
      default:
        return '';
    }
  }

  String get badgeCollectionSubtitle => _t({
        'en': "See every badge you've earned and what's left to unlock.",
        'pl': 'Zobacz wszystkie zdobyte odznaki i te do odblokowania.',
        'nl': 'Bekijk elke verdiende badge en wat je nog kunt ontgrendelen.',
        'es': 'Mira cada insignia ganada y lo que falta por desbloquear.',
        'de': 'Sieh jedes verdiente Abzeichen und was noch zu holen ist.',
      });

  String get badgeEarnedLabel => _t({
        'en': 'Earned',
        'pl': 'Zdobyto',
        'nl': 'Verdiend',
        'es': 'Ganada',
        'de': 'Verdient',
      });

  String get badgeLockedLabel => _t({
        'en': 'Locked',
        'pl': 'Zablokowana',
        'nl': 'Vergrendeld',
        'es': 'Bloqueada',
        'de': 'Gesperrt',
      });

  String get badgeHowToEarnLabel => _t({
        'en': 'How to earn',
        'pl': 'Jak zdobyć',
        'nl': 'Hoe te verdienen',
        'es': 'Cómo ganarla',
        'de': 'So verdienst du es',
      });

  String get weeklyChallengesTitle => _t({
        'en': 'Weekly Challenges',
        'pl': 'Tygodniowe wyzwania',
        'nl': 'Wekelijkse uitdagingen',
        'es': 'Desafíos semanales',
        'de': 'Wöchentliche Herausforderungen',
      });

  String get challengeHowToTitle => _t({
        'en': 'How to complete',
        'pl': 'Jak ukończyć',
        'nl': 'Hoe te voltooien',
        'es': 'Cómo completar',
        'de': 'So schaffst du es',
      });

  String get challengeCompletedLabel => _t({
        'en': 'Completed!',
        'pl': 'Ukończono!',
        'nl': 'Voltooid!',
        'es': '¡Completado!',
        'de': 'Abgeschlossen!',
      });

  /// Localized title + how-to for a weekly challenge id (ChallengeType.name).
  ({String title, String howTo}) weeklyChallengeText(String id) {
    switch (id) {
      case 'scanStreak3':
        return (
          title: _t({
            'en': '3-Day Scan Streak',
            'pl': 'Seria 3 dni skanowania',
            'nl': 'Scanreeks van 3 dagen',
            'es': 'Racha de escaneo de 3 días',
            'de': '3-Tage-Scan-Serie',
          }),
          howTo: _t({
            'en': 'Scan at least one meal for 3 consecutive days.',
            'pl': 'Zeskanuj co najmniej jeden posiłek przez 3 kolejne dni.',
            'nl': 'Scan minstens één maaltijd op 3 opeenvolgende dagen.',
            'es': 'Escanea al menos una comida durante 3 días seguidos.',
            'de': 'Scanne an 3 aufeinanderfolgenden Tagen mindestens eine Mahlzeit.',
          }),
        );
      case 'hitGoal5Days':
        return (
          title: _t({
            'en': 'On Target',
            'pl': 'W celu',
            'nl': 'Op koers',
            'es': 'En el objetivo',
            'de': 'Im Ziel',
          }),
          howTo: _t({
            'en': 'Stay within 10% of your calorie goal for 5 days.',
            'pl': 'Utrzymaj się w granicach 10% celu kalorycznego przez 5 dni.',
            'nl': 'Blijf 5 dagen binnen 10% van je caloriedoel.',
            'es': 'Mantente dentro del 10% de tu objetivo de calorías durante 5 días.',
            'de': 'Bleibe an 5 Tagen innerhalb von 10 % deines Kalorienziels.',
          }),
        );
      case 'logProtein80':
        return (
          title: _t({
            'en': 'Protein Power',
            'pl': 'Moc białka',
            'nl': 'Eiwitkracht',
            'es': 'Poder proteico',
            'de': 'Protein-Power',
          }),
          howTo: _t({
            'en': 'Log at least 80 g protein for 4 days.',
            'pl': 'Zapisz co najmniej 80 g białka przez 4 dni.',
            'nl': 'Log minstens 80 g eiwit op 4 dagen.',
            'es': 'Registra al menos 80 g de proteína durante 4 días.',
            'de': 'Logge an 4 Tagen mindestens 80 g Protein.',
          }),
        );
      case 'drinkWater7Days':
        return (
          title: _t({
            'en': 'Hydration Hero',
            'pl': 'Bohater nawodnienia',
            'nl': 'Hydratatieheld',
            'es': 'Héroe de la hidratación',
            'de': 'Hydrations-Held',
          }),
          howTo: _t({
            'en': 'Hit your water goal every day this week.',
            'pl': 'Osiągaj swój cel wodny każdego dnia w tym tygodniu.',
            'nl': 'Haal je waterdoel elke dag deze week.',
            'es': 'Alcanza tu objetivo de agua todos los días esta semana.',
            'de': 'Erreiche diese Woche jeden Tag dein Wasserziel.',
          }),
        );
      case 'scan10Foods':
        return (
          title: _t({
            'en': 'Food Explorer',
            'pl': 'Odkrywca jedzenia',
            'nl': 'Voedselontdekker',
            'es': 'Explorador de alimentos',
            'de': 'Essens-Entdecker',
          }),
          howTo: _t({
            'en': 'Scan 10 different foods this week.',
            'pl': 'Zeskanuj 10 różnych produktów w tym tygodniu.',
            'nl': 'Scan 10 verschillende voedingsmiddelen deze week.',
            'es': 'Escanea 10 alimentos diferentes esta semana.',
            'de': 'Scanne diese Woche 10 verschiedene Lebensmittel.',
          }),
        );
      case 'noSugarSpike':
        return (
          title: _t({
            'en': 'Steady Sugar',
            'pl': 'Stabilny cukier',
            'nl': 'Stabiele suiker',
            'es': 'Azúcar estable',
            'de': 'Stabiler Zucker',
          }),
          howTo: _t({
            'en': 'Keep all meals under GL 20 for 3 days.',
            'pl': 'Utrzymaj wszystkie posiłki poniżej ładunku glikemicznego 20 przez 3 dni.',
            'nl': 'Houd alle maaltijden onder GL 20 gedurende 3 dagen.',
            'es': 'Mantén todas las comidas por debajo de CG 20 durante 3 días.',
            'de': 'Halte alle Mahlzeiten an 3 Tagen unter GL 20.',
          }),
        );
      default:
        return (title: id, howTo: '');
    }
  }

  // ── Home / dashboard ──

  String get loadingYourData => _t({
        'en': 'Loading your data…',
        'pl': 'Ładowanie danych…',
        'nl': 'Je gegevens laden…',
        'es': 'Cargando tus datos…',
        'de': 'Deine Daten werden geladen…',
      });

  String editFoodTitle(String label) => _t({
        'en': 'Edit "$label"',
        'pl': 'Edytuj „$label"',
        'nl': '"$label" bewerken',
        'es': 'Editar "$label"',
        'de': '"$label" bearbeiten',
      });

  String get noFoodLoggedTodayLong => _t({
        'en': 'No food logged yet today.\nScan or add food to start tracking!',
        'pl': 'Nie zapisano dziś jeszcze jedzenia.\nZeskanuj lub dodaj jedzenie, aby zacząć śledzić!',
        'nl': 'Nog geen eten gelogd vandaag.\nScan of voeg eten toe om te beginnen met bijhouden!',
        'es': 'Aún no has registrado comida hoy.\n¡Escanea o añade comida para empezar a registrar!',
        'de': 'Heute noch kein Essen geloggt.\nScanne oder füge Essen hinzu, um zu starten!',
      });

  String get smartRecommendations => _t({
        'en': 'Smart Recommendations',
        'pl': 'Inteligentne rekomendacje',
        'nl': 'Slimme aanbevelingen',
        'es': 'Recomendaciones inteligentes',
        'de': 'Intelligente Empfehlungen',
      });

  String tipsCount(int n) => _t({
        'en': '$n tips',
        'pl': n == 1 ? '$n wskazówka' : '$n wskazówek',
        'nl': n == 1 ? '$n tip' : '$n tips',
        'es': n == 1 ? '$n consejo' : '$n consejos',
        'de': n == 1 ? '$n Tipp' : '$n Tipps',
      });

  String dayStreakLabel(int n) => _t({
        'en': '$n day streak',
        'pl': '$n-dniowa passa',
        'nl': 'reeks van $n dagen',
        'es': 'racha de $n días',
        'de': '$n-Tage-Serie',
      });

  String get hydrationTitle => _t({
        'en': 'Hydration',
        'pl': 'Nawodnienie',
        'nl': 'Hydratatie',
        'es': 'Hidratación',
        'de': 'Flüssigkeitszufuhr',
      });

  String get hydrationGoalReached => _t({
        'en': '🎉 Hydration goal reached!',
        'pl': '🎉 Cel nawodnienia osiągnięty!',
        'nl': '🎉 Hydratatiedoel bereikt!',
        'es': '🎉 ¡Objetivo de hidratación alcanzado!',
        'de': '🎉 Hydrationsziel erreicht!',
      });

  String waterRemaining(String amount) => _t({
        'en': '$amount remaining',
        'pl': 'pozostało $amount',
        'nl': '$amount resterend',
        'es': '$amount restante',
        'de': '$amount übrig',
      });

  String get removeWaterTooltip => _t({
        'en': 'Remove 250 ml',
        'pl': 'Usuń 250 ml',
        'nl': '250 ml verwijderen',
        'es': 'Quitar 250 ml',
        'de': '250 ml entfernen',
      });

  String get addDrinkTooltip => _t({
        'en': 'Add drink',
        'pl': 'Dodaj napój',
        'nl': 'Drankje toevoegen',
        'es': 'Añadir bebida',
        'de': 'Getränk hinzufügen',
      });

  String get adjustWaterGoalTooltip => _t({
        'en': 'Adjust water goal',
        'pl': 'Dostosuj cel wody',
        'nl': 'Waterdoel aanpassen',
        'es': 'Ajustar objetivo de agua',
        'de': 'Wasserziel anpassen',
      });

  String get scan3dModelTag => _t({
        'en': '3D model',
        'pl': 'model 3D',
        'nl': '3D-model',
        'es': 'modelo 3D',
        'de': '3D-Modell',
      });

  String get timeJustNow => _t({
        'en': 'just now',
        'pl': 'przed chwilą',
        'nl': 'zojuist',
        'es': 'ahora mismo',
        'de': 'gerade eben',
      });

  String minutesAgoShort(int n) => _t({
        'en': '${n}m ago',
        'pl': '$n min temu',
        'nl': '$n min geleden',
        'es': 'hace $n min',
        'de': 'vor $n Min.',
      });

  String hoursAgoShort(int n) => _t({
        'en': '${n}h ago',
        'pl': '$n godz. temu',
        'nl': '$n uur geleden',
        'es': 'hace $n h',
        'de': 'vor $n Std.',
      });

  String daysAgoShort(int n) => _t({
        'en': '${n}d ago',
        'pl': '$n dni temu',
        'nl': '$n dagen geleden',
        'es': 'hace $n d',
        'de': 'vor $n T.',
      });

  /// Localized 3-letter weekday name. [weekday]: 1 = Mon … 7 = Sun.
  String weekdayShort(int weekday) {
    final i = (weekday - 1) % 7;
    switch (_lang) {
      case 'pl':
        return const ['Pon', 'Wto', 'Śro', 'Czw', 'Pią', 'Sob', 'Nie'][i];
      case 'nl':
        return const ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'][i];
      case 'es':
        return const ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'][i];
      case 'de':
        return const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'][i];
      default:
        return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i];
    }
  }

  /// Localized 3-letter month name. [month]: 1 = Jan … 12 = Dec.
  String monthShort(int month) {
    final i = (month - 1) % 12;
    switch (_lang) {
      case 'pl':
        return const ['Sty', 'Lut', 'Mar', 'Kwi', 'Maj', 'Cze', 'Lip', 'Sie', 'Wrz', 'Paź', 'Lis', 'Gru'][i];
      case 'nl':
        return const ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'][i];
      case 'es':
        return const ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'][i];
      case 'de':
        return const ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'][i];
      default:
        return const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][i];
    }
  }

  // ── Analytics ──

  String get analyticsAverageMacros => _t({
        'en': 'Average macros',
        'pl': 'Średnie makroskładniki',
        'nl': 'Gemiddelde macro’s',
        'es': 'Macros promedio',
        'de': 'Durchschnittliche Makros',
      });

  String get analyticsWeekdayPattern => _t({
        'en': 'Weekday pattern',
        'pl': 'Wzorzec dni tygodnia',
        'nl': 'Weekdagpatroon',
        'es': 'Patrón por día de la semana',
        'de': 'Wochentag-Muster',
      });

  String get analyticsWeekdayPatternSub => _t({
        'en': 'Average kcal per weekday',
        'pl': 'Średnie kcal na dzień tygodnia',
        'nl': 'Gemiddelde kcal per weekdag',
        'es': 'Kcal promedio por día',
        'de': 'Durchschnittliche kcal pro Wochentag',
      });

  String get analyticsDayByDay => _t({
        'en': 'Day by day',
        'pl': 'Dzień po dniu',
        'nl': 'Dag voor dag',
        'es': 'Día a día',
        'de': 'Tag für Tag',
      });

  String get analyticsGoalLabel => _t({
        'en': 'Goal',
        'pl': 'Cel',
        'nl': 'Doel',
        'es': 'Meta',
        'de': 'Ziel',
      });

  /// Localized full weekday name. [weekday]: 1 = Mon … 7 = Sun.
  String weekdayFull(int weekday) {
    final i = (weekday - 1) % 7;
    switch (_lang) {
      case 'pl':
        return const ['Poniedziałek', 'Wtorek', 'Środa', 'Czwartek', 'Piątek', 'Sobota', 'Niedziela'][i];
      case 'nl':
        return const ['Maandag', 'Dinsdag', 'Woensdag', 'Donderdag', 'Vrijdag', 'Zaterdag', 'Zondag'][i];
      case 'es':
        return const ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'][i];
      case 'de':
        return const ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'][i];
      default:
        return const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][i];
    }
  }

  // ── Voice / manual / recipes errors ──

  String get voiceErrNoMatch => _t({
        'en': 'I didn\'t catch that. Tap the mic and clearly say the food and amount, e.g. "a banana" or "200 grams of chicken".',
        'pl': 'Nie zrozumiałem. Dotknij mikrofonu i wyraźnie powiedz jedzenie i ilość, np. „banan" lub „200 gramów kurczaka".',
        'nl': 'Ik verstond dat niet. Tik op de microfoon en zeg duidelijk het eten en de hoeveelheid, bijv. "een banaan" of "200 gram kip".',
        'es': 'No lo entendí. Toca el micrófono y di claramente la comida y la cantidad, p. ej. "un plátano" o "200 gramos de pollo".',
        'de': 'Das habe ich nicht verstanden. Tippe auf das Mikrofon und sage Essen und Menge deutlich, z. B. "eine Banane" oder "200 Gramm Hähnchen".',
      });

  String get voiceErrPermission => _t({
        'en': 'Microphone or speech permission is off. Enable it in your phone settings to use voice logging.',
        'pl': 'Uprawnienia mikrofonu lub mowy są wyłączone. Włącz je w ustawieniach telefonu, aby korzystać z logowania głosowego.',
        'nl': 'Microfoon- of spraaktoestemming staat uit. Schakel deze in bij je telefooninstellingen om spraakloggen te gebruiken.',
        'es': 'El permiso de micrófono o voz está desactivado. Actívalo en los ajustes del teléfono para usar el registro por voz.',
        'de': 'Mikrofon- oder Sprachberechtigung ist aus. Aktiviere sie in den Telefoneinstellungen, um die Sprachaufzeichnung zu nutzen.',
      });

  String get voiceErrNetwork => _t({
        'en': 'Voice recognition needs a connection right now. Check your network and try again.',
        'pl': 'Rozpoznawanie mowy wymaga teraz połączenia. Sprawdź sieć i spróbuj ponownie.',
        'nl': 'Spraakherkenning heeft nu een verbinding nodig. Controleer je netwerk en probeer opnieuw.',
        'es': 'El reconocimiento de voz necesita conexión ahora. Revisa tu red e inténtalo de nuevo.',
        'de': 'Die Spracherkennung braucht gerade eine Verbindung. Prüfe dein Netzwerk und versuche es erneut.',
      });

  String get voiceErrBusy => _t({
        'en': 'The microphone is busy. Wait a moment, then try again.',
        'pl': 'Mikrofon jest zajęty. Poczekaj chwilę i spróbuj ponownie.',
        'nl': 'De microfoon is bezig. Wacht even en probeer opnieuw.',
        'es': 'El micrófono está ocupado. Espera un momento e inténtalo de nuevo.',
        'de': 'Das Mikrofon ist belegt. Warte einen Moment und versuche es erneut.',
      });

  String get voiceErrGeneric => _t({
        'en': 'I couldn\'t process that audio. Please try again.',
        'pl': 'Nie udało się przetworzyć tego dźwięku. Spróbuj ponownie.',
        'nl': 'Ik kon die audio niet verwerken. Probeer het opnieuw.',
        'es': 'No pude procesar ese audio. Inténtalo de nuevo.',
        'de': 'Ich konnte dieses Audio nicht verarbeiten. Bitte versuche es erneut.',
      });

  String get voiceRecognitionUnavailable => _t({
        'en': 'Speech recognition is unavailable right now.',
        'pl': 'Rozpoznawanie mowy jest obecnie niedostępne.',
        'nl': 'Spraakherkenning is momenteel niet beschikbaar.',
        'es': 'El reconocimiento de voz no está disponible ahora.',
        'de': 'Die Spracherkennung ist derzeit nicht verfügbar.',
      });

  String get voiceNotAvailableOnDevice => _t({
        'en': 'Speech recognition is not available on this device.',
        'pl': 'Rozpoznawanie mowy nie jest dostępne na tym urządzeniu.',
        'nl': 'Spraakherkenning is niet beschikbaar op dit apparaat.',
        'es': 'El reconocimiento de voz no está disponible en este dispositivo.',
        'de': 'Die Spracherkennung ist auf diesem Gerät nicht verfügbar.',
      });

  String get barcodeProductNotFound => _t({
        'en': 'Product not found in the OpenFoodFacts database. Try adding it manually.',
        'pl': 'Nie znaleziono produktu w bazie OpenFoodFacts. Spróbuj dodać go ręcznie.',
        'nl': 'Product niet gevonden in de OpenFoodFacts-database. Voeg het handmatig toe.',
        'es': 'Producto no encontrado en la base de datos de OpenFoodFacts. Intenta añadirlo manualmente.',
        'de': 'Produkt nicht in der OpenFoodFacts-Datenbank gefunden. Füge es manuell hinzu.',
      });

  String get recipeLoadError => _t({
        'en': 'Couldn\'t load recipes. Pull down to refresh or try again.',
        'pl': 'Nie udało się załadować przepisów. Pociągnij, aby odświeżyć, lub spróbuj ponownie.',
        'nl': 'Kon recepten niet laden. Trek omlaag om te vernieuwen of probeer opnieuw.',
        'es': 'No se pudieron cargar las recetas. Desliza para actualizar o inténtalo de nuevo.',
        'de': 'Rezepte konnten nicht geladen werden. Zum Aktualisieren nach unten ziehen oder erneut versuchen.',
      });

  // ── Smart grocery / pantry ──

  String get smartGroceryTitle => _t({
        'en': 'Smart grocery & pantry',
        'pl': 'Inteligentne zakupy i spiżarnia',
        'nl': 'Slimme boodschappen & voorraad',
        'es': 'Compra y despensa inteligentes',
        'de': 'Smarte Einkäufe & Vorrat',
      });

  String get smartGrocerySubtitle => _t({
        'en': 'Track what you have at home. Marking groceries as bought fills your pantry; logging food uses it up.',
        'pl': 'Śledź, co masz w domu. Oznaczanie zakupów jako kupione uzupełnia spiżarnię; logowanie jedzenia ją zużywa.',
        'nl': 'Houd bij wat je in huis hebt. Boodschappen als gekocht markeren vult je voorraad; eten loggen gebruikt het op.',
        'es': 'Controla lo que tienes en casa. Marcar la compra como comprada llena tu despensa; registrar comida la consume.',
        'de': 'Behalte im Blick, was du zu Hause hast. Als gekauft markierte Einkäufe füllen den Vorrat; Essen loggen verbraucht ihn.',
      });

  String get pantrySectionTitle => _t({
        'en': 'What you have at home',
        'pl': 'Co masz w domu',
        'nl': 'Wat je in huis hebt',
        'es': 'Lo que tienes en casa',
        'de': 'Was du zu Hause hast',
      });

  String get pantryEmptyHint => _t({
        'en': 'Nothing here yet. Mark grocery items as bought to fill your pantry.',
        'pl': 'Jeszcze nic tu nie ma. Oznacz produkty jako kupione, aby uzupełnić spiżarnię.',
        'nl': 'Nog niets hier. Markeer boodschappen als gekocht om je voorraad te vullen.',
        'es': 'Aún no hay nada. Marca productos como comprados para llenar tu despensa.',
        'de': 'Noch nichts hier. Markiere Einkäufe als gekauft, um deinen Vorrat zu füllen.',
      });

  String pantryItemsCount(int n) => _t({
        'en': n == 1 ? '$n item' : '$n items',
        'pl': n == 1 ? '$n produkt' : '$n produktów',
        'nl': n == 1 ? '$n item' : '$n items',
        'es': n == 1 ? '$n artículo' : '$n artículos',
        'de': n == 1 ? '$n Artikel' : '$n Artikel',
      });

  String get markBoughtTooltip => _t({
        'en': 'Bought — add to pantry',
        'pl': 'Kupione — dodaj do spiżarni',
        'nl': 'Gekocht — aan voorraad toevoegen',
        'es': 'Comprado — añadir a la despensa',
        'de': 'Gekauft — zum Vorrat hinzufügen',
      });

  String get dontBuyTooltip => _t({
        'en': 'Don\'t buy',
        'pl': 'Nie kupuj',
        'nl': 'Niet kopen',
        'es': 'No comprar',
        'de': 'Nicht kaufen',
      });

  String addedToPantrySnack(String name) => _t({
        'en': '$name added to your pantry',
        'pl': 'Dodano $name do spiżarni',
        'nl': '$name toegevoegd aan je voorraad',
        'es': '$name añadido a tu despensa',
        'de': '$name zum Vorrat hinzugefügt',
      });

  String removedFromListSnack(String name) => _t({
        'en': '$name removed',
        'pl': 'Usunięto $name',
        'nl': '$name verwijderd',
        'es': '$name eliminado',
        'de': '$name entfernt',
      });

  String get undoAction => _t({
        'en': 'Undo',
        'pl': 'Cofnij',
        'nl': 'Ongedaan maken',
        'es': 'Deshacer',
        'de': 'Rückgängig',
      });

  String get pantryAddedFromPhoto => _t({
        'en': 'Added to your pantry from the photo',
        'pl': 'Dodano do spiżarni ze zdjęcia',
        'nl': 'Toegevoegd aan je voorraad vanaf de foto',
        'es': 'Añadido a tu despensa desde la foto',
        'de': 'Aus dem Foto zum Vorrat hinzugefügt',
      });

  String groceryToBuy(int n) => _t({
        'en': 'To buy ($n)',
        'pl': 'Do kupienia ($n)',
        'nl': 'Te kopen ($n)',
        'es': 'Por comprar ($n)',
        'de': 'Einzukaufen ($n)',
      });

  String groceryPurchased(int n) => _t({
        'en': 'Purchased ($n)',
        'pl': 'Kupione ($n)',
        'nl': 'Gekocht ($n)',
        'es': 'Comprado ($n)',
        'de': 'Gekauft ($n)',
      });

  // ── Food-group balance ──

  String get foodGroupBalanceTitle => _t({
        'en': 'Food group balance',
        'pl': 'Bilans grup żywności',
        'nl': 'Voedingsgroepen-balans',
        'es': 'Equilibrio de grupos de alimentos',
        'de': 'Lebensmittelgruppen-Balance',
      });

  String get foodGroupBalanceSubtitle => _t({
        'en': 'See how your fruit, veg, protein and more compare to daily targets.',
        'pl': 'Zobacz, jak owoce, warzywa, białko i inne wypadają wobec dziennych celów.',
        'nl': 'Zie hoe je fruit, groente, eiwit en meer zich verhouden tot dagdoelen.',
        'es': 'Mira cómo tus frutas, verduras, proteína y más se comparan con los objetivos diarios.',
        'de': 'Sieh, wie Obst, Gemüse, Protein und mehr im Vergleich zu den Tageszielen stehen.',
      });

  String get periodToday => _t({
        'en': 'Today',
        'pl': 'Dziś',
        'nl': 'Vandaag',
        'es': 'Hoy',
        'de': 'Heute',
      });

  String get periodThisWeek => _t({
        'en': 'This week',
        'pl': 'Ten tydzień',
        'nl': 'Deze week',
        'es': 'Esta semana',
        'de': 'Diese Woche',
      });

  String servingsProgress(String current, String target) => _t({
        'en': '$current / $target servings',
        'pl': '$current / $target porcji',
        'nl': '$current / $target porties',
        'es': '$current / $target porciones',
        'de': '$current / $target Portionen',
      });

  String get foodGroupGuidanceNote => _t({
        'en': 'General healthy-eating guidance, not medical advice.',
        'pl': 'Ogólne wskazówki dotyczące zdrowego odżywiania, nie porada medyczna.',
        'nl': 'Algemene richtlijn voor gezond eten, geen medisch advies.',
        'es': 'Orientación general de alimentación saludable, no consejo médico.',
        'de': 'Allgemeine Empfehlung zur gesunden Ernährung, kein medizinischer Rat.',
      });

  /// Localized name of a [FoodGroup] (id = FoodGroup.name).
  String foodGroupName(String id) {
    switch (id) {
      case 'fruit':
        return _t({
          'en': 'Fruit',
          'pl': 'Owoce',
          'nl': 'Fruit',
          'es': 'Frutas',
          'de': 'Obst',
        });
      case 'vegetables':
        return _t({
          'en': 'Vegetables',
          'pl': 'Warzywa',
          'nl': 'Groenten',
          'es': 'Verduras',
          'de': 'Gemüse',
        });
      case 'protein':
        return _t({
          'en': 'Protein',
          'pl': 'Białko',
          'nl': 'Eiwit',
          'es': 'Proteína',
          'de': 'Protein',
        });
      case 'dairy':
        return _t({
          'en': 'Dairy',
          'pl': 'Nabiał',
          'nl': 'Zuivel',
          'es': 'Lácteos',
          'de': 'Milchprodukte',
        });
      case 'grains':
        return _t({
          'en': 'Grains',
          'pl': 'Zboża',
          'nl': 'Granen',
          'es': 'Cereales',
          'de': 'Getreide',
        });
      default:
        return id;
    }
  }

  // ── Grocery tab chrome ──

  String get groceryScanWhatYouHave => _t({
        'en': 'Scan what you have at home',
        'pl': 'Zeskanuj, co masz w domu',
        'nl': 'Scan wat je in huis hebt',
        'es': 'Escanea lo que tienes en casa',
        'de': 'Scanne, was du zu Hause hast',
      });

  String get grocerySmartSuggestionsTooltip => _t({
        'en': 'Smart suggestions from history',
        'pl': 'Inteligentne sugestie z historii',
        'nl': 'Slimme suggesties uit geschiedenis',
        'es': 'Sugerencias inteligentes del historial',
        'de': 'Intelligente Vorschläge aus dem Verlauf',
      });

  String get groceryAddItemTooltip => _t({
        'en': 'Add item',
        'pl': 'Dodaj produkt',
        'nl': 'Item toevoegen',
        'es': 'Añadir artículo',
        'de': 'Artikel hinzufügen',
      });

  String get groceryClearPurchased => _t({
        'en': 'Clear purchased items',
        'pl': 'Wyczyść kupione produkty',
        'nl': 'Gekochte items wissen',
        'es': 'Borrar artículos comprados',
        'de': 'Gekaufte Artikel löschen',
      });

  String get grocerySelectAllDelete => _t({
        'en': 'Select all & delete',
        'pl': 'Zaznacz wszystko i usuń',
        'nl': 'Alles selecteren en verwijderen',
        'es': 'Seleccionar todo y eliminar',
        'de': 'Alle auswählen & löschen',
      });

  String groceryDeleteAllBody(int n) => _t({
        'en': 'This removes all $n items from your grocery list.',
        'pl': 'To usunie wszystkie $n produktów z Twojej listy zakupów.',
        'nl': 'Hiermee verwijder je alle $n items van je boodschappenlijst.',
        'es': 'Esto elimina los $n artículos de tu lista de compras.',
        'de': 'Dies entfernt alle $n Artikel von deiner Einkaufsliste.',
      });

  String get groceryListEmpty => _t({
        'en': 'Your grocery list is empty',
        'pl': 'Twoja lista zakupów jest pusta',
        'nl': 'Je boodschappenlijst is leeg',
        'es': 'Tu lista de compras está vacía',
        'de': 'Deine Einkaufsliste ist leer',
      });

  String get grocerySnapFridge => _t({
        'en': 'Snap your fridge, pantry or basket (optional)',
        'pl': 'Zrób zdjęcie lodówki, spiżarni lub koszyka (opcjonalnie)',
        'nl': 'Fotografeer je koelkast, voorraad of mandje (optioneel)',
        'es': 'Haz una foto de tu nevera, despensa o cesta (opcional)',
        'de': 'Fotografiere deinen Kühlschrank, Vorrat oder Korb (optional)',
      });

  String get groceryPhotosLocal => _t({
        'en': 'Photos stay on your device and are never uploaded.',
        'pl': 'Zdjęcia pozostają na urządzeniu i nigdy nie są przesyłane.',
        'nl': 'Foto’s blijven op je apparaat en worden nooit geüpload.',
        'es': 'Las fotos permanecen en tu dispositivo y nunca se suben.',
        'de': 'Fotos bleiben auf deinem Gerät und werden nie hochgeladen.',
      });

  String get groceryScanMealFirst => _t({
        'en': 'Scan a meal first to get personalised suggestions.',
        'pl': 'Najpierw zeskanuj posiłek, aby otrzymać spersonalizowane sugestie.',
        'nl': 'Scan eerst een maaltijd voor persoonlijke suggesties.',
        'es': 'Escanea una comida primero para recibir sugerencias personalizadas.',
        'de': 'Scanne zuerst eine Mahlzeit für personalisierte Vorschläge.',
      });

  String groceryAddItemsToList(int n) => _t({
        'en': n == 1 ? 'Add 1 item to list' : 'Add $n items to list',
        'pl': 'Dodaj do listy ($n)',
        'nl': n == 1 ? '1 item toevoegen' : '$n items toevoegen',
        'es': 'Añadir a la lista ($n)',
        'de': n == 1 ? '1 Artikel hinzufügen' : '$n Artikel hinzufügen',
      });

  String groceryPhotoScanComplete(int added, int updated, String found) => _t({
        'en': 'Photo scan complete: +$added new, $updated updated. Found: $found',
        'pl': 'Skan zdjęcia gotowy: +$added nowych, $updated zaktualizowanych. Znaleziono: $found',
        'nl': 'Fotoscan voltooid: +$added nieuw, $updated bijgewerkt. Gevonden: $found',
        'es': 'Escaneo de foto completo: +$added nuevos, $updated actualizados. Encontrado: $found',
        'de': 'Fotoscan abgeschlossen: +$added neu, $updated aktualisiert. Gefunden: $found',
      });

  String get noRecipesForSlot => _t({
        'en': 'No recipes match this slot. Try adjusting your goal or dietary filters.',
        'pl': 'Brak przepisów pasujących do tego miejsca. Zmień cel lub filtry dietetyczne.',
        'nl': 'Geen recepten voor dit vak. Pas je doel of dieetfilters aan.',
        'es': 'No hay recetas para este espacio. Ajusta tu objetivo o filtros dietéticos.',
        'de': 'Keine passenden Rezepte für diesen Slot. Passe dein Ziel oder deine Diätfilter an.',
      });

  // ── Barcode scanner (native UI) ──

  String get barcodePointCamera => _t({
        'en': 'Point camera at a food barcode',
        'pl': 'Skieruj aparat na kod kreskowy produktu',
        'nl': 'Richt de camera op een streepjescode',
        'es': 'Apunta la cámara a un código de barras',
        'de': 'Richte die Kamera auf einen Barcode',
      });

  String get barcodeErrorTitle => _t({
        'en': 'Error',
        'pl': 'Błąd',
        'nl': 'Fout',
        'es': 'Error',
        'de': 'Fehler',
      });

  String get barcodeNotFoundTitle => _t({
        'en': 'Product not found',
        'pl': 'Nie znaleziono produktu',
        'nl': 'Product niet gevonden',
        'es': 'Producto no encontrado',
        'de': 'Produkt nicht gefunden',
      });

  String get barcodeNotFoundBody => _t({
        'en': 'No nutrition data found for this barcode. Try a different product.',
        'pl': 'Nie znaleziono danych odżywczych dla tego kodu. Spróbuj innego produktu.',
        'nl': 'Geen voedingswaarden gevonden voor deze streepjescode. Probeer een ander product.',
        'es': 'No se encontraron datos nutricionales para este código. Prueba con otro producto.',
        'de': 'Keine Nährwertdaten für diesen Barcode gefunden. Versuche ein anderes Produkt.',
      });

  String get barcodeScanAgain => _t({
        'en': 'Scan again',
        'pl': 'Skanuj ponownie',
        'nl': 'Opnieuw scannen',
        'es': 'Escanear de nuevo',
        'de': 'Erneut scannen',
      });

  String get heightLabel => _t({
        'en': 'Height',
        'pl': 'Wzrost',
        'nl': 'Lengte',
        'es': 'Altura',
        'de': 'Größe',
      });

  String get deleteAccountConfirmBody => _t({
        'en': 'This will permanently delete your account and all synced data. Local data on this device will be kept.\n\nThis cannot be undone.',
        'pl': 'Spowoduje to trwałe usunięcie konta i wszystkich zsynchronizowanych danych. Dane lokalne na tym urządzeniu zostaną zachowane.\n\nTej operacji nie można cofnąć.',
        'nl': 'Hiermee worden je account en alle gesynchroniseerde gegevens permanent verwijderd. Lokale gegevens op dit apparaat blijven behouden.\n\nDit kan niet ongedaan worden gemaakt.',
        'es': 'Esto eliminará permanentemente tu cuenta y todos los datos sincronizados. Los datos locales de este dispositivo se conservarán.\n\nEsto no se puede deshacer.',
        'de': 'Dadurch werden dein Konto und alle synchronisierten Daten dauerhaft gelöscht. Lokale Daten auf diesem Gerät bleiben erhalten.\n\nDies kann nicht rückgängig gemacht werden.',
      });

  String get continueLabel => _t({
        'en': 'Continue',
        'pl': 'Kontynuuj',
        'nl': 'Doorgaan',
        'es': 'Continuar',
        'de': 'Weiter',
      });

  String get hideKeyboard => _t({
        'en': 'Hide keyboard',
        'pl': 'Ukryj klawiaturę',
        'nl': 'Toetsenbord verbergen',
        'es': 'Ocultar teclado',
        'de': 'Tastatur ausblenden',
      });

  String removeFoodConfirm(String label) => _t({
        'en': 'Remove "$label" from today\'s intake?',
        'pl': 'Usunąć „$label" z dzisiejszego spożycia?',
        'nl': '"$label" verwijderen uit de inname van vandaag?',
        'es': '¿Eliminar "$label" de la ingesta de hoy?',
        'de': '"$label" aus der heutigen Aufnahme entfernen?',
      });

  String get deleteScanTitle => _t({
        'en': 'Delete Scan',
        'pl': 'Usuń skan',
        'nl': 'Scan verwijderen',
        'es': 'Eliminar escaneo',
        'de': 'Scan löschen',
      });

  String get deleteScanHistoryConfirm => _t({
        'en': 'Delete this scan from history?',
        'pl': 'Usunąć ten skan z historii?',
        'nl': 'Deze scan uit de geschiedenis verwijderen?',
        'es': '¿Eliminar este escaneo del historial?',
        'de': 'Diesen Scan aus dem Verlauf löschen?',
      });

  String get noScansYet => _t({
        'en': 'No scans yet — tap Scan to start!',
        'pl': 'Brak skanów — dotknij Skanuj, aby rozpocząć!',
        'nl': 'Nog geen scans — tik op Scannen om te beginnen!',
        'es': 'Aún no hay escaneos: ¡toca Escanear para empezar!',
        'de': 'Noch keine Scans — tippe auf Scannen, um zu beginnen!',
      });

  String scanItemCount(int n) => _t({
        'en': '$n item${n == 1 ? '' : 's'}',
        'pl': n == 1 ? '$n element' : '$n elementów',
        'nl': '$n item${n == 1 ? '' : 's'}',
        'es': n == 1 ? '$n elemento' : '$n elementos',
        'de': n == 1 ? '$n Element' : '$n Elemente',
      });

  String get howManyPeople => _t({
        'en': 'How many people?',
        'pl': 'Dla ilu osób?',
        'nl': 'Voor hoeveel personen?',
        'es': '¿Para cuántas personas?',
        'de': 'Für wie viele Personen?',
      });

  String get peopleCountHelp => _t({
        'en': 'Set how many people each planned day cooks for. Grocery amounts are multiplied accordingly.',
        'pl': 'Ustaw, dla ilu osób gotujesz każdego zaplanowanego dnia. Ilości na liście zakupów zostaną odpowiednio przeliczone.',
        'nl': 'Stel in voor hoeveel personen je elke geplande dag kookt. De boodschappenhoeveelheden worden dienovereenkomstig vermenigvuldigd.',
        'es': 'Indica para cuántas personas cocinas cada día planificado. Las cantidades de la compra se multiplican en consecuencia.',
        'de': 'Lege fest, für wie viele Personen du an jedem geplanten Tag kochst. Die Einkaufsmengen werden entsprechend multipliziert.',
      });

  String get setAllDays => _t({
        'en': 'Set all days',
        'pl': 'Ustaw wszystkie dni',
        'nl': 'Alle dagen instellen',
        'es': 'Establecer todos los días',
        'de': 'Alle Tage festlegen',
      });

  String get generate => _t({
        'en': 'Generate',
        'pl': 'Generuj',
        'nl': 'Genereren',
        'es': 'Generar',
        'de': 'Generieren',
      });

  String get groceryListEmptied => _t({
        'en': 'Grocery list emptied',
        'pl': 'Lista zakupów opróżniona',
        'nl': 'Boodschappenlijst geleegd',
        'es': 'Lista de la compra vaciada',
        'de': 'Einkaufsliste geleert',
      });

  String get emptyGroceryList => _t({
        'en': 'Empty current grocery list',
        'pl': 'Opróżnij bieżącą listę zakupów',
        'nl': 'Huidige boodschappenlijst legen',
        'es': 'Vaciar la lista de la compra actual',
        'de': 'Aktuelle Einkaufsliste leeren',
      });

  String get skipSetLater => _t({
        'en': 'Skip — I\'ll set this later in Settings',
        'pl': 'Pomiń — ustawię to później w Ustawieniach',
        'nl': 'Overslaan — ik stel dit later in bij Instellingen',
        'es': 'Omitir: lo configuraré más tarde en Ajustes',
        'de': 'Überspringen — ich stelle das später in den Einstellungen ein',
      });

  // ── Diabetes / Bolus calculator: generic ──
  String get confirm => _t({
        'en': 'Confirm',
        'pl': 'Potwierdź',
        'nl': 'Bevestigen',
        'es': 'Confirmar',
        'de': 'Bestätigen',
      });

  String get goBack => _t({
        'en': 'Go back',
        'pl': 'Wróć',
        'nl': 'Terug',
        'es': 'Volver',
        'de': 'Zurück',
      });

  String get diabetesGeneralSection => _t({
        'en': 'General',
        'pl': 'Ogólne',
        'nl': 'Algemeen',
        'es': 'General',
        'de': 'Allgemein',
      });

  String diabetesTypeLabel(String key) {
    switch (key) {
      case 'type1':
        return _t({
          'en': 'Type 1',
          'pl': 'Typ 1',
          'nl': 'Type 1',
          'es': 'Tipo 1',
          'de': 'Typ 1',
        });
      case 'type2':
        return _t({
          'en': 'Type 2',
          'pl': 'Typ 2',
          'nl': 'Type 2',
          'es': 'Tipo 2',
          'de': 'Typ 2',
        });
      case 'gestational':
        return _t({
          'en': 'Gestational',
          'pl': 'Ciążowa',
          'nl': 'Zwangerschapsdiabetes',
          'es': 'Gestacional',
          'de': 'Schwangerschaftsdiabetes',
        });
      case 'other':
        return other;
      case 'preferNotToSay':
      default:
        return preferNotToSay;
    }
  }

  // ── Insulin settings survey ──
  String get insulinSettingsSurvey => _t({
        'en': 'Insulin Settings Survey',
        'pl': 'Ankieta ustawień insuliny',
        'nl': 'Vragenlijst insuline-instellingen',
        'es': 'Cuestionario de ajustes de insulina',
        'de': 'Fragebogen zu Insulineinstellungen',
      });

  String get diabetesTypeField => _t({
        'en': 'Diabetes type',
        'pl': 'Typ cukrzycy',
        'nl': 'Type diabetes',
        'es': 'Tipo de diabetes',
        'de': 'Diabetes-Typ',
      });

  String get usesCgm => _t({
        'en': 'I use a continuous glucose monitor (CGM)',
        'pl': 'Używam ciągłego monitora glukozy (CGM)',
        'nl': 'Ik gebruik een continue glucosemonitor (CGM)',
        'es': 'Uso un monitor continuo de glucosa (MCG)',
        'de': 'Ich nutze ein kontinuierliches Glukosemesssystem (CGM)',
      });

  String get calculatorComponents => _t({
        'en': 'Calculator components',
        'pl': 'Składniki kalkulatora',
        'nl': 'Rekenmachineonderdelen',
        'es': 'Componentes de la calculadora',
        'de': 'Rechner-Komponenten',
      });

  String get enableMealBolus => _t({
        'en': 'Enable meal bolus',
        'pl': 'Włącz bolus na posiłek',
        'nl': 'Maaltijdbolus inschakelen',
        'es': 'Activar bolo de comida',
        'de': 'Mahlzeitenbolus aktivieren',
      });

  String get enableMealBolusDesc => _t({
        'en': 'Covers the carbs in a meal using your carb ratios.',
        'pl': 'Pokrywa węglowodany w posiłku na podstawie Twoich przeliczników.',
        'nl': 'Dekt de koolhydraten in een maaltijd op basis van je ratio\'s.',
        'es': 'Cubre los carbohidratos de una comida usando tus ratios.',
        'de': 'Deckt die Kohlenhydrate einer Mahlzeit anhand deiner Faktoren ab.',
      });

  String get enableCorrectionDose => _t({
        'en': 'Enable correction dose',
        'pl': 'Włącz dawkę korekcyjną',
        'nl': 'Correctiedosis inschakelen',
        'es': 'Activar dosis de corrección',
        'de': 'Korrekturdosis aktivieren',
      });

  String get subtractIob => _t({
        'en': 'Subtract insulin-on-board (IOB)',
        'pl': 'Odejmij insulinę aktywną (IOB)',
        'nl': 'Insuline-on-board (IOB) aftrekken',
        'es': 'Restar insulina activa (IOB)',
        'de': 'Insulin-on-Board (IOB) abziehen',
      });

  String get subtractIobSurveyDesc => _t({
        'en': 'Uses your logged insulin doses and action duration.',
        'pl': 'Korzysta z zapisanych dawek insuliny i czasu działania.',
        'nl': 'Gebruikt je geregistreerde insulinedoses en werkingsduur.',
        'es': 'Usa tus dosis de insulina registradas y la duración de acción.',
        'de': 'Verwendet deine erfassten Insulindosen und die Wirkdauer.',
      });

  String get subtractIobCardDesc => _t({
        'en': 'Uses confirmed recent doses you logged.',
        'pl': 'Korzysta z potwierdzonych, niedawno zapisanych dawek.',
        'nl': 'Gebruikt bevestigde recente doses die je hebt geregistreerd.',
        'es': 'Usa las dosis recientes confirmadas que registraste.',
        'de': 'Verwendet bestätigte kürzlich erfasste Dosen.',
      });

  String glucoseTargetsSection(String unit) => _t({
        'en': 'Glucose targets ($unit)',
        'pl': 'Cele glikemii ($unit)',
        'nl': 'Glucosestreefwaarden ($unit)',
        'es': 'Objetivos de glucosa ($unit)',
        'de': 'Glukoseziele ($unit)',
      });

  String get targetGlucoseField => _t({
        'en': 'Target glucose',
        'pl': 'Docelowa glikemia',
        'nl': 'Streefglucose',
        'es': 'Glucosa objetivo',
        'de': 'Zielglukose',
      });

  String get lowHypoThreshold => _t({
        'en': 'Low (hypo) threshold',
        'pl': 'Próg niski (hipoglikemia)',
        'nl': 'Lage (hypo) drempel',
        'es': 'Umbral bajo (hipo)',
        'de': 'Niedrigschwelle (Hypo)',
      });

  String get highHyperThreshold => _t({
        'en': 'High (hyper) threshold — optional',
        'pl': 'Próg wysoki (hiperglikemia) — opcjonalnie',
        'nl': 'Hoge (hyper) drempel — optioneel',
        'es': 'Umbral alto (hiper): opcional',
        'de': 'Hochschwelle (Hyper) — optional',
      });

  String get icrSection => _t({
        'en': 'Insulin-to-carb ratios (g carb per unit)',
        'pl': 'Przeliczniki insulina-węglowodany (g węgl. na jednostkę)',
        'nl': 'Insuline-koolhydraatratio\'s (g koolhydraat per eenheid)',
        'es': 'Ratios insulina-carbohidratos (g de carbohidrato por unidad)',
        'de': 'Insulin-Kohlenhydrat-Faktoren (g KH pro Einheit)',
      });

  String isfSection(String unit) => _t({
        'en': 'Correction factors / ISF ($unit per unit)',
        'pl': 'Współczynniki korekcyjne / ISF ($unit na jednostkę)',
        'nl': 'Correctiefactoren / ISF ($unit per eenheid)',
        'es': 'Factores de corrección / ISF ($unit por unidad)',
        'de': 'Korrekturfaktoren / ISF ($unit pro Einheit)',
      });

  String get insulinActionLimits => _t({
        'en': 'Insulin action & limits',
        'pl': 'Działanie insuliny i limity',
        'nl': 'Insulinewerking en limieten',
        'es': 'Acción de la insulina y límites',
        'de': 'Insulinwirkung & Grenzwerte',
      });

  String get insulinActionDurationHours => _t({
        'en': 'Insulin action duration (hours)',
        'pl': 'Czas działania insuliny (godziny)',
        'nl': 'Werkingsduur insuline (uren)',
        'es': 'Duración de acción de la insulina (horas)',
        'de': 'Insulinwirkdauer (Stunden)',
      });

  String get maxSingleBolusUnitsField => _t({
        'en': 'Maximum single bolus (units)',
        'pl': 'Maksymalny pojedynczy bolus (jednostki)',
        'nl': 'Maximale enkele bolus (eenheden)',
        'es': 'Bolo único máximo (unidades)',
        'de': 'Maximaler Einzelbolus (Einheiten)',
      });

  String get validateAndSaveSettings => _t({
        'en': 'Validate & save settings',
        'pl': 'Sprawdź i zapisz ustawienia',
        'nl': 'Instellingen valideren en opslaan',
        'es': 'Validar y guardar ajustes',
        'de': 'Einstellungen prüfen & speichern',
      });

  String get pleaseFixSettings => _t({
        'en': 'Please fix your settings',
        'pl': 'Popraw swoje ustawienia',
        'nl': 'Corrigeer je instellingen',
        'es': 'Corrige tus ajustes',
        'de': 'Bitte korrigiere deine Einstellungen',
      });

  String get pleaseConfirmTitle => _t({
        'en': 'Please confirm',
        'pl': 'Potwierdź',
        'nl': 'Bevestig',
        'es': 'Confirma',
        'de': 'Bitte bestätigen',
      });

  String get bolusCalculatorEnabledMsg => _t({
        'en': 'Bolus Calculator Mode enabled.',
        'pl': 'Tryb kalkulatora bolusa włączony.',
        'nl': 'Bolusrekenmodus ingeschakeld.',
        'es': 'Modo calculadora de bolo activado.',
        'de': 'Bolusrechner-Modus aktiviert.',
      });

  String get bloodGlucoseUnitColon => _t({
        'en': 'Blood glucose unit:',
        'pl': 'Jednostka glikemii:',
        'nl': 'Bloedglucose-eenheid:',
        'es': 'Unidad de glucosa:',
        'de': 'Blutzuckereinheit:',
      });

  String get roundingIncrement => _t({
        'en': 'Rounding increment:',
        'pl': 'Krok zaokrąglania:',
        'nl': 'Afrondingsstap:',
        'es': 'Incremento de redondeo:',
        'de': 'Rundungsschritt:',
      });

  String get windowOvernight => _t({
        'en': 'Overnight (00:00–10:59)',
        'pl': 'Noc (00:00–10:59)',
        'nl': '\'s Nachts (00:00–10:59)',
        'es': 'Noche (00:00–10:59)',
        'de': 'Nachts (00:00–10:59)',
      });

  String get windowDaytime => _t({
        'en': 'Daytime (11:00–16:59)',
        'pl': 'Dzień (11:00–16:59)',
        'nl': 'Overdag (11:00–16:59)',
        'es': 'Día (11:00–16:59)',
        'de': 'Tagsüber (11:00–16:59)',
      });

  String get windowEvening => _t({
        'en': 'Evening (17:00–23:59)',
        'pl': 'Wieczór (17:00–23:59)',
        'nl': 'Avond (17:00–23:59)',
        'es': 'Tarde (17:00–23:59)',
        'de': 'Abend (17:00–23:59)',
      });

  String pleaseProvide(String items) => _t({
        'en': 'Please provide: $items.',
        'pl': 'Podaj: $items.',
        'nl': 'Geef op: $items.',
        'es': 'Indica: $items.',
        'de': 'Bitte angeben: $items.',
      });

  String get missingAtLeastOneIcr => _t({
        'en': 'at least one ICR',
        'pl': 'co najmniej jeden przelicznik ICR',
        'nl': 'ten minste één ICR',
        'es': 'al menos un ICR',
        'de': 'mindestens ein ICR',
      });

  String get missingComponent => _t({
        'en': 'at least one calculator component (meal bolus or correction)',
        'pl': 'co najmniej jeden składnik kalkulatora (bolus na posiłek lub korekcja)',
        'nl': 'ten minste één rekenonderdeel (maaltijdbolus of correctie)',
        'es': 'al menos un componente de la calculadora (bolo de comida o corrección)',
        'de': 'mindestens eine Rechner-Komponente (Mahlzeitenbolus oder Korrektur)',
      });

  String get missingMaxBolus => _t({
        'en': 'maximum bolus',
        'pl': 'maksymalny bolus',
        'nl': 'maximale bolus',
        'es': 'bolo máximo',
        'de': 'maximaler Bolus',
      });

  String get missingTargetGlucose => _t({
        'en': 'target glucose',
        'pl': 'docelowa glikemia',
        'nl': 'streefglucose',
        'es': 'glucosa objetivo',
        'de': 'Zielglukose',
      });

  String get missingCorrectionFactor => _t({
        'en': 'at least one correction factor',
        'pl': 'co najmniej jeden współczynnik korekcyjny',
        'nl': 'ten minste één correctiefactor',
        'es': 'al menos un factor de corrección',
        'de': 'mindestens ein Korrekturfaktor',
      });

  String get missingActionDuration => _t({
        'en': 'insulin action duration',
        'pl': 'czas działania insuliny',
        'nl': 'werkingsduur insuline',
        'es': 'duración de acción de la insulina',
        'de': 'Insulinwirkdauer',
      });

  // ── Diabetes review screen ──
  String get insulinSettingsReview => _t({
        'en': 'Insulin Settings Review',
        'pl': 'Przegląd ustawień insuliny',
        'nl': 'Controle insuline-instellingen',
        'es': 'Revisión de ajustes de insulina',
        'de': 'Überprüfung der Insulineinstellungen',
      });

  String get lastReviewed => _t({
        'en': 'Last reviewed',
        'pl': 'Ostatni przegląd',
        'nl': 'Laatst gecontroleerd',
        'es': 'Última revisión',
        'de': 'Zuletzt überprüft',
      });

  String get nextReviewDue => _t({
        'en': 'Next review due',
        'pl': 'Następny przegląd',
        'nl': 'Volgende controle',
        'es': 'Próxima revisión',
        'de': 'Nächste Überprüfung fällig',
      });

  String get reminderSnoozedUntil => _t({
        'en': 'Reminder snoozed until',
        'pl': 'Przypomnienie odłożone do',
        'nl': 'Herinnering uitgesteld tot',
        'es': 'Recordatorio pospuesto hasta',
        'de': 'Erinnerung verschoben bis',
      });

  String get confirmSettingsCorrect => _t({
        'en': 'Confirm my settings are still correct',
        'pl': 'Potwierdź, że moje ustawienia są nadal poprawne',
        'nl': 'Bevestig dat mijn instellingen nog kloppen',
        'es': 'Confirmar que mis ajustes siguen siendo correctos',
        'de': 'Bestätigen, dass meine Einstellungen noch korrekt sind',
      });

  String get updateInsulinSettings => _t({
        'en': 'Update my insulin settings',
        'pl': 'Zaktualizuj moje ustawienia insuliny',
        'nl': 'Mijn insuline-instellingen bijwerken',
        'es': 'Actualizar mis ajustes de insulina',
        'de': 'Meine Insulineinstellungen aktualisieren',
      });

  String reviewKeepsSafe(int days) => _t({
        'en': 'Reviewing your settings regularly keeps the calculator safe. Confirming marks them current for the next $days days.',
        'pl': 'Regularny przegląd ustawień utrzymuje bezpieczeństwo kalkulatora. Potwierdzenie oznacza je jako aktualne na kolejne $days dni.',
        'nl': 'Door je instellingen regelmatig te controleren blijft de rekenmodule veilig. Bevestigen markeert ze als actueel voor de komende $days dagen.',
        'es': 'Revisar tus ajustes con regularidad mantiene la calculadora segura. Confirmar los marca como vigentes durante los próximos $days días.',
        'de': 'Regelmäßiges Überprüfen deiner Einstellungen hält den Rechner sicher. Mit dem Bestätigen gelten sie für die nächsten $days Tage als aktuell.',
      });

  String get reviewStatusCurrent => _t({
        'en': 'Current',
        'pl': 'Aktualne',
        'nl': 'Actueel',
        'es': 'Vigente',
        'de': 'Aktuell',
      });

  String get reviewStatusCurrentDetail => _t({
        'en': 'Your settings are reviewed and the calculator is available.',
        'pl': 'Twoje ustawienia są sprawdzone, a kalkulator jest dostępny.',
        'nl': 'Je instellingen zijn gecontroleerd en de rekenmodule is beschikbaar.',
        'es': 'Tus ajustes están revisados y la calculadora está disponible.',
        'de': 'Deine Einstellungen sind überprüft und der Rechner ist verfügbar.',
      });

  String get reviewStatusSnoozed => _t({
        'en': 'Review due (reminder snoozed)',
        'pl': 'Przegląd wymagany (przypomnienie odłożone)',
        'nl': 'Controle nodig (herinnering uitgesteld)',
        'es': 'Revisión pendiente (recordatorio pospuesto)',
        'de': 'Überprüfung fällig (Erinnerung verschoben)',
      });

  String get reviewStatusSnoozedDetail => _t({
        'en': 'A review is due. The reminder is snoozed, but the calculator stays disabled until you review.',
        'pl': 'Przegląd jest wymagany. Przypomnienie jest odłożone, ale kalkulator pozostaje wyłączony do czasu przeglądu.',
        'nl': 'Een controle is nodig. De herinnering is uitgesteld, maar de rekenmodule blijft uitgeschakeld tot je controleert.',
        'es': 'Hay una revisión pendiente. El recordatorio está pospuesto, pero la calculadora permanece desactivada hasta que la revises.',
        'de': 'Eine Überprüfung ist fällig. Die Erinnerung ist verschoben, aber der Rechner bleibt deaktiviert, bis du überprüfst.',
      });

  String get reviewStatusOverdue => _t({
        'en': 'Overdue',
        'pl': 'Zaległe',
        'nl': 'Te laat',
        'es': 'Vencida',
        'de': 'Überfällig',
      });

  String get reviewStatusOverdueDetail => _t({
        'en': 'Your settings review is overdue. Bolus calculations are disabled until you review and confirm.',
        'pl': 'Przegląd ustawień jest zaległy. Obliczenia bolusa są wyłączone do czasu przeglądu i potwierdzenia.',
        'nl': 'Je instellingencontrole is te laat. Bolusberekeningen zijn uitgeschakeld tot je controleert en bevestigt.',
        'es': 'La revisión de tus ajustes está vencida. Los cálculos de bolo están desactivados hasta que revises y confirmes.',
        'de': 'Die Überprüfung deiner Einstellungen ist überfällig. Bolusberechnungen sind deaktiviert, bis du überprüfst und bestätigst.',
      });

  String get reviewStatusNotCompleted => _t({
        'en': 'Not completed',
        'pl': 'Nieukończone',
        'nl': 'Niet voltooid',
        'es': 'No completada',
        'de': 'Nicht abgeschlossen',
      });

  String get reviewStatusNotCompletedDetail => _t({
        'en': 'Complete the insulin settings survey to use the calculator.',
        'pl': 'Wypełnij ankietę ustawień insuliny, aby korzystać z kalkulatora.',
        'nl': 'Vul de vragenlijst voor insuline-instellingen in om de rekenmodule te gebruiken.',
        'es': 'Completa el cuestionario de ajustes de insulina para usar la calculadora.',
        'de': 'Fülle den Fragebogen zu Insulineinstellungen aus, um den Rechner zu nutzen.',
      });

  String reviewStatusLabel(String label) => _t({
        'en': 'Status: $label',
        'pl': 'Status: $label',
        'nl': 'Status: $label',
        'es': 'Estado: $label',
        'de': 'Status: $label',
      });

  String get insulinReviewNeeded => _t({
        'en': 'Insulin settings review needed',
        'pl': 'Wymagany przegląd ustawień insuliny',
        'nl': 'Controle insuline-instellingen nodig',
        'es': 'Se necesita revisar los ajustes de insulina',
        'de': 'Überprüfung der Insulineinstellungen erforderlich',
      });

  String get bolusDisabledUntilReview => _t({
        'en': 'For safety, the bolus calculator is disabled until you review and confirm your insulin settings.',
        'pl': 'Ze względów bezpieczeństwa kalkulator bolusa jest wyłączony do czasu przeglądu i potwierdzenia ustawień insuliny.',
        'nl': 'Voor de veiligheid is de bolusrekenmodule uitgeschakeld tot je je insuline-instellingen controleert en bevestigt.',
        'es': 'Por seguridad, la calculadora de bolo está desactivada hasta que revises y confirmes tus ajustes de insulina.',
        'de': 'Aus Sicherheitsgründen ist der Bolusrechner deaktiviert, bis du deine Insulineinstellungen überprüfst und bestätigst.',
      });

  String get reviewNow => _t({
        'en': 'Review now',
        'pl': 'Przejrzyj teraz',
        'nl': 'Nu controleren',
        'es': 'Revisar ahora',
        'de': 'Jetzt überprüfen',
      });

  String get remindTomorrow => _t({
        'en': 'Remind me tomorrow',
        'pl': 'Przypomnij jutro',
        'nl': 'Herinner me morgen',
        'es': 'Recordármelo mañana',
        'de': 'Morgen erinnern',
      });

  String get inTwoDays => _t({
        'en': 'In 2 days',
        'pl': 'Za 2 dni',
        'nl': 'Over 2 dagen',
        'es': 'En 2 días',
        'de': 'In 2 Tagen',
      });

  String get inOneWeek => _t({
        'en': 'In 1 week',
        'pl': 'Za tydzień',
        'nl': 'Over 1 week',
        'es': 'En 1 semana',
        'de': 'In 1 Woche',
      });

  // ── Bolus setup screen ──
  String get iUseInsulin => _t({
        'en': 'I use insulin',
        'pl': 'Używam insuliny',
        'nl': 'Ik gebruik insuline',
        'es': 'Uso insulina',
        'de': 'Ich verwende Insulin',
      });

  String get iUseInsulinDesc => _t({
        'en': 'Required before the bolus calculator can be offered.',
        'pl': 'Wymagane, zanim kalkulator bolusa stanie się dostępny.',
        'nl': 'Vereist voordat de bolusrekenmodule kan worden aangeboden.',
        'es': 'Necesario antes de poder ofrecer la calculadora de bolo.',
        'de': 'Erforderlich, bevor der Bolusrechner angeboten werden kann.',
      });

  String get beforeYouEnable => _t({
        'en': 'Before you enable',
        'pl': 'Zanim włączysz',
        'nl': 'Voordat je inschakelt',
        'es': 'Antes de activar',
        'de': 'Bevor du aktivierst',
      });

  String get continueToSurvey => _t({
        'en': 'Continue to insulin settings survey',
        'pl': 'Przejdź do ankiety ustawień insuliny',
        'nl': 'Doorgaan naar vragenlijst insuline-instellingen',
        'es': 'Continuar al cuestionario de ajustes de insulina',
        'de': 'Weiter zum Fragebogen zu Insulineinstellungen',
      });

  String get disableBolusCalculatorMode => _t({
        'en': 'Disable Bolus Calculator Mode',
        'pl': 'Wyłącz tryb kalkulatora bolusa',
        'nl': 'Bolusrekenmodus uitschakelen',
        'es': 'Desactivar modo calculadora de bolo',
        'de': 'Bolusrechner-Modus deaktivieren',
      });

  String get highRiskFeature => _t({
        'en': 'High-risk feature. This calculator can suggest insulin doses from your settings. A wrong dose can be dangerous. It is not a medical device and does not replace your care plan.',
        'pl': 'Funkcja wysokiego ryzyka. Ten kalkulator może sugerować dawki insuliny na podstawie Twoich ustawień. Błędna dawka może być niebezpieczna. To nie jest wyrób medyczny i nie zastępuje Twojego planu leczenia.',
        'nl': 'Functie met hoog risico. Deze rekenmodule kan insulinedoses voorstellen op basis van je instellingen. Een verkeerde dosis kan gevaarlijk zijn. Het is geen medisch hulpmiddel en vervangt je zorgplan niet.',
        'es': 'Función de alto riesgo. Esta calculadora puede sugerir dosis de insulina a partir de tus ajustes. Una dosis incorrecta puede ser peligrosa. No es un dispositivo médico y no sustituye tu plan de tratamiento.',
        'de': 'Hochrisiko-Funktion. Dieser Rechner kann anhand deiner Einstellungen Insulindosen vorschlagen. Eine falsche Dosis kann gefährlich sein. Es ist kein Medizinprodukt und ersetzt nicht deinen Behandlungsplan.',
      });

  // ── Bolus calculator card ──
  String get bolusEstimate => _t({
        'en': 'Bolus estimate',
        'pl': 'Szacowany bolus',
        'nl': 'Bolusschatting',
        'es': 'Estimación de bolo',
        'de': 'Bolusschätzung',
      });

  String get mealCarbohydratesG => _t({
        'en': 'Meal carbohydrates (g)',
        'pl': 'Węglowodany posiłku (g)',
        'nl': 'Koolhydraten maaltijd (g)',
        'es': 'Carbohidratos de la comida (g)',
        'de': 'Kohlenhydrate der Mahlzeit (g)',
      });

  String get addCorrectionForGlucose => _t({
        'en': 'Add correction for current glucose',
        'pl': 'Dodaj korekcję dla aktualnej glikemii',
        'nl': 'Correctie voor huidige glucose toevoegen',
        'es': 'Añadir corrección para la glucosa actual',
        'de': 'Korrektur für aktuelle Glukose hinzufügen',
      });

  String currentGlucoseUnit(String unit) => _t({
        'en': 'Current glucose ($unit)',
        'pl': 'Aktualna glikemia ($unit)',
        'nl': 'Huidige glucose ($unit)',
        'es': 'Glucosa actual ($unit)',
        'de': 'Aktuelle Glukose ($unit)',
      });

  String get setTime => _t({
        'en': 'Set time',
        'pl': 'Ustaw czas',
        'nl': 'Tijd instellen',
        'es': 'Ajustar hora',
        'de': 'Zeit einstellen',
      });

  String nowTime(String time) => _t({
        'en': 'Now ($time)',
        'pl': 'Teraz ($time)',
        'nl': 'Nu ($time)',
        'es': 'Ahora ($time)',
        'de': 'Jetzt ($time)',
      });

  String get calculateEstimate => _t({
        'en': 'Calculate estimate',
        'pl': 'Oblicz szacunek',
        'nl': 'Schatting berekenen',
        'es': 'Calcular estimación',
        'de': 'Schätzung berechnen',
      });

  String get bolusUnavailableUntilReview => _t({
        'en': 'Bolus estimate is unavailable until you review and confirm your insulin settings.',
        'pl': 'Szacowany bolus jest niedostępny do czasu przeglądu i potwierdzenia ustawień insuliny.',
        'nl': 'Bolusschatting is niet beschikbaar tot je je insuline-instellingen controleert en bevestigt.',
        'es': 'La estimación de bolo no está disponible hasta que revises y confirmes tus ajustes de insulina.',
        'de': 'Die Bolusschätzung ist nicht verfügbar, bis du deine Insulineinstellungen überprüfst und bestätigst.',
      });

  String get estimatedBolusLabel => _t({
        'en': 'Estimated bolus based on your saved settings:',
        'pl': 'Szacowany bolus na podstawie zapisanych ustawień:',
        'nl': 'Geschatte bolus op basis van je opgeslagen instellingen:',
        'es': 'Bolo estimado según tus ajustes guardados:',
        'de': 'Geschätzter Bolus basierend auf deinen gespeicherten Einstellungen:',
      });

  String bolusUnitsValue(String value) => _t({
        'en': '$value units',
        'pl': '$value jednostek',
        'nl': '$value eenheden',
        'es': '$value unidades',
        'de': '$value Einheiten',
      });

  String get responsibleForDose => _t({
        'en': 'You are responsible for confirming this dose.',
        'pl': 'Odpowiadasz za potwierdzenie tej dawki.',
        'nl': 'Jij bent verantwoordelijk voor het bevestigen van deze dosis.',
        'es': 'Eres responsable de confirmar esta dosis.',
        'de': 'Du bist für die Bestätigung dieser Dosis verantwortlich.',
      });

  String get logDoseITook => _t({
        'en': 'Log the dose I actually took',
        'pl': 'Zapisz dawkę, którą faktycznie przyjąłem/przyjęłam',
        'nl': 'Registreer de dosis die ik echt heb genomen',
        'es': 'Registrar la dosis que realmente tomé',
        'de': 'Tatsächlich genommene Dosis protokollieren',
      });

  String get howThisCalculated => _t({
        'en': 'How this was calculated',
        'pl': 'Jak to obliczono',
        'nl': 'Hoe dit is berekend',
        'es': 'Cómo se calculó esto',
        'de': 'So wurde dies berechnet',
      });

  String get noEstimateShown => _t({
        'en': 'No estimate shown',
        'pl': 'Nie pokazano szacunku',
        'nl': 'Geen schatting getoond',
        'es': 'No se muestra estimación',
        'de': 'Keine Schätzung angezeigt',
      });

  // breakdown table labels
  String get bdMealCarbs => _t({
        'en': 'Meal carbs',
        'pl': 'Węglowodany posiłku',
        'nl': 'Maaltijdkoolhydraten',
        'es': 'Carbohidratos de la comida',
        'de': 'Mahlzeit-Kohlenhydrate',
      });

  String get bdIcrUsed => _t({
        'en': 'Insulin-to-carb ratio used',
        'pl': 'Użyty przelicznik insulina-węglowodany',
        'nl': 'Gebruikte insuline-koolhydraatratio',
        'es': 'Ratio insulina-carbohidratos usado',
        'de': 'Verwendeter Insulin-KH-Faktor',
      });

  String get bdMealComponent => _t({
        'en': 'Meal component',
        'pl': 'Składnik posiłkowy',
        'nl': 'Maaltijdcomponent',
        'es': 'Componente de comida',
        'de': 'Mahlzeitenanteil',
      });

  String get bdCurrentGlucose => _t({
        'en': 'Current glucose',
        'pl': 'Aktualna glikemia',
        'nl': 'Huidige glucose',
        'es': 'Glucosa actual',
        'de': 'Aktuelle Glukose',
      });

  String get bdTargetGlucose => _t({
        'en': 'Target glucose',
        'pl': 'Docelowa glikemia',
        'nl': 'Streefglucose',
        'es': 'Glucosa objetivo',
        'de': 'Zielglukose',
      });

  String get bdCorrectionFactorUsed => _t({
        'en': 'Correction factor used',
        'pl': 'Użyty współczynnik korekcyjny',
        'nl': 'Gebruikte correctiefactor',
        'es': 'Factor de corrección usado',
        'de': 'Verwendeter Korrekturfaktor',
      });

  String get bdCorrectionComponent => _t({
        'en': 'Correction component',
        'pl': 'Składnik korekcyjny',
        'nl': 'Correctiecomponent',
        'es': 'Componente de corrección',
        'de': 'Korrekturanteil',
      });

  String get bdIobSubtracted => _t({
        'en': 'Insulin-on-board subtracted',
        'pl': 'Odjęta insulina aktywna',
        'nl': 'Insuline-on-board afgetrokken',
        'es': 'Insulina activa restada',
        'de': 'Abgezogenes Insulin-on-Board',
      });

  String get bdRawTotal => _t({
        'en': 'Raw total',
        'pl': 'Suma surowa',
        'nl': 'Ruw totaal',
        'es': 'Total bruto',
        'de': 'Rohsumme',
      });

  String bdRoundedTo(String inc) => _t({
        'en': 'Rounded (to $inc u)',
        'pl': 'Zaokrąglone (do $inc j.)',
        'nl': 'Afgerond (op $inc e.)',
        'es': 'Redondeado (a $inc u)',
        'de': 'Gerundet (auf $inc E.)',
      });

  String get bdMaxSingleBolus => _t({
        'en': 'Max single bolus',
        'pl': 'Maks. pojedynczy bolus',
        'nl': 'Max. enkele bolus',
        'es': 'Bolo único máx.',
        'de': 'Max. Einzelbolus',
      });

  String get bdTimeBlock => _t({
        'en': 'Time block',
        'pl': 'Blok czasowy',
        'nl': 'Tijdblok',
        'es': 'Bloque horario',
        'de': 'Zeitblock',
      });

  String get logInsulinDose => _t({
        'en': 'Log insulin dose',
        'pl': 'Zapisz dawkę insuliny',
        'nl': 'Insulinedosis registreren',
        'es': 'Registrar dosis de insulina',
        'de': 'Insulindosis protokollieren',
      });

  String get enterDoseDesc => _t({
        'en': 'Enter the dose you actually took. This is used for insulin-on-board calculations and your records.',
        'pl': 'Wpisz dawkę, którą faktycznie przyjąłeś/aś. Służy do obliczeń insuliny aktywnej i Twoich zapisów.',
        'nl': 'Voer de dosis in die je echt hebt genomen. Dit wordt gebruikt voor IOB-berekeningen en je registratie.',
        'es': 'Introduce la dosis que realmente tomaste. Se usa para los cálculos de insulina activa y tu historial.',
        'de': 'Gib die tatsächlich genommene Dosis ein. Sie wird für IOB-Berechnungen und deine Aufzeichnungen verwendet.',
      });

  String get unitsTaken => _t({
        'en': 'Units taken',
        'pl': 'Przyjęte jednostki',
        'nl': 'Genomen eenheden',
        'es': 'Unidades tomadas',
        'de': 'Genommene Einheiten',
      });

  String get notesOptional => _t({
        'en': 'Notes (optional)',
        'pl': 'Notatki (opcjonalnie)',
        'nl': 'Notities (optioneel)',
        'es': 'Notas (opcional)',
        'de': 'Notizen (optional)',
      });

  String get iConfirmTookDose => _t({
        'en': 'I confirm I took this dose',
        'pl': 'Potwierdzam, że przyjąłem/przyjęłam tę dawkę',
        'nl': 'Ik bevestig dat ik deze dosis heb genomen',
        'es': 'Confirmo que tomé esta dosis',
        'de': 'Ich bestätige, dass ich diese Dosis genommen habe',
      });

  String get saveDose => _t({
        'en': 'Save dose',
        'pl': 'Zapisz dawkę',
        'nl': 'Dosis opslaan',
        'es': 'Guardar dosis',
        'de': 'Dosis speichern',
      });

  String get enterValidUnits => _t({
        'en': 'Enter a valid number of units.',
        'pl': 'Wpisz prawidłową liczbę jednostek.',
        'nl': 'Voer een geldig aantal eenheden in.',
        'es': 'Introduce un número de unidades válido.',
        'de': 'Gib eine gültige Anzahl an Einheiten ein.',
      });

  String get doseLogged => _t({
        'en': 'Dose logged.',
        'pl': 'Dawka zapisana.',
        'nl': 'Dosis geregistreerd.',
        'es': 'Dosis registrada.',
        'de': 'Dosis protokolliert.',
      });

  // ── Diabetes safety copy ──
  String get diabetesGeneralDisclaimer => _t({
        'en': 'This insulin estimate is calculated from settings you entered. It is not a substitute for medical advice. Incorrect settings, carb counts, glucose readings, or insulin history can cause dangerous low or high glucose. Always follow your diabetes care plan.',
        'pl': 'Ten szacunek insuliny jest obliczany na podstawie wprowadzonych ustawień. Nie zastępuje porady lekarskiej. Błędne ustawienia, liczby węglowodanów, odczyty glikemii lub historia insuliny mogą powodować niebezpieczną hipo- lub hiperglikemię. Zawsze przestrzegaj swojego planu leczenia cukrzycy.',
        'nl': 'Deze insulineschatting is berekend op basis van de instellingen die je hebt ingevoerd. Het is geen vervanging voor medisch advies. Onjuiste instellingen, koolhydraattellingen, glucosewaarden of insulinegeschiedenis kunnen gevaarlijke lage of hoge glucose veroorzaken. Volg altijd je diabeteszorgplan.',
        'es': 'Esta estimación de insulina se calcula a partir de los ajustes que introdujiste. No sustituye el consejo médico. Unos ajustes, recuentos de carbohidratos, lecturas de glucosa o historial de insulina incorrectos pueden provocar una glucosa peligrosamente baja o alta. Sigue siempre tu plan de tratamiento de la diabetes.',
        'de': 'Diese Insulinschätzung wird aus den von dir eingegebenen Einstellungen berechnet. Sie ersetzt keine ärztliche Beratung. Falsche Einstellungen, Kohlenhydratangaben, Glukosewerte oder Insulinverläufe können gefährlich niedrige oder hohe Glukosewerte verursachen. Befolge stets deinen Diabetes-Behandlungsplan.',
      });

  String get diabetesBeforeEnabling => _t({
        'en': 'Only use this feature if your insulin-to-carb ratio, correction factor, target glucose, and insulin action duration were provided by your clinician, diabetes educator, pump, or official care plan.',
        'pl': 'Korzystaj z tej funkcji tylko wtedy, gdy Twój przelicznik insulina-węglowodany, współczynnik korekcyjny, docelowa glikemia i czas działania insuliny zostały podane przez lekarza, edukatora diabetologicznego, pompę lub oficjalny plan leczenia.',
        'nl': 'Gebruik deze functie alleen als je insuline-koolhydraatratio, correctiefactor, streefglucose en werkingsduur van insuline zijn opgegeven door je arts, diabetesverpleegkundige, pomp of officieel zorgplan.',
        'es': 'Usa esta función solo si tu ratio insulina-carbohidratos, factor de corrección, glucosa objetivo y duración de acción de la insulina fueron proporcionados por tu médico, educador en diabetes, bomba o plan de tratamiento oficial.',
        'de': 'Nutze diese Funktion nur, wenn dein Insulin-KH-Faktor, Korrekturfaktor, Zielglukose und Insulinwirkdauer von deinem Arzt, Diabetesberater, deiner Pumpe oder einem offiziellen Behandlungsplan stammen.',
      });

  String get diabetesRegulatoryNotice => _t({
        'en': 'Depending on where you live, an insulin calculator may be regulated as medical-device software. This feature is provided for informational support only and has not been cleared or certified as a medical device.',
        'pl': 'W zależności od miejsca zamieszkania kalkulator insuliny może być regulowany jako oprogramowanie wyrobu medycznego. Ta funkcja służy wyłącznie celom informacyjnym i nie została dopuszczona ani certyfikowana jako wyrób medyczny.',
        'nl': 'Afhankelijk van waar je woont, kan een insulinerekenmachine gereguleerd zijn als software voor medische hulpmiddelen. Deze functie is alleen bedoeld als informatieve ondersteuning en is niet goedgekeurd of gecertificeerd als medisch hulpmiddel.',
        'es': 'Según dónde vivas, una calculadora de insulina puede estar regulada como software de dispositivo médico. Esta función se ofrece solo como apoyo informativo y no ha sido autorizada ni certificada como dispositivo médico.',
        'de': 'Je nach Wohnort kann ein Insulinrechner als Medizinprodukte-Software reguliert sein. Diese Funktion dient nur zur informativen Unterstützung und ist nicht als Medizinprodukt zugelassen oder zertifiziert.',
      });

  String get diabetesSettingsSourceConfirmation => _t({
        'en': 'I understand this app does not replace medical advice. I confirm that the insulin settings I entered are from my clinician, insulin pump, diabetes educator, or official diabetes care plan. I understand incorrect settings can cause dangerous low or high blood glucose.',
        'pl': 'Rozumiem, że ta aplikacja nie zastępuje porady lekarskiej. Potwierdzam, że wprowadzone ustawienia insuliny pochodzą od mojego lekarza, pompy insulinowej, edukatora diabetologicznego lub oficjalnego planu leczenia cukrzycy. Rozumiem, że błędne ustawienia mogą powodować niebezpieczną hipo- lub hiperglikemię.',
        'nl': 'Ik begrijp dat deze app geen vervanging is voor medisch advies. Ik bevestig dat de insuline-instellingen die ik heb ingevoerd afkomstig zijn van mijn arts, insulinepomp, diabetesverpleegkundige of officieel diabeteszorgplan. Ik begrijp dat onjuiste instellingen gevaarlijk lage of hoge bloedglucose kunnen veroorzaken.',
        'es': 'Entiendo que esta app no sustituye el consejo médico. Confirmo que los ajustes de insulina que introduje provienen de mi médico, bomba de insulina, educador en diabetes o plan de tratamiento oficial. Entiendo que unos ajustes incorrectos pueden provocar una glucosa peligrosamente baja o alta.',
        'de': 'Mir ist bewusst, dass diese App keine ärztliche Beratung ersetzt. Ich bestätige, dass die von mir eingegebenen Insulineinstellungen von meinem Arzt, meiner Insulinpumpe, meinem Diabetesberater oder einem offiziellen Behandlungsplan stammen. Mir ist bewusst, dass falsche Einstellungen gefährlich niedrige oder hohe Blutzuckerwerte verursachen können.',
      });

  String get diabetesFinalResponsibility => _t({
        'en': 'I understand this is calculated from my saved settings and I am responsible for confirming my dose.',
        'pl': 'Rozumiem, że jest to obliczane na podstawie moich zapisanych ustawień i odpowiadam za potwierdzenie swojej dawki.',
        'nl': 'Ik begrijp dat dit wordt berekend op basis van mijn opgeslagen instellingen en dat ik verantwoordelijk ben voor het bevestigen van mijn dosis.',
        'es': 'Entiendo que esto se calcula a partir de mis ajustes guardados y que soy responsable de confirmar mi dosis.',
        'de': 'Mir ist bewusst, dass dies aus meinen gespeicherten Einstellungen berechnet wird und ich für die Bestätigung meiner Dosis verantwortlich bin.',
      });

  // ── Bolus block reasons ──
  String bolusBlock(String key) {
    switch (key) {
      case 'calculatorDisabled':
        return _t({
          'en': 'Bolus Calculator Mode is turned off. Enable it in diabetes settings.',
          'pl': 'Tryb kalkulatora bolusa jest wyłączony. Włącz go w ustawieniach cukrzycy.',
          'nl': 'Bolusrekenmodus is uitgeschakeld. Schakel deze in bij diabetesinstellingen.',
          'es': 'El modo calculadora de bolo está desactivado. Actívalo en los ajustes de diabetes.',
          'de': 'Der Bolusrechner-Modus ist ausgeschaltet. Aktiviere ihn in den Diabetes-Einstellungen.',
        });
      case 'surveyIncomplete':
        return _t({
          'en': 'Complete the Diabetes Insulin Settings Survey before using the calculator.',
          'pl': 'Wypełnij ankietę ustawień insuliny przed użyciem kalkulatora.',
          'nl': 'Vul de vragenlijst voor insuline-instellingen in voordat je de rekenmodule gebruikt.',
          'es': 'Completa el cuestionario de ajustes de insulina antes de usar la calculadora.',
          'de': 'Fülle den Fragebogen zu Insulineinstellungen aus, bevor du den Rechner verwendest.',
        });
      case 'consentMissing':
        return _t({
          'en': 'You must accept the safety confirmation before using the calculator.',
          'pl': 'Musisz zaakceptować potwierdzenie bezpieczeństwa przed użyciem kalkulatora.',
          'nl': 'Je moet de veiligheidsbevestiging accepteren voordat je de rekenmodule gebruikt.',
          'es': 'Debes aceptar la confirmación de seguridad antes de usar la calculadora.',
          'de': 'Du musst die Sicherheitsbestätigung akzeptieren, bevor du den Rechner verwendest.',
        });
      case 'settingsStale':
        return _t({
          'en': 'Your insulin settings have not been reviewed in over 90 days. For safety, bolus calculations are disabled until you review and confirm your settings.',
          'pl': 'Twoje ustawienia insuliny nie były przeglądane od ponad 90 dni. Ze względów bezpieczeństwa obliczenia bolusa są wyłączone do czasu przeglądu i potwierdzenia ustawień.',
          'nl': 'Je insuline-instellingen zijn al meer dan 90 dagen niet gecontroleerd. Voor de veiligheid zijn bolusberekeningen uitgeschakeld tot je je instellingen controleert en bevestigt.',
          'es': 'Tus ajustes de insulina no se han revisado en más de 90 días. Por seguridad, los cálculos de bolo están desactivados hasta que revises y confirmes tus ajustes.',
          'de': 'Deine Insulineinstellungen wurden seit über 90 Tagen nicht überprüft. Aus Sicherheitsgründen sind Bolusberechnungen deaktiviert, bis du deine Einstellungen überprüfst und bestätigst.',
        });
      case 'surveyOverdue':
        return _t({
          'en': 'Your insulin settings review is overdue. For safety, bolus calculations are disabled until you review and confirm them.',
          'pl': 'Przegląd ustawień insuliny jest zaległy. Ze względów bezpieczeństwa obliczenia bolusa są wyłączone do czasu ich przeglądu i potwierdzenia.',
          'nl': 'De controle van je insuline-instellingen is te laat. Voor de veiligheid zijn bolusberekeningen uitgeschakeld tot je ze controleert en bevestigt.',
          'es': 'La revisión de tus ajustes de insulina está vencida. Por seguridad, los cálculos de bolo están desactivados hasta que los revises y confirmes.',
          'de': 'Die Überprüfung deiner Insulineinstellungen ist überfällig. Aus Sicherheitsgründen sind Bolusberechnungen deaktiviert, bis du sie überprüfst und bestätigst.',
        });
      case 'glucoseUnitMissing':
        return _t({
          'en': 'Your blood-glucose unit is not set. Set mg/dL or mmol/L in settings.',
          'pl': 'Jednostka glikemii nie jest ustawiona. Ustaw mg/dL lub mmol/L w ustawieniach.',
          'nl': 'Je bloedglucose-eenheid is niet ingesteld. Stel mg/dL of mmol/L in bij instellingen.',
          'es': 'Tu unidad de glucosa no está configurada. Configura mg/dL o mmol/L en los ajustes.',
          'de': 'Deine Blutzuckereinheit ist nicht festgelegt. Stelle mg/dL oder mmol/L in den Einstellungen ein.',
        });
      case 'icrMissingForTimeBlock':
        return _t({
          'en': 'No insulin-to-carb ratio is configured for the current time. Meal bolus cannot be calculated.',
          'pl': 'Brak skonfigurowanego przelicznika insulina-węglowodany dla bieżącej pory. Nie można obliczyć bolusa na posiłek.',
          'nl': 'Er is geen insuline-koolhydraatratio ingesteld voor het huidige tijdstip. Maaltijdbolus kan niet worden berekend.',
          'es': 'No hay un ratio insulina-carbohidratos configurado para la hora actual. No se puede calcular el bolo de comida.',
          'de': 'Für die aktuelle Uhrzeit ist kein Insulin-KH-Faktor konfiguriert. Der Mahlzeitenbolus kann nicht berechnet werden.',
        });
      case 'isfMissingForTimeBlock':
        return _t({
          'en': 'No correction factor is configured for the current time. Correction bolus cannot be calculated.',
          'pl': 'Brak skonfigurowanego współczynnika korekcyjnego dla bieżącej pory. Nie można obliczyć bolusa korekcyjnego.',
          'nl': 'Er is geen correctiefactor ingesteld voor het huidige tijdstip. Correctiebolus kan niet worden berekend.',
          'es': 'No hay un factor de corrección configurado para la hora actual. No se puede calcular el bolo de corrección.',
          'de': 'Für die aktuelle Uhrzeit ist kein Korrekturfaktor konfiguriert. Der Korrekturbolus kann nicht berechnet werden.',
        });
      case 'targetGlucoseMissing':
        return _t({
          'en': 'No target glucose is configured. Correction bolus cannot be calculated.',
          'pl': 'Brak skonfigurowanej docelowej glikemii. Nie można obliczyć bolusa korekcyjnego.',
          'nl': 'Er is geen streefglucose ingesteld. Correctiebolus kan niet worden berekend.',
          'es': 'No hay glucosa objetivo configurada. No se puede calcular el bolo de corrección.',
          'de': 'Es ist keine Zielglukose konfiguriert. Der Korrekturbolus kann nicht berechnet werden.',
        });
      case 'actionDurationMissing':
        return _t({
          'en': 'Insulin action duration is not set, so insulin-on-board cannot be calculated.',
          'pl': 'Czas działania insuliny nie jest ustawiony, więc nie można obliczyć insuliny aktywnej.',
          'nl': 'Werkingsduur van insuline is niet ingesteld, dus insuline-on-board kan niet worden berekend.',
          'es': 'La duración de acción de la insulina no está configurada, por lo que no se puede calcular la insulina activa.',
          'de': 'Die Insulinwirkdauer ist nicht festgelegt, daher kann das Insulin-on-Board nicht berechnet werden.',
        });
      case 'maxBolusMissing':
        return _t({
          'en': 'No maximum single bolus is configured. Calculation is disabled for safety.',
          'pl': 'Brak skonfigurowanego maksymalnego pojedynczego bolusa. Obliczenia są wyłączone ze względów bezpieczeństwa.',
          'nl': 'Er is geen maximale enkele bolus ingesteld. Berekening is uitgeschakeld voor de veiligheid.',
          'es': 'No hay un bolo único máximo configurado. El cálculo está desactivado por seguridad.',
          'de': 'Es ist kein maximaler Einzelbolus konfiguriert. Die Berechnung ist aus Sicherheitsgründen deaktiviert.',
        });
      case 'minIncrementMissing':
        return _t({
          'en': 'No bolus rounding increment is configured. Calculation is disabled.',
          'pl': 'Brak skonfigurowanego kroku zaokrąglania bolusa. Obliczenia są wyłączone.',
          'nl': 'Er is geen afrondingsstap voor de bolus ingesteld. Berekening is uitgeschakeld.',
          'es': 'No hay un incremento de redondeo de bolo configurado. El cálculo está desactivado.',
          'de': 'Es ist kein Rundungsschritt für den Bolus konfiguriert. Die Berechnung ist deaktiviert.',
        });
      case 'currentGlucoseMissing':
        return _t({
          'en': 'A current glucose reading is required for a correction bolus.',
          'pl': 'Aktualny odczyt glikemii jest wymagany do bolusa korekcyjnego.',
          'nl': 'Een huidige glucosemeting is vereist voor een correctiebolus.',
          'es': 'Se requiere una lectura de glucosa actual para un bolo de corrección.',
          'de': 'Für einen Korrekturbolus ist ein aktueller Glukosewert erforderlich.',
        });
      case 'glucoseReadingStale':
        return _t({
          'en': 'Your glucose reading is too old. Enter a fresh reading for a correction bolus.',
          'pl': 'Twój odczyt glikemii jest zbyt stary. Wprowadź świeży odczyt do bolusa korekcyjnego.',
          'nl': 'Je glucosemeting is te oud. Voer een verse meting in voor een correctiebolus.',
          'es': 'Tu lectura de glucosa es demasiado antigua. Introduce una lectura reciente para un bolo de corrección.',
          'de': 'Dein Glukosewert ist zu alt. Gib für einen Korrekturbolus einen aktuellen Wert ein.',
        });
      case 'mealCarbsMissingOrInvalid':
        return _t({
          'en': 'Enter a valid carbohydrate amount for this meal.',
          'pl': 'Wprowadź prawidłową ilość węglowodanów dla tego posiłku.',
          'nl': 'Voer een geldige hoeveelheid koolhydraten in voor deze maaltijd.',
          'es': 'Introduce una cantidad de carbohidratos válida para esta comida.',
          'de': 'Gib eine gültige Kohlenhydratmenge für diese Mahlzeit ein.',
        });
      case 'iobRequiredButUnavailable':
        return _t({
          'en': 'Insulin-on-board is required by your settings but cannot be calculated. Calculation is disabled.',
          'pl': 'Twoje ustawienia wymagają insuliny aktywnej, ale nie można jej obliczyć. Obliczenia są wyłączone.',
          'nl': 'Insuline-on-board is vereist door je instellingen maar kan niet worden berekend. Berekening is uitgeschakeld.',
          'es': 'Tus ajustes requieren insulina activa, pero no se puede calcular. El cálculo está desactivado.',
          'de': 'Deine Einstellungen erfordern Insulin-on-Board, das jedoch nicht berechnet werden kann. Die Berechnung ist deaktiviert.',
        });
      case 'glucoseBelowHypoThreshold':
        return _t({
          'en': 'Your glucose is below your configured low threshold. This app cannot recommend insulin. Follow your hypoglycemia care plan.',
          'pl': 'Twoja glikemia jest poniżej ustawionego progu niskiego. Ta aplikacja nie może zalecać insuliny. Postępuj zgodnie z planem leczenia hipoglikemii.',
          'nl': 'Je glucose ligt onder je ingestelde lage drempel. Deze app kan geen insuline aanbevelen. Volg je hypoglykemie-zorgplan.',
          'es': 'Tu glucosa está por debajo del umbral bajo que configuraste. Esta app no puede recomendar insulina. Sigue tu plan de tratamiento de la hipoglucemia.',
          'de': 'Deine Glukose liegt unter deiner eingestellten Niedrigschwelle. Diese App kann kein Insulin empfehlen. Befolge deinen Hypoglykämie-Behandlungsplan.',
        });
      case 'glucoseImplausible':
        return _t({
          'en': 'The glucose value looks out of range. Calculation is disabled for safety.',
          'pl': 'Wartość glikemii wydaje się poza zakresem. Obliczenia są wyłączone ze względów bezpieczeństwa.',
          'nl': 'De glucosewaarde lijkt buiten bereik. Berekening is uitgeschakeld voor de veiligheid.',
          'es': 'El valor de glucosa parece estar fuera de rango. El cálculo está desactivado por seguridad.',
          'de': 'Der Glukosewert scheint außerhalb des Bereichs zu liegen. Die Berechnung ist aus Sicherheitsgründen deaktiviert.',
        });
      case 'carbsImplausible':
        return _t({
          'en': 'The carbohydrate amount looks out of range. Calculation is disabled for safety.',
          'pl': 'Ilość węglowodanów wydaje się poza zakresem. Obliczenia są wyłączone ze względów bezpieczeństwa.',
          'nl': 'De hoeveelheid koolhydraten lijkt buiten bereik. Berekening is uitgeschakeld voor de veiligheid.',
          'es': 'La cantidad de carbohidratos parece estar fuera de rango. El cálculo está desactivado por seguridad.',
          'de': 'Die Kohlenhydratmenge scheint außerhalb des Bereichs zu liegen. Die Berechnung ist aus Sicherheitsgründen deaktiviert.',
        });
      case 'settingInvalid':
        return _t({
          'en': 'One of your saved insulin settings is invalid. Review your settings.',
          'pl': 'Jedno z zapisanych ustawień insuliny jest nieprawidłowe. Przejrzyj swoje ustawienia.',
          'nl': 'Een van je opgeslagen insuline-instellingen is ongeldig. Controleer je instellingen.',
          'es': 'Uno de tus ajustes de insulina guardados no es válido. Revisa tus ajustes.',
          'de': 'Eine deiner gespeicherten Insulineinstellungen ist ungültig. Überprüfe deine Einstellungen.',
        });
      case 'maxBolusExceeded':
      default:
        return _t({
          'en': 'The calculated amount exceeds your configured maximum single bolus. This calculation is blocked. Follow your care plan or contact your clinician.',
          'pl': 'Obliczona ilość przekracza Twój maksymalny pojedynczy bolus. To obliczenie jest zablokowane. Postępuj zgodnie z planem leczenia lub skontaktuj się z lekarzem.',
          'nl': 'De berekende hoeveelheid overschrijdt je ingestelde maximale enkele bolus. Deze berekening is geblokkeerd. Volg je zorgplan of neem contact op met je arts.',
          'es': 'La cantidad calculada supera tu bolo único máximo configurado. Este cálculo está bloqueado. Sigue tu plan de tratamiento o contacta con tu médico.',
          'de': 'Die berechnete Menge überschreitet deinen eingestellten maximalen Einzelbolus. Diese Berechnung ist blockiert. Befolge deinen Behandlungsplan oder wende dich an deinen Arzt.',
        });
    }
  }

  // ── Bolus warnings ──
  String bolusWarning(String key) {
    switch (key) {
      case 'glucoseBelowTargetNoCorrection':
        return _t({
          'en': 'Your glucose is below target, so no correction insulin was added.',
          'pl': 'Twoja glikemia jest poniżej celu, więc nie dodano insuliny korekcyjnej.',
          'nl': 'Je glucose ligt onder het streefdoel, dus er is geen correctie-insuline toegevoegd.',
          'es': 'Tu glucosa está por debajo del objetivo, por lo que no se añadió insulina de corrección.',
          'de': 'Deine Glukose liegt unter dem Zielwert, daher wurde kein Korrekturinsulin hinzugefügt.',
        });
      case 'glucoseAboveHyperThreshold':
        return _t({
          'en': 'Your glucose is above your configured high threshold. Follow your diabetes care plan and consider checking ketones or contacting a clinician if instructed by your care plan.',
          'pl': 'Twoja glikemia jest powyżej ustawionego progu wysokiego. Postępuj zgodnie z planem leczenia cukrzycy i rozważ sprawdzenie ketonów lub kontakt z lekarzem, jeśli tak zaleca Twój plan.',
          'nl': 'Je glucose ligt boven je ingestelde hoge drempel. Volg je diabeteszorgplan en overweeg ketonen te controleren of een arts te raadplegen als je zorgplan dat aangeeft.',
          'es': 'Tu glucosa está por encima del umbral alto que configuraste. Sigue tu plan de tratamiento de la diabetes y considera comprobar las cetonas o contactar con un médico si tu plan lo indica.',
          'de': 'Deine Glukose liegt über deiner eingestellten Hochschwelle. Befolge deinen Diabetes-Behandlungsplan und ziehe in Betracht, Ketone zu prüfen oder einen Arzt zu kontaktieren, wenn dein Plan dies vorsieht.',
        });
      case 'iobMayBeInaccurate':
        return _t({
          'en': 'You logged recent insulin. This estimate subtracts calculated insulin-on-board, but IOB may be inaccurate. Be careful about insulin stacking and follow your care plan.',
          'pl': 'Zapisałeś/aś niedawną insulinę. Ten szacunek odejmuje obliczoną insulinę aktywną, ale IOB może być niedokładne. Uważaj na nakładanie się dawek insuliny i przestrzegaj planu leczenia.',
          'nl': 'Je hebt recent insuline geregistreerd. Deze schatting trekt berekende insuline-on-board af, maar IOB kan onnauwkeurig zijn. Wees voorzichtig met insulinestapeling en volg je zorgplan.',
          'es': 'Registraste insulina reciente. Esta estimación resta la insulina activa calculada, pero la IOB puede ser imprecisa. Ten cuidado con la acumulación de insulina y sigue tu plan de tratamiento.',
          'de': 'Du hast kürzlich Insulin erfasst. Diese Schätzung zieht berechnetes Insulin-on-Board ab, aber das IOB kann ungenau sein. Achte auf Insulin-Stacking und befolge deinen Behandlungsplan.',
        });
      case 'carbsUnusuallyHigh':
        return _t({
          'en': 'The carbohydrate amount is unusually high. Please double-check it before relying on this estimate.',
          'pl': 'Ilość węglowodanów jest niezwykle wysoka. Sprawdź ją dokładnie przed poleganiem na tym szacunku.',
          'nl': 'De hoeveelheid koolhydraten is ongewoon hoog. Controleer dit goed voordat je op deze schatting vertrouwt.',
          'es': 'La cantidad de carbohidratos es inusualmente alta. Compruébala bien antes de fiarte de esta estimación.',
          'de': 'Die Kohlenhydratmenge ist ungewöhnlich hoch. Bitte überprüfe sie genau, bevor du dich auf diese Schätzung verlässt.',
        });
      case 'estimateZeroOrNegative':
      default:
        return _t({
          'en': 'Calculated insulin need is zero or negative after considering current glucose and insulin-on-board. Follow your care plan.',
          'pl': 'Obliczone zapotrzebowanie na insulinę wynosi zero lub jest ujemne po uwzględnieniu aktualnej glikemii i insuliny aktywnej. Postępuj zgodnie z planem leczenia.',
          'nl': 'De berekende insulinebehoefte is nul of negatief na het meewegen van huidige glucose en insuline-on-board. Volg je zorgplan.',
          'es': 'La necesidad de insulina calculada es cero o negativa tras considerar la glucosa actual y la insulina activa. Sigue tu plan de tratamiento.',
          'de': 'Der berechnete Insulinbedarf ist nach Berücksichtigung der aktuellen Glukose und des Insulin-on-Board null oder negativ. Befolge deinen Behandlungsplan.',
        });
    }
  }

  // ── Diabetes settings validator messages ──
  String validatorMessage(String code, {String? label}) {
    final lbl = label ?? '';
    switch (code) {
      case 'valueNotPositive':
        return _t({
          'en': 'A $lbl value must be greater than zero.',
          'pl': 'Wartość ($lbl) musi być większa od zera.',
          'nl': 'Een $lbl-waarde moet groter zijn dan nul.',
          'es': 'Un valor de $lbl debe ser mayor que cero.',
          'de': 'Ein $lbl-Wert muss größer als null sein.',
        });
      case 'valueOutOfRange':
        return _t({
          'en': 'A $lbl value is outside a safe range.',
          'pl': 'Wartość ($lbl) jest poza bezpiecznym zakresem.',
          'nl': 'Een $lbl-waarde valt buiten een veilig bereik.',
          'es': 'Un valor de $lbl está fuera de un rango seguro.',
          'de': 'Ein $lbl-Wert liegt außerhalb eines sicheren Bereichs.',
        });
      case 'invalidTimeRange':
        return _t({
          'en': 'A $lbl time block has an invalid time range.',
          'pl': 'Blok czasowy ($lbl) ma nieprawidłowy zakres czasu.',
          'nl': 'Een $lbl-tijdblok heeft een ongeldig tijdsbereik.',
          'es': 'Un bloque horario de $lbl tiene un rango de tiempo no válido.',
          'de': 'Ein $lbl-Zeitblock hat einen ungültigen Zeitbereich.',
        });
      case 'blocksOverlap':
        return _t({
          'en': 'Your $lbl time blocks overlap. Fix them before continuing.',
          'pl': 'Twoje bloki czasowe ($lbl) nakładają się. Popraw je przed kontynuacją.',
          'nl': 'Je $lbl-tijdblokken overlappen. Corrigeer ze voordat je doorgaat.',
          'es': 'Tus bloques horarios de $lbl se solapan. Corrígelos antes de continuar.',
          'de': 'Deine $lbl-Zeitblöcke überschneiden sich. Korrigiere sie, bevor du fortfährst.',
        });
      case 'targetOutOfRange':
        return _t({
          'en': 'Target glucose is outside a safe range.',
          'pl': 'Docelowa glikemia jest poza bezpiecznym zakresem.',
          'nl': 'Streefglucose valt buiten een veilig bereik.',
          'es': 'La glucosa objetivo está fuera de un rango seguro.',
          'de': 'Die Zielglukose liegt außerhalb eines sicheren Bereichs.',
        });
      case 'actionDurationOutOfRange':
        return _t({
          'en': 'Insulin action duration is outside a safe range.',
          'pl': 'Czas działania insuliny jest poza bezpiecznym zakresem.',
          'nl': 'Werkingsduur van insuline valt buiten een veilig bereik.',
          'es': 'La duración de acción de la insulina está fuera de un rango seguro.',
          'de': 'Die Insulinwirkdauer liegt außerhalb eines sicheren Bereichs.',
        });
      case 'maxBolusOutOfRange':
        return _t({
          'en': 'Maximum single bolus is outside a safe range.',
          'pl': 'Maksymalny pojedynczy bolus jest poza bezpiecznym zakresem.',
          'nl': 'Maximale enkele bolus valt buiten een veilig bereik.',
          'es': 'El bolo único máximo está fuera de un rango seguro.',
          'de': 'Der maximale Einzelbolus liegt außerhalb eines sicheren Bereichs.',
        });
      case 'incrementUnsupported':
        return _t({
          'en': 'Bolus rounding increment is not a supported value.',
          'pl': 'Krok zaokrąglania bolusa nie jest obsługiwaną wartością.',
          'nl': 'Afrondingsstap voor de bolus is geen ondersteunde waarde.',
          'es': 'El incremento de redondeo de bolo no es un valor admitido.',
          'de': 'Der Rundungsschritt für den Bolus ist kein unterstützter Wert.',
        });
      case 'thresholdsInverted':
        return _t({
          'en': 'Low threshold must be below the high threshold.',
          'pl': 'Próg niski musi być poniżej progu wysokiego.',
          'nl': 'De lage drempel moet onder de hoge drempel liggen.',
          'es': 'El umbral bajo debe estar por debajo del umbral alto.',
          'de': 'Die Niedrigschwelle muss unter der Hochschwelle liegen.',
        });
      case 'glucoseOutOfRange':
        return _t({
          'en': 'The glucose value looks out of range.',
          'pl': 'Wartość glikemii wydaje się poza zakresem.',
          'nl': 'De glucosewaarde lijkt buiten bereik.',
          'es': 'El valor de glucosa parece estar fuera de rango.',
          'de': 'Der Glukosewert scheint außerhalb des Bereichs zu liegen.',
        });
      case 'carbsNotPositive':
        return _t({
          'en': 'Enter a carbohydrate amount greater than zero.',
          'pl': 'Wprowadź ilość węglowodanów większą od zera.',
          'nl': 'Voer een hoeveelheid koolhydraten groter dan nul in.',
          'es': 'Introduce una cantidad de carbohidratos mayor que cero.',
          'de': 'Gib eine Kohlenhydratmenge größer als null ein.',
        });
      case 'carbsOutOfRange':
        return _t({
          'en': 'The carbohydrate amount looks out of range.',
          'pl': 'Ilość węglowodanów wydaje się poza zakresem.',
          'nl': 'De hoeveelheid koolhydraten lijkt buiten bereik.',
          'es': 'La cantidad de carbohidratos parece estar fuera de rango.',
          'de': 'Die Kohlenhydratmenge scheint außerhalb des Bereichs zu liegen.',
        });
      case 'carbsUnusuallyHigh':
      default:
        return _t({
          'en': 'The carbohydrate amount is unusually high. Please double-check it.',
          'pl': 'Ilość węglowodanów jest niezwykle wysoka. Sprawdź ją dokładnie.',
          'nl': 'De hoeveelheid koolhydraten is ongewoon hoog. Controleer dit goed.',
          'es': 'La cantidad de carbohidratos es inusualmente alta. Compruébala bien.',
          'de': 'Die Kohlenhydratmenge ist ungewöhnlich hoch. Bitte überprüfe sie genau.',
        });
    }
  }

  String get validatorLabelIcr => _t({
        'en': 'insulin-to-carb ratio',
        'pl': 'przelicznik insulina-węglowodany',
        'nl': 'insuline-koolhydraatratio',
        'es': 'ratio insulina-carbohidratos',
        'de': 'Insulin-KH-Faktor',
      });

  String get validatorLabelIsf => _t({
        'en': 'correction factor',
        'pl': 'współczynnik korekcyjny',
        'nl': 'correctiefactor',
        'es': 'factor de corrección',
        'de': 'Korrekturfaktor',
      });

  String nutrientName(String key) {
    switch (key) {
      case 'calories':
        return _t({'en': 'Calories', 'pl': 'Kalorie', 'nl': 'Calorieën', 'es': 'Calorías', 'de': 'Kalorien'});
      case 'protein':
        return _t({'en': 'Protein', 'pl': 'Białko', 'nl': 'Eiwitten', 'es': 'Proteínas', 'de': 'Protein'});
      case 'carbohydrates':
        return _t({'en': 'Carbohydrates', 'pl': 'Węglowodany', 'nl': 'Koolhydraten', 'es': 'Carbohidratos', 'de': 'Kohlenhydrate'});
      case 'fat':
        return _t({'en': 'Fat', 'pl': 'Tłuszcz', 'nl': 'Vetten', 'es': 'Grasas', 'de': 'Fett'});
      case 'dietaryFiber':
        return _t({'en': 'Dietary Fiber', 'pl': 'Błonnik', 'nl': 'Vezels', 'es': 'Fibra', 'de': 'Ballaststoffe'});
      case 'vitaminA':
        return _t({'en': 'Vitamin A', 'pl': 'Witamina A', 'nl': 'Vitamine A', 'es': 'Vitamina A', 'de': 'Vitamin A'});
      case 'vitaminC':
        return _t({'en': 'Vitamin C', 'pl': 'Witamina C', 'nl': 'Vitamine C', 'es': 'Vitamina C', 'de': 'Vitamin C'});
      case 'vitaminD':
        return _t({'en': 'Vitamin D', 'pl': 'Witamina D', 'nl': 'Vitamine D', 'es': 'Vitamina D', 'de': 'Vitamin D'});
      case 'vitaminE':
        return _t({'en': 'Vitamin E', 'pl': 'Witamina E', 'nl': 'Vitamine E', 'es': 'Vitamina E', 'de': 'Vitamin E'});
      case 'vitaminK':
        return _t({'en': 'Vitamin K', 'pl': 'Witamina K', 'nl': 'Vitamine K', 'es': 'Vitamina K', 'de': 'Vitamin K'});
      case 'folateB9':
        return _t({'en': 'Folate (B9)', 'pl': 'Foliany (B9)', 'nl': 'Foliumzuur (B9)', 'es': 'Folato (B9)', 'de': 'Folat (B9)'});
      case 'vitaminB12':
        return _t({'en': 'Vitamin B12', 'pl': 'Witamina B12', 'nl': 'Vitamine B12', 'es': 'Vitamina B12', 'de': 'Vitamin B12'});
      case 'calcium':
        return _t({'en': 'Calcium', 'pl': 'Wapń', 'nl': 'Calcium', 'es': 'Calcio', 'de': 'Kalzium'});
      case 'iron':
        return _t({'en': 'Iron', 'pl': 'Żelazo', 'nl': 'IJzer', 'es': 'Hierro', 'de': 'Eisen'});
      case 'magnesium':
        return _t({'en': 'Magnesium', 'pl': 'Magnez', 'nl': 'Magnesium', 'es': 'Magnesio', 'de': 'Magnesium'});
      case 'potassium':
        return _t({'en': 'Potassium', 'pl': 'Potas', 'nl': 'Kalium', 'es': 'Potasio', 'de': 'Kalium'});
      case 'sodium':
        return _t({'en': 'Sodium', 'pl': 'Sód', 'nl': 'Natrium', 'es': 'Sodio', 'de': 'Natrium'});
      case 'zinc':
        return _t({'en': 'Zinc', 'pl': 'Cynk', 'nl': 'Zink', 'es': 'Zinc', 'de': 'Zink'});
      case 'omega3':
        return _t({'en': 'Omega-3 (EPA+DHA+ALA)', 'pl': 'Omega-3 (EPA+DHA+ALA)', 'nl': 'Omega-3 (EPA+DHA+ALA)', 'es': 'Omega-3 (EPA+DHA+ALA)', 'de': 'Omega-3 (EPA+DHA+ALA)'});
      case 'selenium':
        return _t({'en': 'Selenium', 'pl': 'Selen', 'nl': 'Selenium', 'es': 'Selenio', 'de': 'Selen'});
      case 'iodine':
        return _t({'en': 'Iodine', 'pl': 'Jod', 'nl': 'Jodium', 'es': 'Yodo', 'de': 'Jod'});
      case 'chromium':
        return _t({'en': 'Chromium', 'pl': 'Chrom', 'nl': 'Chroom', 'es': 'Cromo', 'de': 'Chrom'});
      default:
        return key;
    }
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  static const _supported = ['en', 'pl', 'nl', 'es', 'de'];

  @override
  bool isSupported(Locale locale) => _supported.contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate old) => false;
}
