import 'dart:convert';
import 'dart:typed_data';
import '../models/food_scan_result.dart';
import 'gemini_proxy_client.dart';

/// Gemini Vision service — scientific-grade food recognition & macro calculation.
class GeminiVisionService {
  // ── Image-scan prompt ──────────────────────────────────────────────────────
  static const _imagePrompt = r'''
You are a clinical nutritionist and dietitian with expertise in Indian and global cuisines.
Analyze this food image with scientific precision.

═══════════════════════════════════════════════════════════════
STEP 1 — IDENTIFY every food item visible in the image
═══════════════════════════════════════════════════════════════
- List every distinct food item (including drinks, condiments, garnishes)
- For Indian dishes: identify the exact dish (e.g. "Chicken Biryani" not just "rice")
- Distinguish cooking methods: fried vs grilled vs boiled changes calories significantly

DISH AMBIGUITY — this matters more than anything else on this list.
Many dishes are visually near-identical (chicken vs mutton biryani, rajma vs
chole, poha vs upma, paratha vs chapati, curd vs raita). Getting the dish wrong
makes every macro wrong, so:
- For EACH item, also return an "alternatives" array: the 1-3 next most likely
  dishes it could be, best guess first, empty if you are genuinely certain.
- Judge ONLY from what is visible. Do not assume the most common dish.
- If the meat, lentil or grain type cannot be determined visually, say so in
  confidence_note and set overall confidence to "low" — do not guess silently.

═══════════════════════════════════════════════════════════════
STEP 2 — ESTIMATE PORTION SIZE using visual cues
═══════════════════════════════════════════════════════════════
Use these visual references:
- A standard dinner plate = ~26cm diameter → ~250-350g cooked rice, ~300g curry
- A katori/bowl = ~150-200ml → ~120-150g dal, ~100g sabzi
- A chapati/roti = ~30-40g (6-inch) or ~60-70g (8-inch)
- A glass = ~200-250ml for liquids
- A tablespoon of oil/ghee = ~14g = 125 kcal
- "Palm-sized" protein serving ≈ 85-100g cooked
- Compare food items relative to each other for cross-validation

Always express quantity in grams (g) or millilitres (ml) with realistic estimates.
Use STANDARD SERVING SIZES from ICMR (Indian) or USDA nutritional databases.

═══════════════════════════════════════════════════════════════
STEP 3 — CALCULATE MACROS USING STANDARD DATABASE VALUES
═══════════════════════════════════════════════════════════════
Use ICMR / USDA / NIN Hyderabad nutritional values per 100g.

⚠ The table below is a SMALL SAMPLE for calibration ONLY — it is NOT a menu and
NOT exhaustive. Most meals you see will not appear in it. Rules:
- Identify the dish FIRST from the image, then recall its real nutritional
  values from your own knowledge of ICMR/USDA/NIN data.
- NEVER substitute a listed food for the one actually shown because it looks
  similar. Mutton biryani is not chicken biryani. Rajma is not dal. Paratha is
  not chapati. Report what is actually there, with its own correct values.
- Only use a row below when the food genuinely IS that food.
- Adjust for visible oil, ghee, cream, cheese and frying — restaurant and
  festive versions of a dish routinely carry 30-60% more fat than the plain
  home-cooked reference values.

CALIBRATION SAMPLE (per 100g cooked unless noted):
- Plain rice (cooked): 130 kcal, P:2.7g, C:28g, F:0.3g
- Chapati/Roti (1 piece ~30g): 90 kcal, P:2.7g, C:17g, F:1.5g
- Dal (cooked): 116 kcal, P:7.6g, C:20g, F:0.4g
- Paneer: 265 kcal, P:18.3g, C:1.2g, F:20.8g
- Chicken (grilled): 165 kcal, P:31g, C:0g, F:3.6g
- Chicken (fried): 246 kcal, P:23g, C:8g, F:13g
- Egg (boiled, 1 = 50g): 78 kcal, P:6g, C:0.6g, F:5g
- Milk (full fat, 100ml): 61 kcal, P:3.2g, C:4.7g, F:3.3g
- Curd (100g): 98 kcal, P:3.1g, C:3.4g, F:3.6g
- Idli (1 piece ~35g): 39 kcal, P:1.8g, C:7g, F:0.1g
- Dosa (1 plain ~80g): 133 kcal, P:3.5g, C:22g, F:3.5g
- Sambar (100ml): 45 kcal, P:2.1g, C:6g, F:1.2g
- Biryani (chicken, 100g): 170 kcal, P:9g, C:24g, F:4g
- Ghee (1 tbsp = 14g): 125 kcal, P:0g, C:0g, F:14g
- Oil (1 tbsp = 14g): 125 kcal, P:0g, C:0g, F:14g
- Banana (1 medium = 120g): 105 kcal, P:1.3g, C:27g, F:0.4g

VALIDATION RULE — always verify:
  calories ≈ (protein_g × 4) + (carbs_g × 4) + (fat_g × 9)
  If your numbers don't match within 10%, re-check your values.

═══════════════════════════════════════════════════════════════
STEP 4 — RETURN EXACT JSON (NO markdown, NO explanation)
═══════════════════════════════════════════════════════════════
{
  "detected": true,
  "food_items": [
    {
      "name": "exact food name",
      "quantity_g": 150,
      "unit": "g",
      "calories_per_100g": 130,
      "calories": 195,
      "protein_g": 4.1,
      "carbs_g": 42.0,
      "fat_g": 0.5,
      "fiber_g": 0.5,
      "sugar_g": 0.1,
      "sodium_mg": 5,
      "cooking_method": "boiled/fried/grilled/raw/baked",
      "confidence_note": "brief reason for estimate",
      "alternatives": ["next most likely dish", "third most likely"]
    }
  ],
  "total": {
    "calories": 195,
    "protein_g": 4.1,
    "carbs_g": 42.0,
    "fat_g": 0.5,
    "fiber_g": 0.5,
    "sugar_g": 0.1,
    "sodium_mg": 5
  },
  "confidence": "high",
  "meal_type": "breakfast/lunch/dinner/snack",
  "portion_estimation_method": "describe how you estimated portion (plate size, count, visual comparison)",
  "calorie_check": "protein×4 + carbs×4 + fat×9 = X kcal vs stated Y kcal"
}

If no food detected:
{"detected": false, "food_items": [], "total": {"calories":0,"protein_g":0,"carbs_g":0,"fat_g":0,"fiber_g":0,"sugar_g":0,"sodium_mg":0}, "confidence": "low", "meal_type": "snack", "portion_estimation_method": "", "calorie_check": ""}
''';

