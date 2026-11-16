import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_dimens.dart';
import '../theme/app_typography.dart';
import 'country_codes.dart';

/// Shows a searchable bottom sheet of country dial codes and returns the
/// one the user picked, or null if they dismissed it.
Future<CountryDialCode?> pickCountryCode(BuildContext context) {
  return showModalBottomSheet<CountryDialCode>(
    context: context,
    backgroundColor: AppColors.surfaceContainer,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => const _CountryCodeSheet(),
  );
}

class _CountryCodeSheet extends StatefulWidget {
  const _CountryCodeSheet();

  @override
  State<_CountryCodeSheet> createState() => _CountryCodeSheetState();
}

class _CountryCodeSheetState extends State<_CountryCodeSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final results = query.isEmpty
        ? kCountryDialCodes
        : kCountryDialCodes
            .where((c) =>
                c.name.toLowerCase().contains(query) ||
                c.dialCode.contains(query))
            .toList();

    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page,
                    AppSpacing.md, AppSpacing.page, AppSpacing.sm),
                child: Text('Select country', style: AppText.headlineMd()),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.page),
                child: TextField(
                  controller: _search,
                  autofocus: false,
                  onChanged: (_) => setState(() {}),
                  style: AppText.body(),
                  decoration: const InputDecoration(
                    hintText: 'Search country or code…',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.page, vertical: 4),
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final c = results[i];
                    return ListTile(
                      onTap: () => Navigator.pop(context, c),
                      contentPadding: EdgeInsets.zero,
                      leading:
                          Text(c.flag, style: const TextStyle(fontSize: 22)),
                      title: Text(c.name, style: AppText.body()),
                      trailing: Text(c.dialCode,
                          style: AppText.bodyBold(color: AppColors.primary)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
