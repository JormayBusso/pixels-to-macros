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

  String get getStarted => _t({
        'en': "Let's get started!",
        'pl': 'Zaczynajmy!',
        'nl': "Laten we beginnen!",
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
        'en': 'All data is stored locally on your device. No data is sent to any server.',
        'pl': 'Wszystkie dane są przechowywane lokalnie na Twoim urządzeniu. Żadne dane nie są wysyłane na serwer.',
        'nl': 'Alle gegevens worden lokaal op je apparaat opgeslagen. Er worden geen gegevens naar een server gestuurd.',
        'es': 'Todos los datos se almacenan localmente en tu dispositivo. No se envían datos a ningún servidor.',
        'de': 'Alle Daten werden lokal auf deinem Gerät gespeichert. Es werden keine Daten an einen Server gesendet.',
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
        'es': 'Herramientas de evaluación científica para la investigación de tesis.',
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
            'pl': 'Zróbmy krótką wycieczkę, abyś wiedział, gdzie wszystko się znajduje.',
            'nl': 'Laten we een korte rondleiding doen zodat je weet waar alles staat.',
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
            'en': 'Tap AI Scan to open the camera.\nPoint at your plate and get instant calories & macros!\nIncludes flashlight toggle and low-light warnings.',
            'pl': 'Dotknij Skan AI, aby otworzyć aparat.\nWyceluj w talerz i natychmiast poznaj kalorie i makroskładniki!\nZawiera przełącznik latarki i ostrzeżenia o słabym oświetleniu.',
            'nl': 'Tik op AI-scan om de camera te openen.\nRicht op je bord en krijg direct calorieën en macro\'s!\nMet zaklamp-schakelaar en waarschuwingen bij weinig licht.',
            'es': 'Toca Escaneo IA para abrir la cámara.\n¡Apunta a tu plato y obtén calorías y macros al instante!\nIncluye linterna y avisos de poca luz.',
            'de': 'Tippe auf KI-Scan, um die Kamera zu öffnen.\nRichte sie auf deinen Teller und erhalte sofort Kalorien & Makros!\nInklusive Taschenlampe und Warnungen bei wenig Licht.',
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
            'en': 'Tap AI Speech to log food by voice in English.\nSay "200 grams of chicken and a banana" — it matches your food database automatically.',
            'pl': 'Dotknij Mowa AI, aby zapisać jedzenie głosem po angielsku.\nPowiedz „200 gramów kurczaka i banan" — automatycznie dopasuje to do Twojej bazy żywności.',
            'nl': 'Tik op AI-spraak om eten met je stem in het Engels te loggen.\nZeg "200 gram kip en een banaan" — het matcht automatisch met je voedingsdatabase.',
            'es': 'Toca Voz IA para registrar comida por voz en inglés.\nDi "200 gramos de pollo y un plátano" — coincide con tu base de datos de alimentos automáticamente.',
            'de': 'Tippe auf KI-Sprache, um Essen per Stimme auf Englisch zu erfassen.\nSage "200 Gramm Hähnchen und eine Banane" — es wird automatisch mit deiner Lebensmitteldatenbank abgeglichen.',
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
            'en': 'Search foods, pick from My Meals, or scan a barcode.\nBarcode scanning shows a health score (0-100) before logging.',
            'pl': 'Wyszukaj produkty, wybierz z Moich Posiłków lub zeskanuj kod kreskowy.\nSkanowanie kodu pokazuje ocenę zdrowotności (0-100) przed zapisem.',
            'nl': 'Zoek voedsel, kies uit Mijn Maaltijden of scan een barcode.\nBarcode scannen toont een gezondheidsscore (0-100) vóór het loggen.',
            'es': 'Busca alimentos, elige de Mis Comidas o escanea un código de barras.\nEl escaneo muestra una puntuación de salud (0-100) antes de registrar.',
            'de': 'Suche Lebensmittel, wähle aus Meine Mahlzeiten oder scanne einen Barcode.\nDer Barcode-Scan zeigt vor dem Erfassen einen Gesundheitswert (0-100).',
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
            'en': 'Your streak badge is now bigger and easier to spot. Keep logging daily to build momentum.',
            'pl': 'Twoja odznaka serii jest teraz większa i łatwiejsza do zauważenia. Zapisuj codziennie, aby utrzymać tempo.',
            'nl': 'Je reeks-badge is nu groter en beter zichtbaar. Blijf dagelijks loggen om je momentum op te bouwen.',
            'es': 'Tu insignia de racha ahora es más grande y fácil de ver. Sigue registrando a diario para mantener el impulso.',
            'de': 'Dein Serien-Abzeichen ist jetzt größer und leichter zu erkennen. Erfasse täglich weiter, um den Schwung zu halten.',
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
            'en': 'Tap the body icon to open the anatomy map.\nBrain, eyes, heart, lungs, gut, bones, muscles, skin, blood, and immune regions are tappable and color-coded from your nutrient intake.',
            'pl': 'Dotknij ikony ciała, aby otworzyć mapę anatomii.\nMózg, oczy, serce, płuca, jelita, kości, mięśnie, skóra, krew i obszary odpornościowe są klikalne i oznaczone kolorami na podstawie spożycia składników odżywczych.',
            'nl': 'Tik op het lichaamspictogram om de anatomiekaart te openen.\nHersenen, ogen, hart, longen, darmen, botten, spieren, huid, bloed en immuungebieden zijn aantikbaar en kleurgecodeerd op basis van je voedingsinname.',
            'es': 'Toca el icono del cuerpo para abrir el mapa anatómico.\nCerebro, ojos, corazón, pulmones, intestino, huesos, músculos, piel, sangre y zonas inmunitarias son tocables y con colores según tu ingesta de nutrientes.',
            'de': 'Tippe auf das Körpersymbol, um die Anatomiekarte zu öffnen.\nGehirn, Augen, Herz, Lunge, Darm, Knochen, Muskeln, Haut, Blut und Immunbereiche sind antippbar und je nach Nährstoffzufuhr farblich markiert.',
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
            'en': 'The leaf icon opens your full nutrition dashboard with macros, vitamins, minerals, and the upgraded micronutrient wheel.',
            'pl': 'Ikona liścia otwiera pełny pulpit odżywiania z makroskładnikami, witaminami, minerałami i ulepszonym kołem mikroskładników.',
            'nl': 'Het bladpictogram opent je volledige voedingsdashboard met macro\'s, vitamines, mineralen en het verbeterde micronutriëntenwiel.',
            'es': 'El icono de la hoja abre tu panel de nutrición completo con macros, vitaminas, minerales y la rueda de micronutrientes mejorada.',
            'de': 'Das Blattsymbol öffnet dein vollständiges Ernährungs-Dashboard mit Makros, Vitaminen, Mineralien und dem verbesserten Mikronährstoff-Rad.',
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
            'en': 'The hydration card tracks your daily water intake.\nUse the + drink button to log water, coffee, tea, and more.',
            'pl': 'Karta nawodnienia śledzi dzienne spożycie wody.\nUżyj przycisku + napój, aby zapisać wodę, kawę, herbatę i więcej.',
            'nl': 'De hydratatiekaart houdt je dagelijkse waterinname bij.\nGebruik de + drankknop om water, koffie, thee en meer te loggen.',
            'es': 'La tarjeta de hidratación registra tu consumo diario de agua.\nUsa el botón + bebida para registrar agua, café, té y más.',
            'de': 'Die Flüssigkeitskarte verfolgt deine tägliche Wasseraufnahme.\nNutze die + Getränk-Taste, um Wasser, Kaffee, Tee und mehr zu erfassen.',
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
            'en': 'Need a fast water log? Tap +200 ml for one-tap hydration updates.',
            'pl': 'Potrzebujesz szybkiego zapisu wody? Dotknij +200 ml, aby zaktualizować nawodnienie jednym dotknięciem.',
            'nl': 'Snel water loggen? Tik op +200 ml voor hydratatie-updates met één tik.',
            'es': '¿Necesitas registrar agua rápido? Toca +200 ml para actualizar la hidratación con un toque.',
            'de': 'Schnell Wasser erfassen? Tippe auf +200 ml für Flüssigkeits-Updates mit einem Tipp.',
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
            'en': 'Recommendations now adapt to your goal and nutrient gaps (like low iron, vitamin D, B12, calcium, and more).',
            'pl': 'Rekomendacje dostosowują się teraz do Twojego celu i niedoborów składników (jak niski poziom żelaza, witaminy D, B12, wapnia i innych).',
            'nl': 'Aanbevelingen passen zich nu aan je doel en voedingstekorten aan (zoals weinig ijzer, vitamine D, B12, calcium en meer).',
            'es': 'Las recomendaciones ahora se adaptan a tu objetivo y a tus carencias de nutrientes (como hierro, vitamina D, B12, calcio y más).',
            'de': 'Empfehlungen passen sich jetzt deinem Ziel und Nährstofflücken an (z. B. wenig Eisen, Vitamin D, B12, Kalzium und mehr).',
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
            'pl': 'Śledź tutaj tygodniowe i miesięczne trendy kalorii i makroskładników.',
            'nl': 'Volg hier wekelijkse en maandelijkse calorie- en macrotrends.',
            'es': 'Sigue aquí las tendencias semanales y mensuales de calorías y macros.',
            'de': 'Verfolge hier wöchentliche und monatliche Kalorien- und Makrotrends.',
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
            'en': 'Browse recipes tailored to your nutrition goal and log meals quickly.',
            'pl': 'Przeglądaj przepisy dopasowane do Twojego celu żywieniowego i szybko zapisuj posiłki.',
            'nl': 'Blader door recepten op maat van je voedingsdoel en log maaltijden snel.',
            'es': 'Explora recetas adaptadas a tu objetivo nutricional y registra comidas rápidamente.',
            'de': 'Durchstöbere Rezepte passend zu deinem Ernährungsziel und erfasse Mahlzeiten schnell.',
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
            'en': 'Use search + goal filters to find recipes that match your needs faster.',
            'pl': 'Użyj wyszukiwania i filtrów celu, aby szybciej znaleźć przepisy pasujące do Twoich potrzeb.',
            'nl': 'Gebruik zoeken + doelfilters om sneller recepten te vinden die bij je passen.',
            'es': 'Usa la búsqueda y los filtros de objetivo para encontrar recetas que se ajusten a ti más rápido.',
            'de': 'Nutze Suche + Zielfilter, um schneller passende Rezepte zu finden.',
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
            'en': 'Add items manually or get smart suggestions based on your scan history.',
            'pl': 'Dodawaj produkty ręcznie lub otrzymuj inteligentne sugestie na podstawie historii skanów.',
            'nl': 'Voeg items handmatig toe of krijg slimme suggesties op basis van je scangeschiedenis.',
            'es': 'Añade artículos manualmente u obtén sugerencias inteligentes según tu historial de escaneos.',
            'de': 'Füge Artikel manuell hinzu oder erhalte smarte Vorschläge aus deinem Scan-Verlauf.',
          }),
        ),
        // 14 – Settings
        (
          title: _t({
            'en': 'Settings ⚙️',
            'pl': 'Ustawienia ⚙️',
            'nl': 'Instellingen ⚙️',
            'es': 'Ajustes ⚙️',
            'de': 'Einstellungen ⚙️',
          }),
          body: _t({
            'en': 'Change your nutrition goal, color theme, mascot, text size, weekly badge recap, and more.\nDiabetes users can set ICR for bolus calculations.',
            'pl': 'Zmień cel żywieniowy, motyw kolorystyczny, maskotkę, rozmiar tekstu, cotygodniowe podsumowanie odznak i więcej.\nUżytkownicy z cukrzycą mogą ustawić ICR do obliczeń bolusa.',
            'nl': 'Wijzig je voedingsdoel, kleurthema, mascotte, tekstgrootte, wekelijkse badge-samenvatting en meer.\nDiabetesgebruikers kunnen ICR instellen voor bolusberekeningen.',
            'es': 'Cambia tu objetivo nutricional, tema de color, mascota, tamaño de texto, resumen semanal de insignias y más.\nLos usuarios con diabetes pueden configurar el ICR para el cálculo de bolos.',
            'de': 'Ändere dein Ernährungsziel, Farbthema, Maskottchen, Textgröße, wöchentliche Abzeichen-Zusammenfassung und mehr.\nDiabetes-Nutzer können das KE-Verhältnis (ICR) für Bolusberechnungen festlegen.',
          }),
        ),
        // 15 – Weekly Badges
        (
          title: _t({
            'en': 'Weekly Badges 🏅',
            'pl': 'Cotygodniowe odznaki 🏅',
            'nl': 'Wekelijkse badges 🏅',
            'es': 'Insignias semanales 🏅',
            'de': 'Wöchentliche Abzeichen 🏅',
          }),
          body: _t({
            'en': 'At the start of each week, the app can show the badges you earned last week.\nUse this setting to turn that recap on or off.',
            'pl': 'Na początku każdego tygodnia aplikacja może pokazać odznaki zdobyte w zeszłym tygodniu.\nUżyj tego ustawienia, aby włączyć lub wyłączyć to podsumowanie.',
            'nl': 'Aan het begin van elke week kan de app de badges tonen die je vorige week verdiende.\nGebruik deze instelling om die samenvatting aan of uit te zetten.',
            'es': 'Al inicio de cada semana, la app puede mostrar las insignias que ganaste la semana pasada.\nUsa este ajuste para activar o desactivar ese resumen.',
            'de': 'Zu Beginn jeder Woche kann die App die Abzeichen der letzten Woche anzeigen.\nMit dieser Einstellung schaltest du diese Zusammenfassung ein oder aus.',
          }),
        ),
        // 16 – Vacation Mode
        (
          title: _t({
            'en': 'Vacation Mode 🏖️',
            'pl': 'Tryb wakacyjny 🏖️',
            'nl': 'Vakantiemodus 🏖️',
            'es': 'Modo vacaciones 🏖️',
            'de': 'Urlaubsmodus 🏖️',
          }),
          body: _t({
            'en': 'Protect your streak while you\'re away.\nTap the toggle to activate Vacation Mode.\nYou can also adjust your daily water goal and Glycemic Load settings here.',
            'pl': 'Chroń swoją serię, gdy Cię nie ma.\nDotknij przełącznika, aby włączyć Tryb wakacyjny.\nMożesz tu również dostosować dzienny cel wody i ustawienia ładunku glikemicznego.',
            'nl': 'Bescherm je reeks terwijl je weg bent.\nTik op de schakelaar om Vakantiemodus in te schakelen.\nJe kunt hier ook je dagelijkse waterdoel en glycemische lading-instellingen aanpassen.',
            'es': 'Protege tu racha mientras estás fuera.\nToca el interruptor para activar el Modo vacaciones.\nTambién puedes ajustar aquí tu objetivo diario de agua y la carga glucémica.',
            'de': 'Schütze deine Serie, während du weg bist.\nTippe auf den Schalter, um den Urlaubsmodus zu aktivieren.\nHier kannst du auch dein tägliches Wasserziel und die glykämische Last anpassen.',
          }),
        ),
        // 17 – Outro
        (
          title: _t({
            'en': "You're All Set! 🚀",
            'pl': 'Wszystko gotowe! 🚀',
            'nl': 'Je bent klaar! 🚀',
            'es': '¡Todo listo! 🚀',
            'de': 'Alles bereit! 🚀',
          }),
          body: _t({
            'en': 'Start scanning your first meal — or speak it!\n\nTip: you can replay this tour anytime from Settings → About.',
            'pl': 'Zacznij od zeskanowania pierwszego posiłku — lub powiedz go!\n\nWskazówka: możesz powtórzyć tę wycieczkę w dowolnym momencie w Ustawienia → Informacje.',
            'nl': 'Begin met het scannen van je eerste maaltijd — of spreek het in!\n\nTip: je kunt deze rondleiding altijd opnieuw afspelen via Instellingen → Over.',
            'es': '¡Empieza escaneando tu primera comida o dícela!\n\nConsejo: puedes repetir este recorrido cuando quieras desde Ajustes → Acerca de.',
            'de': 'Scanne deine erste Mahlzeit — oder sprich sie ein!\n\nTipp: Du kannst diese Tour jederzeit unter Einstellungen → Info erneut starten.',
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
        'en': "Today's Nutrition",
        'pl': 'Dzisiejsze odżywianie',
        'nl': "Voeding van vandaag",
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