  // ── Text-only prompt ───────────────────────────────────────────────────────
  static const _textPromptBase = r'''
You are a clinical nutritionist. The user has described what they ate, in text.
Calculate calories and macros with scientific precision.

Use ICMR / USDA / NIN Hyderabad nutritional values.
Parse quantities, units (g, kg, ml, cup, piece, serving, tbsp, tsp) and food names from the input.
If quantity is not specified, use a typical Indian/standard serving size.

WHAT COUNTS AS FOOD — read this before deciding:
1. A snack is food. A single ingredient is food. Nuts, dried fruit, one biscuit,
   a spoon of ghee — all food. Do NOT require a cooked dish or a full meal.
2. EVERY distinct food named gets its OWN entry in food_items. "4 almonds,
   cashew and dates" is THREE entries, never one combined entry and never a
   generic name like "mixed dry fruits". Split on commas and on "and".
3. Bare counts refer to PIECES: "4 almonds" = 4 pieces, not 4 grams. Multiply
   the per-piece weight below by the count to get quantity_g.
4. A count given once does not apply to the rest of the list. In "4 almonds,
   cashew and dates" only the almonds are 4; the others have no quantity, so
   use a typical serving for each.
5. Small quantities are still real. 4 almonds is ~28 kcal — return it, never
   round it to zero and never drop the item for being small.
6. Set detected:false ONLY when the text names no food whatsoever. If even one
   food is recognisable, detected is true and that food is listed.

Name each item in its own singular/plural natural form ("Almonds", "Cashews",
"Dates") — the app maps that name to an icon, so a combined or invented name
gives the wrong picture.

⚠ The table below is a SMALL SAMPLE for calibration ONLY — not exhaustive, and
not a list to match against. Identify what the user actually described, then use
your own knowledge of its real values. Never substitute a listed food for a
similar-sounding one.

CALIBRATION SAMPLE (per 100g cooked unless noted):
- Plain rice (cooked): 130 kcal, P:2.7g, C:28g, F:0.3g
- Chapati/Roti (1 piece ~30g): 90 kcal, P:2.7g, C:17g, F:1.5g
- Dal (cooked): 116 kcal, P:7.6g, C:20g, F:0.4g
- Paneer: 265 kcal, P:18.3g, C:1.2g, F:20.8g
- Chicken (grilled): 165 kcal, P:31g, C:0g, F:3.6g
- Chicken (fried): 246 kcal, P:23g, C:8g, F:13g
- Egg (boiled, 1 = 50g): 78 kcal, P:6g, C:0.6g, F:5g
- Milk (full fat, 100ml): 61 kcal, P:3.2g, C:4.7g, F:3.3g
- Curd (100g): 98 kcal, P:3.1g, C:3.4g, F:3.6g
- Idli (1 piece ~35g): 39 kcal, P:1.8g, C:7g, F:0.1g
- Dosa (1 plain ~80g): 133 kcal, P:3.5g, C:22g, F:3.5g
- Sambar (100ml): 45 kcal, P:2.1g, C:6g, F:1.2g
- Biryani (chicken, 100g): 170 kcal, P:9g, C:24g, F:4g
- Ghee (1 tbsp = 14g): 125 kcal, P:0g, C:0g, F:14g
- Banana (1 medium = 120g): 105 kcal, P:1.3g, C:27g, F:0.4g

PER-PIECE WEIGHTS for items counted rather than weighed. These are the ones
users name by number, and guessing grams for them is the most common error:
- Almond (1 piece = 1.2g): 7 kcal, P:0.26g, C:0.24g, F:0.6g
- Cashew (1 piece = 1.5g): 9 kcal, P:0.27g, C:0.44g, F:0.7g
- Walnut (1 half = 3g): 20 kcal, P:0.5g, C:0.4g, F:2g
- Pistachio (1 piece = 0.7g): 4 kcal, P:0.14g, C:0.2g, F:0.32g
- Peanut (1 piece = 0.8g): 5 kcal, P:0.2g, C:0.13g, F:0.4g
- Date, dried (1 piece = 8g): 23 kcal, P:0.2g, C:6.2g, F:0g
- Raisin (1 tbsp = 10g): 30 kcal, P:0.3g, C:8g, F:0g
- Fig, dried (1 piece = 8g): 20 kcal, P:0.3g, C:5g, F:0.1g
- Biscuit / marie (1 piece = 5g): 23 kcal, P:0.4g, C:4g, F:0.7g

TYPICAL SERVINGS when a count is not given, for the same items:
almonds 10 pieces, cashews 8 pieces, walnuts 4 halves, pistachios 15 pieces,
dates 2 pieces, raisins 1 tbsp, mixed nuts 25g.

VALIDATION: calories ≈ (protein_g × 4) + (carbs_g × 4) + (fat_g × 9). Verify this.

RETURN ONLY JSON (NO markdown, NO explanation):
{
  "detected": true,
  "food_items": [
    {
      "name": "exact food name",
      "quantity_g": 150,
      "unit": "g",
      "calories_per_100g": 130,
      "calories": 195,
      "protein_g": 4.1,
      "carbs_g": 42.0,
      "fat_g": 0.5,
      "fiber_g": 0.5,
      "sugar_g": 0.1,
      "sodium_mg": 5,
      "cooking_method": "boiled/fried/grilled/raw/baked",
      "confidence_note": "brief note"
    }
  ],
  "total": {
    "calories": 195,
    "protein_g": 4.1,
    "carbs_g": 42.0,
    "fat_g": 0.5,
    "fiber_g": 0.5,
    "sugar_g": 0.1,
    "sodium_mg": 5
  },
  "confidence": "high",
  "meal_type": "breakfast/lunch/dinner/snack",
  "portion_estimation_method": "user-provided quantities",
  "calorie_check": "protein×4 + carbs×4 + fat×9 = X kcal"
}
If input is not food: {"detected": false, "food_items": [], "total": {"calories":0,"protein_g":0,"carbs_g":0,"fat_g":0,"fiber_g":0,"sugar_g":0,"sodium_mg":0}, "confidence": "low", "meal_type": "snack", "portion_estimation_method": "", "calorie_check": ""}
''';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Scan a food image and return macros/calories.
  /// [userHint] — optional user-provided context e.g. "chicken biryani, 200g"
  Future<FoodScanResult> scanImage(Uint8List jpegBytes,
      {String? userHint}) async {
    // Prepend user hint to the prompt so AI uses it for better portion estimates
    final promptWithHint = (userHint != null && userHint.trim().isNotEmpty)
        ? 'USER CONTEXT (use this for accurate identification and portion sizing):\n"${userHint.trim()}"\n\n$_imagePrompt'
        : _imagePrompt;

    final contents = [
      {
        'role': 'user',
        'parts': [
          {'text': promptWithHint},
          {
            'inline_data': {
              'mime_type': 'image/jpeg',
              'data': base64Encode(jpegBytes),
            },
          },
        ],
      },
    ];

    // One retry on an unparseable reply. A malformed response used to fall
    // through to "no food detected", which reads to the user as a bad analysis
    // rather than the transient glitch it usually is.
    for (var attempt = 0; attempt < 2; attempt++) {
      final text = await GeminiProxyClient.generate(
        kind: 'vision',
        model: _visionModel,
        contents: contents,
        generationConfig: _jsonGenerationConfig,
      );
      final parsed = _parse(text);
      if (parsed != null) return _reconcile(parsed);
    }
    return _empty();
  }

