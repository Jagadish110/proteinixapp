import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/theme/app_typography.dart';

/// Labelled pill input. The label sits above the field in `labelCaps`, matching
/// the sign-in / onboarding forms.
class TerraField extends StatelessWidget {
  const TerraField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.icon,
    this.suffix,
    this.obscure = false,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.onSubmitted,
    this.trailingText,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.nextFocus,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final IconData? icon;
  final Widget? suffix;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  /// When set, the keyboard shows "Next" and jumps here on submit.
  final FocusNode? nextFocus;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;

  /// Muted unit shown inside the field on the right ("kg", "cm").
  final String? trailingText;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!.toUpperCase(), style: AppText.labelCaps(size: 11)),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscure,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLines: obscure ? 1 : maxLines,
          enabled: enabled,
          autofocus: autofocus,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction ??
              (maxLines > 1
                  ? TextInputAction.newline
                  : nextFocus != null
                      ? TextInputAction.next
                      : TextInputAction.done),
          onSubmitted: (value) {
            onSubmitted?.call(value);
            if (nextFocus != null) {
              nextFocus!.requestFocus();
            } else if (onSubmitted == null) {
              FocusManager.instance.primaryFocus?.unfocus();
            }
          },
          style:
              AppText.body(color: AppColors.onSurface).copyWith(fontSize: 16),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon == null ? null : Icon(icon, size: 20),
            suffixIcon: suffix ??
                (trailingText == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: Align(
                          alignment: Alignment.centerRight,
                          widthFactor: 1,
                          child: Text(
                            trailingText!,
                            style:
                                AppText.body(color: AppColors.onSurfaceVariant),
                          ),
                        ),
                      )),
            border: OutlineInputBorder(
              borderRadius: maxLines > 1 ? AppRadius.cardR : AppRadius.pill,
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: maxLines > 1 ? AppRadius.cardR : AppRadius.pill,
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: maxLines > 1 ? AppRadius.cardR : AppRadius.pill,
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// Multi-line input that fills a card and is tappable across its whole surface.
///
/// A bare borderless TextField only accepts taps on the text lines themselves,
/// so the card padding around it looks like an input but does nothing. This
/// forwards taps anywhere on the card to the field's focus node.
class TerraTextArea extends StatefulWidget {
  const TerraTextArea({
    super.key,
    required this.controller,
    this.hint,
    this.minLines = 3,
    this.maxLines = 5,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String? hint;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<TerraTextArea> createState() => _TerraTextAreaState();
}

class _TerraTextAreaState extends State<TerraTextArea> {
  FocusNode? _owned;
  late final FocusNode _node = widget.focusNode ?? (_owned = FocusNode());

  @override
  void initState() {
    super.initState();
    // Drives the focused border colour.
    _node.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Android's back button hides the IME without clearing focus, so a
        // `hasFocus` guard alone left the field focused with no keyboard and
        // every further tap doing nothing. Re-show the IME explicitly in that
        // case instead of assuming focus implies a visible keyboard.
        if (_node.hasFocus) {
          SystemChannels.textInput.invokeMethod<void>('TextInput.show');
        } else {
          _node.requestFocus();
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: AppRadius.cardR,
          border: Border.all(
            color: _node.hasFocus ? AppColors.primary : AppColors.outline,
            width: _node.hasFocus ? 2 : 1,
          ),
        ),
        child: TextField(
          controller: widget.controller,
          focusNode: _node,
          autofocus: widget.autofocus,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          onChanged: widget.onChanged,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          style: AppText.body().copyWith(fontSize: 17, height: 1.5),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            hintText: widget.hint,
            filled: false,
            isDense: true,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintStyle: AppText.body(
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.55)),
          ),
        ),
      ),
    );
  }
}

/// Taps outside a text field close the keyboard.
///
/// Wrap any screen that hosts a form — without it, a tap on empty space leaves
/// the keyboard covering half the layout with no obvious way to dismiss it.
class DismissKeyboard extends StatelessWidget {
  const DismissKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

/// Two-or-more option segmented pill (kg/lbs, cm/ft, week ranges).
class SegmentedPill<T> extends StatelessWidget {
  const SegmentedPill({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    required this.labelBuilder,
    this.activeColor = AppColors.secondary,
    this.activeTextColor = AppColors.onSecondary,
    this.compact = false,
  });

  final List<T> values;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T) labelBuilder;
  final Color activeColor;
  final Color activeTextColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Scrollable, not just sized to fit: values.length varies per caller
    // (meal slots are user-configurable, and a longer label set on a
    // narrower phone is exactly what turned this into a fixed-width Row
    // overflowing past the screen edge). Scrolling is the one layout that
    // can't overflow regardless of how many pills or how narrow the device.
    //
    // ListView, not SingleChildScrollView — the latter has no shrinkWrap,
    // and shrinkWrap: true is load-bearing here, not tidying: one caller
    // floats this as a compact pill centered over the camera preview (Align
    // inside a Stack), which hands it bounded-but-loose width. Without
    // shrinkWrap a scroll view under bounded constraints claims all of it by
    // default, which would stretch that centered pill into a full-width bar.
    //
    // A fixed SizedBox height, not IntrinsicHeight, solves the other axis:
    // a ListView, even shrink-wrapped along its scroll direction, still
    // defaults to filling whatever cross-axis space it's handed — harmless
    // in a Column, where the cross axis is just this widget's own width, but
    // that same camera-preview caller hands it a *tall*, loosely-bounded
    // height (Align in a Stack.expand), which used to stretch the pill into
    // a tall dark capsule. IntrinsicHeight looked like the fix but silently
    // broke every caller instead: RenderViewportBase (what backs any
    // ListView) hard-codes computeMaxIntrinsicHeight to return 0.0 — laying
    // out "every child to measure them" defeats the point of a viewport —
    // so IntrinsicHeight collapsed this to zero height everywhere, not just
    // in the one context it was meant to fix. A concrete height sized to
    // this pill's own padding + text avoids querying the viewport for
    // anything it can't answer.
    final height = compact ? 36.0 : 40.0;
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        children: [
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: AppRadius.pill,
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: values.map((v) {
                final active = v == selected;
                return GestureDetector(
                  onTap: () => onChanged(v),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 12 : 16,
                      vertical: compact ? 5 : 7,
                    ),
                    decoration: BoxDecoration(
                      color: active ? activeColor : Colors.transparent,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(
                      labelBuilder(v),
                      style: AppText.labelCaps(
                        color: active
                            ? activeTextColor
                            : AppColors.onSurfaceVariant,
                        size: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
