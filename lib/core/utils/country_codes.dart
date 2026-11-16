/// A country's dial code entry for the phone-auth country picker.
class CountryDialCode {
  const CountryDialCode({
    required this.name,
    required this.dialCode,
    required this.flag,
  });

  final String name;
  final String dialCode;

  /// Flag emoji — renders natively, no image assets needed.
  final String flag;
}

/// Curated list of common countries. India is first since this app's
/// content (food database, Indian-language coach) targets that market by
/// default, but any country can be searched and picked.
const kCountryDialCodes = <CountryDialCode>[
  CountryDialCode(name: 'India', dialCode: '+91', flag: '🇮🇳'),
  CountryDialCode(name: 'United States', dialCode: '+1', flag: '🇺🇸'),
  CountryDialCode(name: 'United Kingdom', dialCode: '+44', flag: '🇬🇧'),
  CountryDialCode(name: 'United Arab Emirates', dialCode: '+971', flag: '🇦🇪'),
  CountryDialCode(name: 'Saudi Arabia', dialCode: '+966', flag: '🇸🇦'),
  CountryDialCode(name: 'Australia', dialCode: '+61', flag: '🇦🇺'),
  CountryDialCode(name: 'Canada', dialCode: '+1', flag: '🇨🇦'),
  CountryDialCode(name: 'Singapore', dialCode: '+65', flag: '🇸🇬'),
  CountryDialCode(name: 'Malaysia', dialCode: '+60', flag: '🇲🇾'),
  CountryDialCode(name: 'Qatar', dialCode: '+974', flag: '🇶🇦'),
  CountryDialCode(name: 'Kuwait', dialCode: '+965', flag: '🇰🇼'),
  CountryDialCode(name: 'Oman', dialCode: '+968', flag: '🇴🇲'),
  CountryDialCode(name: 'Bangladesh', dialCode: '+880', flag: '🇧🇩'),
  CountryDialCode(name: 'Pakistan', dialCode: '+92', flag: '🇵🇰'),
  CountryDialCode(name: 'Sri Lanka', dialCode: '+94', flag: '🇱🇰'),
  CountryDialCode(name: 'Nepal', dialCode: '+977', flag: '🇳🇵'),
  CountryDialCode(name: 'Germany', dialCode: '+49', flag: '🇩🇪'),
  CountryDialCode(name: 'France', dialCode: '+33', flag: '🇫🇷'),
  CountryDialCode(name: 'Netherlands', dialCode: '+31', flag: '🇳🇱'),
  CountryDialCode(name: 'Ireland', dialCode: '+353', flag: '🇮🇪'),
  CountryDialCode(name: 'New Zealand', dialCode: '+64', flag: '🇳🇿'),
  CountryDialCode(name: 'South Africa', dialCode: '+27', flag: '🇿🇦'),
  CountryDialCode(name: 'Nigeria', dialCode: '+234', flag: '🇳🇬'),
  CountryDialCode(name: 'Japan', dialCode: '+81', flag: '🇯🇵'),
  CountryDialCode(name: 'South Korea', dialCode: '+82', flag: '🇰🇷'),
  CountryDialCode(name: 'China', dialCode: '+86', flag: '🇨🇳'),
  CountryDialCode(name: 'Indonesia', dialCode: '+62', flag: '🇮🇩'),
  CountryDialCode(name: 'Philippines', dialCode: '+63', flag: '🇵🇭'),
  CountryDialCode(name: 'Brazil', dialCode: '+55', flag: '🇧🇷'),
  CountryDialCode(name: 'Mexico', dialCode: '+52', flag: '🇲🇽'),
];
