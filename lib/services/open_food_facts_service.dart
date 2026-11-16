import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// A packaged product looked up by its barcode.
///
/// The macros are what is printed on the pack, per 100 g (or 100 ml), which
/// is why a barcode log shows exact figures where a photo scan shows an
/// estimate.
class BarcodeProduct {
  const BarcodeProduct({
    required this.barcode,
    required this.name,
    required this.kcalPer100,
    required this.proteinPer100,
    required this.carbsPer100,
    required this.fatPer100,
    required this.fiberPer100,
    this.brand,
    this.servingSize,
    this.isLiquid = false,
  });

  final String barcode;
  final String name;
  final String? brand;
  final double kcalPer100;
  final double proteinPer100;
  final double carbsPer100;
  final double fatPer100;
  final double fiberPer100;

  /// One labelled serving, in grams or millilitres. Null when the pack does
  /// not state one — the quantity picker then starts at 100.
  final double? servingSize;

  /// Drinks are labelled per 100 ml, so the unit shown follows the product.
  final bool isLiquid;

  String get unit => isLiquid ? 'ml' : 'g';

  String get displayName =>
      (brand == null || brand!.isEmpty) ? name : '$name · $brand';

  /// Macros for [quantity] grams / millilitres of this product.
  ({int kcal, double protein, double carbs, double fat, double fiber}) forQuantity(
      double quantity) {
    final m = quantity / 100;
    return (
      kcal: (kcalPer100 * m).round(),
      protein: proteinPer100 * m,
      carbs: carbsPer100 * m,
      fat: fatPer100 * m,
      fiber: fiberPer100 * m,
    );
  }

  /// Builds a product from an Open Food Facts `product` object, or returns
  /// null when it carries no usable energy figure — a product with a name but
  /// no nutrition table would log as zero calories, which is worse than
  /// telling the user it was not found.
  static BarcodeProduct? fromOpenFoodFacts(
      String barcode, Map<String, dynamic> product) {
    final nutriments = product['nutriments'];
    if (nutriments is! Map) return null;

    double? num_(String key) {
      final v = nutriments[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    // Energy is published in kcal for most products and only in kJ for some.
    var kcal = num_('energy-kcal_100g');
    if (kcal == null) {
      final kj = num_('energy-kj_100g') ?? num_('energy_100g');
      if (kj != null) kcal = kj / 4.184;
    }
    if (kcal == null || kcal < 0) return null;

    String? text(String key) {
      final v = product[key];
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    final name =
        text('product_name') ?? text('product_name_en') ?? text('generic_name');
    if (name == null) return null;

    // "brands" is a comma-separated list; the first is the one on the pack.
    final brand = text('brands')?.split(',').first.trim();

    final servingRaw = product['serving_quantity'];
    final serving = servingRaw is num
        ? servingRaw.toDouble()
        : servingRaw is String
            ? double.tryParse(servingRaw)
            : null;

    final servingText = (text('serving_size') ?? text('quantity') ?? '')
        .toLowerCase();
    final isLiquid = RegExp(r'\d\s*(ml|cl|l)\b').hasMatch(servingText);

    double clean(double? v) => (v == null || v < 0) ? 0 : v;

    return BarcodeProduct(
      barcode: barcode,
      name: name,
      brand: brand,
      kcalPer100: kcal,
      proteinPer100: clean(num_('proteins_100g')),
      carbsPer100: clean(num_('carbohydrates_100g')),
      fatPer100: clean(num_('fat_100g')),
      fiberPer100: clean(num_('fiber_100g')),
      servingSize: (serving != null && serving > 0) ? serving : null,
      isLiquid: isLiquid,
    );
  }
}

/// Thrown when the lookup could not be completed — no connection, a timeout,
/// or the service being down. Distinct from "no such product", which is a
/// normal answer and returns null.
class BarcodeLookupException implements Exception {
  const BarcodeLookupException();
}

/// Looks packaged food up by barcode in Open Food Facts, the open product
/// database (https://world.openfoodfacts.org, data under the ODbL).
///
/// Only the barcode itself is sent. No account, profile or health data leaves
/// the device for this, and the request carries no user identifier.
class OpenFoodFactsService {
  OpenFoodFactsService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _fields = 'product_name,product_name_en,generic_name,brands,'
      'nutriments,serving_quantity,serving_size,quantity';

  /// Retail barcodes only: EAN-8, UPC-A / EAN-13 and the rare 14-digit GTIN.
  /// Anything else on a pack (a QR code, a batch number) is not a product id.
  static bool isProductBarcode(String code) =>
      RegExp(r'^\d{8}$|^\d{12,14}$').hasMatch(code);

  /// The product for [barcode], or null if Open Food Facts does not have it
  /// (or has it without nutrition values).
  ///
  /// Throws [BarcodeLookupException] when the lookup itself failed.
  Future<BarcodeProduct?> lookup(String barcode) async {
    final uri = Uri.https(
      'world.openfoodfacts.org',
      '/api/v2/product/$barcode.json',
      {'fields': _fields},
    );

    final http.Response res;
    try {
      res = await _client.get(uri, headers: const {
        // Open Food Facts asks every client to identify itself by app name.
        'User-Agent': 'Proteinix/1.0 (Android)',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));
    } catch (_) {
      throw const BarcodeLookupException();
    }

    // The API answers 404 for an unknown barcode on v2.
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw const BarcodeLookupException();

    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! Map<String, dynamic>) return null;
      final product = json['product'];
      if (json['status'] != 1 || product is! Map<String, dynamic>) return null;
      return BarcodeProduct.fromOpenFoodFacts(barcode, product);
    } catch (_) {
      throw const BarcodeLookupException();
    }
  }
}
