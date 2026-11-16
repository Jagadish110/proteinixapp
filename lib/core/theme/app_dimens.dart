import 'package:flutter/material.dart';

/// 8px-based spacing rhythm from the Vigor Obsidian spec.
class AppSpacing {
  const AppSpacing._();

  static const double base = 4;
  static const double xs = 8;
  static const double sm = 16;
  static const double md = 24;
  static const double lg = 32;
  static const double xl = 48;

  /// Horizontal page margin.
  static const double page = 20;

  /// Gap between grid/list items.
  static const double gutter = 16;

  /// Clearance so the floating nav never covers the last scrollable item.
  static const double navClearance = 128;

  static const EdgeInsets pageInsets = EdgeInsets.symmetric(horizontal: page);

  /// Standard scroll padding for a tab screen sitting behind the floating nav.
  static const EdgeInsets screenScroll =
      EdgeInsets.fromLTRB(page, 8, page, navClearance);
}

/// Shape language: modern rounded, pills for anything touchable.
class AppRadius {
  const AppRadius._();

  static const double sm = 4;
  static const double base = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Large "organic curve" used by every content card.
  static const double card = 32;
  static const double full = 999;

  static final BorderRadius smR = BorderRadius.circular(sm);
  static final BorderRadius mdR = BorderRadius.circular(md);
  static final BorderRadius lgR = BorderRadius.circular(lg);
  static final BorderRadius xlR = BorderRadius.circular(xl);
  static final BorderRadius cardR = BorderRadius.circular(card);
  static final BorderRadius pill = BorderRadius.circular(full);
}
