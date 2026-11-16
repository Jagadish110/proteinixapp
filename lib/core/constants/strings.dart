class AppStrings {
  const AppStrings._();

  static const appName = 'Proteinix';
  static const appFullName = 'Proteinix';

  /// Shown on the licences page. Must match `version:` in pubspec.yaml —
  /// app_version_test.dart fails if they drift apart.
  static const appVersion = '1.0.0';

  /// Where the Support screen sends mail.
  ///
  /// PLACEHOLDER — currently the developer's personal account, so the feature
  /// works today. Swap this one line for a dedicated support address before
  /// release: every user who opens Support sees it, and Play requires a
  /// public support contact on the listing regardless.
  static const supportEmail = 'nallupureddyjagadishwarreddy@gmail.com';
  static const tagline = 'Rooted Wellness';
  static const welcomeHeadline = 'Reconnect with your\nnatural rhythm.';
  static const welcomeBody =
      'Earthy nutrition, mindful progress, and organic coaching tailored for you.';

  // Auth
  static const getStarted = 'Get Started';
  static const signIn = 'Sign In';
  static const signUp = 'Sign Up';
  static const createAccount = 'Create Account';
  static const email = 'Email Address';
  static const password = 'Password';
  static const forgotPassword = 'Forgot password?';
  static const continueWithGoogle = 'Continue with Google';

  // Onboarding
  static const personalProfile = 'Personal Profile';
  static const goalQuestion = 'What is your primary goal?';
  static const activityQuestion = 'How active are you?';
  static const completeProfile = 'Complete Profile';
  static const onboardingTerms =
      'By completing, you agree to our wellness privacy terms.';

  // Tabs
  static const home = 'Home';
  static const nutrition = 'Nutrition';
  static const capture = 'Capture';
  static const progress = 'Progress';
  static const coach = 'AI Coach';

  // Sections
  static const dailyEnergy = 'DAILY ENERGY & NUTRITION';
  static const sleepCycle = 'SLEEP CYCLE';
  static const todaysProgress = "TODAY'S PROGRESS";
  static const dailySteps = 'DAILY STEPS';
  static const hydration = 'HYDRATION';
  static const todaysMeals = "Today's Meals";
  static const logFood = 'Log Food';
}