  /// Text-only query: user types food description → AI returns macros/calories.
  Future<FoodScanResult> scanText(String foodDescription) async {
    final prompt =
        '$_textPromptBase\n\nUSER MEAL DESCRIPTION:\n"$foodDescription"';
    final contents = [
      {
        'role': 'user',
        'parts': [
          {'text': prompt}
        ],
      },
    ];
    for (var attempt = 0; attempt < 2; attempt++) {
      final text = await GeminiProxyClient.generate(
        kind: 'text',
        model: _textModel,
        contents: contents,
        generationConfig: _jsonGenerationConfig,
      );
      final parsed = _parse(text);
      if (parsed != null) return _reconcile(parsed);
    }
    return _empty();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Both paths run on Flash, via the `-latest` alias rather than a dated
  /// version — Google has repeatedly retired dated models for new API keys
  /// outright (e.g. gemini-2.5-flash), and the alias is what keeps working
  /// across that without an app release.
  ///
  /// Kept as two constants rather than one so the vision path can be moved to
  /// `gemini-pro-latest` by editing a single line — Pro is materially better
  /// at identifying a specific dish from a photo, but costs roughly 8-10x per
  /// image. Text parsing has no recognition to do and should stay on Flash
  /// regardless.
  static const _visionModel = 'gemini-flash-latest';
  static const _textModel = 'gemini-flash-latest';

  static const _jsonGenerationConfig = {
    'temperature': 0.1,
    'responseMimeType': 'application/json',
  };

  /// Returns null when the reply couldn't be parsed, so callers can retry.
  /// A parse failure is not the same as "no food in the photo".
  FoodScanResult? _parse(String raw) {
    if (raw.isEmpty) return null;
    var cleaned = raw
        .replaceAll(RegExp(r'^```(json)?', multiLine: true), '')
        .replaceAll(RegExp(r'```$', multiLine: true), '')
        .trim();
    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      cleaned = cleaned.substring(firstBrace, lastBrace + 1);
    }
    try {
      final json = jsonDecode(cleaned) as Map<String, dynamic>;
      return FoodScanResult.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Enforces the Atwater check the prompt asks for.
  ///
  /// The prompt tells the model to verify `cal ≈ P×4 + C×4 + F×9` and even
  /// returns a `calorie_check` string, but nothing ever validated it — so when
  /// the model's arithmetic drifted, the wrong calorie count was logged as
  /// fact. Macros are estimated from identified foods and portions; the calorie
  /// figure is a derived number, so when the two disagree the macros are the
  /// more trustworthy source and the total is recomputed from them.
  FoodScanResult _reconcile(FoodScanResult r) {
    if (!r.detected || r.foodItems.isEmpty) return r;

    final derived =
        (r.totalProteinG * 4) + (r.totalCarbsG * 4) + (r.totalFatG * 9);
    if (derived <= 0) return r;

    final stated = r.totalCalories.toDouble();
    final drift = (stated - derived).abs() / derived;
    if (drift <= 0.10) return r;

    return r.copyWith(
      totalCalories: derived.round(),
      calorieCheck: 'Adjusted: macros imply ${derived.round()} kcal, '
          'model stated ${stated.round()} kcal '
          '(${(drift * 100).round()}% off).',
    );
  }

  FoodScanResult _empty() => FoodScanResult(
        detected: false,
        foodItems: const [],
        totalCalories: 0,
        totalProteinG: 0,
        totalCarbsG: 0,
        totalFatG: 0,
        totalFiberG: 0,
        totalSugarG: 0,
        totalSodiumMg: 0,
        confidence: 'low',
        mealType: 'snack',
        portionEstimationMethod: '',
        calorieCheck: '',
      );
}
