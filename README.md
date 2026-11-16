# NutiAI — Flutter Android Fitness & Nutrition App

Complete production-ready Flutter source for **NutiAI**, an AI-powered fitness and
nutrition tracker built for Indian and global users.

## Stack

- **Frontend**: Flutter / Dart (Material 3)
- **Backend**: Supabase (Auth + Postgres + Storage)
- **AI**: Google Gemini (`gemini-1.5-flash`) for food vision + AI coach
- **State**: Riverpod
- **Local Storage**: SharedPreferences
- **Native Android**: Kotlin (Sleep Guard service, Health Connect, Installed apps)

## Project Layout

```
nutiai_flutter/
├── pubspec.yaml
├── .env.example                    → copy to .env, fill in your keys
├── supabase_schema.sql             → run in Supabase SQL editor
├── lib/                            → Flutter Dart source
└── android/                        → Android native (Kotlin)
```

## Setup

### 1. Install Flutter
- Install Flutter 3.19+ and Android Studio
- `flutter doctor` should be all green

### 2. Configure Supabase
1. Create a project at https://supabase.com
2. Open SQL Editor → paste `supabase_schema.sql` → run
3. Enable Email auth in **Authentication → Providers**
4. Enable Google OAuth in **Authentication → Providers** (paste your Google Web Client ID)
5. Create a public bucket called `avatars` in **Storage**
6. Copy your **Project URL** and **anon public key**

### 3. Configure Gemini
The Gemini key is **not** stored in the app anymore — it lives only as a
secret on the `gemini-proxy` Supabase Edge Function (`supabase/functions/gemini-proxy`),
so it can't be extracted from the built APK. The app calls that function
instead of the Gemini API directly, and the function enforces a per-user daily
quota (see `supabase/migrations/20260816000000_ai_usage_quota.sql`).
1. Get an API key at https://aistudio.google.com/apikey
2. Deploy the function: `supabase functions deploy gemini-proxy --project-ref <ref>`
3. Set the secret: `supabase secrets set GEMINI_API_KEY=<key> --project-ref <ref>`

### 4. Configure Google Sign-In (for Supabase OAuth)
- Follow https://supabase.com/docs/guides/auth/social-login/auth-google
- Create OAuth client IDs (Web + Android) in Google Cloud Console
- Add Android SHA-1 fingerprint

### 5. Env file
```bash
cp .env.example .env
# Fill in keys
```

Optional keys, all off when absent:

```bash
# Turns the Free / Pro split on. Leave unset until the Play products and the
# RevenueCat `premium` entitlement exist, or the paywall has nothing to sell.
ENFORCE_PREMIUM=true

# AdMob. With no banner unit the ad SDK is never started and no ad is shown.
# Without an app id the build uses Google's sample id (test ads only).
ADMOB_APP_ID=ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX
ADMOB_BANNER_UNIT_ID=ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX
```

### 6. Plans (Free / Pro)

| | Free | Pro |
|---|---|---|
| Search, barcode, saved meals, dashboard | unlimited | unlimited |
| Photo scans | 3 a day | unlimited |
| AI text and voice logging | — | included |
| AI Coach (30 messages a day) | — | included |
| Banner ad on the home dashboard | yes | no |

Set up in Play Console and RevenueCat, not in code:

1. Two subscriptions in Play Console: monthly at ₹49 and yearly at ₹399.
2. A 7-day free-trial offer on the **yearly** base plan only.
3. In RevenueCat, attach both to one offering and to the entitlement `premium`
   (the identifier stays `premium`; the app calls the plan "Pro").

The paywall reads prices and the trial from the store, so it shows whatever is
configured there. The trial reminder is a local notification two days before
the trial ends; cancelling is one tap from Profile → Subscription, which opens
Google Play's cancel screen for the subscription.

The 3-scans and 30-messages limits are counted on the device
(`lib/services/plan_limits.dart`). The server-side quota in `gemini-proxy` is
unchanged and remains the hard ceiling.

**Ads and health data.** The only ad is one banner at the bottom of the home
dashboard (`lib/widgets/home_banner_ad.dart`). Requests carry no keywords, user
id or any app data — see the rules at the top of `lib/services/ad_service.dart`.
Health Connect steps and sleep must never be passed to the ad SDK.

### 7. Build
```bash
flutter pub get
flutter run            # debug build on connected device
flutter build apk      # release apk → build/app/outputs/flutter-apk/app-release.apk
```

## Sleep tracking

Set a bedtime and a wake time on the dashboard's Sleep Cycle card, or on `/sleep`,
and switch it on. No setup flow, no foreground service, no permission prompts.

**How it measures.** Three `AlarmManager` alarms — bedtime, wake, and a self-chaining
sample every 15 minutes between them. Each sample reads one boolean
(`PowerManager.isInteractive`) and exits; nothing stays resident. Sleep is the sum of
the dark stretches ≥15 min, excluding the awake gaps, so it is time *asleep* rather
than time in bed. Nights under 45 minutes report zero. See `ANDROID_NATIVE.md`.

**Permissions.** Turning notifications on is the entire setup — there is no
special-access screen to visit. Sleep tracking itself needs nothing beyond
`RECEIVE_BOOT_COMPLETED` (to rebuild alarms after a restart). No
`PACKAGE_USAGE_STATS`, no exact-alarm access, no battery-optimisation allowlist,
no foreground service, no `AccessibilityService`.

**What that costs.** Android is free to batch inexact alarms into Doze maintenance
windows, so reminders can arrive late and several together, and sleep samples can be
dropped. Sample alarms are therefore scheduled independently rather than chained — a
dropped one costs a single sample, not the rest of the night — and opening the app
re-books whatever is missing.

**Accuracy.** Bounded by the sample interval, and the app says so on the sleep screen:
a phone picked up and put down inside 15 minutes leaves no trace, so `phone_pickups`
and the wake-up count are floors rather than exact counts.

Diagnostics (`/diagnostics`) shows the sample count, which distinguishes "the alarms
never ran" from "they ran and saw a quiet night" — the first question to ask when a
night comes back empty.

> The old Sleep Guard — app blocking via `SYSTEM_ALERT_WINDOW` overlays and a
> foreground service polling the foreground app every 1.5s — is gone. Only the sleep
> *measurement* remains.

## Health Connect

Reads steps via `HealthConnectClient` only when the app is opened or pulled-to-refresh.
**No continuous sensor listening.** Falls back to a one-shot `TYPE_STEP_COUNTER` read
on devices without Health Connect.

## App Modules

| Tab | Screen | Purpose |
|---|---|---|
| Home | `home_screen.dart` | Daily summary, calorie ring, meal cards, water, steps, sleep widget |
| Meals | `meals_screen.dart` | Per-meal log, macro grid, quick log entry points |
| Scan | `food_scanner_screen.dart` | Gemini Vision food recognition with confidence badge |
| Progress | `progress_screen.dart` | Charts (weight, calories, macros, steps, sleep, water) |
| Coach | `ai_coach_screen.dart` | Personalized Gemini chat with multilingual support |

## License

Proprietary — built for the NutiAI brand.
