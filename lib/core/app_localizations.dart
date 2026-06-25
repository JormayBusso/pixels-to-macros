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
        'en': 'Grocery',
        'pl': 'Zakupy',
        'nl': 'Boodschap',
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
        'en': 'Remind me to log meals at 13:00',
        'pl': 'Przypomnij mi o logowaniu posiłków o 13:00',
        'nl': 'Herinner me om maaltijden te loggen om 13:00',
        'es': 'Recordarme registrar comidas a las 13:00',
        'de': 'Erinnere mich um 13:00 Mahlzeiten zu loggen',
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

  String pickRecipe(String meal) => _t({
        'en': 'Pick a $meal Recipe',
        'pl': 'Wybierz przepis na $meal',
        'nl': 'Kies een $meal recept',
        'es': 'Elige una receta de $meal',
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

  // ── Edit Food ──

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
