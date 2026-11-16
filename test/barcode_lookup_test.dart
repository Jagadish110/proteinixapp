import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proteinix/services/open_food_facts_service.dart';

Map<String, dynamic> offProduct({
  Map<String, dynamic>? nutriments,
  String? name = 'Masala Oats',
  String? brands = 'Saffola, Marico',
  Object? servingQuantity = 40,
  String? servingSize = '40 g',
}) =>
    {
      if (name != null) 'product_name': name,
      if (brands != null) 'brands': brands,
      if (servingQuantity != null) 'serving_quantity': servingQuantity,
      if (servingSize != null) 'serving_size': servingSize,
      'nutriments': nutriments ??
          {
            'energy-kcal_100g': 380,
            'proteins_100g': 11.5,
            'carbohydrates_100g': 66,
            'fat_100g': 7.2,
            'fiber_100g': 9,
          },
    };

void main() {
  group('BarcodeProduct.fromOpenFoodFacts', () {
    test('reads the label values per 100 g', () {
      final p = BarcodeProduct.fromOpenFoodFacts('8901088136808', offProduct())!;
      expect(p.name, 'Masala Oats');
      expect(p.brand, 'Saffola');
      expect(p.kcalPer100, 380);
      expect(p.proteinPer100, 11.5);
      expect(p.servingSize, 40);
      expect(p.unit, 'g');
      expect(p.displayName, 'Masala Oats · Saffola');
    });

    test('scales to the quantity eaten', () {
      final p = BarcodeProduct.fromOpenFoodFacts('1', offProduct())!;
      final m = p.forQuantity(40);
      expect(m.kcal, 152);
      expect(m.protein, closeTo(4.6, 0.001));
      expect(m.carbs, closeTo(26.4, 0.001));
      expect(m.fat, closeTo(2.88, 0.001));
      expect(m.fiber, closeTo(3.6, 0.001));
    });

    test('converts energy published only in kJ', () {
      final p = BarcodeProduct.fromOpenFoodFacts(
          '1', offProduct(nutriments: {'energy_100g': 1590}))!;
      expect(p.kcalPer100, closeTo(380, 0.5));
    });

    test('missing macros read as zero rather than failing the product', () {
      final p = BarcodeProduct.fromOpenFoodFacts(
          '1', offProduct(nutriments: {'energy-kcal_100g': 42}))!;
      expect(p.proteinPer100, 0);
      expect(p.fiberPer100, 0);
    });

    test('accepts numbers that arrive as strings', () {
      final p = BarcodeProduct.fromOpenFoodFacts(
          '1',
          offProduct(
            nutriments: {'energy-kcal_100g': '250', 'proteins_100g': '8.5'},
            servingQuantity: '30',
          ))!;
      expect(p.kcalPer100, 250);
      expect(p.proteinPer100, 8.5);
      expect(p.servingSize, 30);
    });

    test('a product with no energy figure is treated as not found', () {
      expect(
          BarcodeProduct.fromOpenFoodFacts(
              '1', offProduct(nutriments: {'proteins_100g': 5})),
          isNull);
      expect(
          BarcodeProduct.fromOpenFoodFacts(
              '1', {'product_name': 'Mystery'}),
          isNull);
    });

    test('a product with no name is treated as not found', () {
      expect(BarcodeProduct.fromOpenFoodFacts('1', offProduct(name: null)),
          isNull);
    });

    test('drinks are measured in millilitres', () {
      final p = BarcodeProduct.fromOpenFoodFacts(
          '1', offProduct(servingSize: '200 ml', servingQuantity: 200))!;
      expect(p.isLiquid, isTrue);
      expect(p.unit, 'ml');
    });

    test('no brand leaves the name alone', () {
      final p =
          BarcodeProduct.fromOpenFoodFacts('1', offProduct(brands: null))!;
      expect(p.displayName, 'Masala Oats');
    });
  });

  group('OpenFoodFactsService', () {
    test('only retail barcodes count as product codes', () {
      expect(OpenFoodFactsService.isProductBarcode('8901088136808'), isTrue);
      expect(OpenFoodFactsService.isProductBarcode('96385074'), isTrue);
      expect(OpenFoodFactsService.isProductBarcode('012345678905'), isTrue);
      expect(OpenFoodFactsService.isProductBarcode('https://x.y'), isFalse);
      expect(OpenFoodFactsService.isProductBarcode('12345'), isFalse);
      expect(OpenFoodFactsService.isProductBarcode(''), isFalse);
    });

    test('sends the barcode and nothing about the user', () async {
      late http.Request seen;
      final service = OpenFoodFactsService(client: MockClient((req) async {
        seen = req;
        return http.Response(
            jsonEncode({'status': 1, 'product': offProduct()}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }));

      final p = await service.lookup('8901088136808');

      expect(p?.name, 'Masala Oats');
      expect(seen.url.host, 'world.openfoodfacts.org');
      expect(seen.url.path, '/api/v2/product/8901088136808.json');
      expect(seen.url.queryParameters.keys, ['fields']);
      expect(seen.headers.containsKey('authorization'), isFalse);
      expect(seen.body, isEmpty);
    });

    test('an unknown barcode is null, not an error', () async {
      final byStatus = OpenFoodFactsService(
          client: MockClient((_) async => http.Response(
              jsonEncode({'status': 0, 'status_verbose': 'product not found'}),
              200)));
      expect(await byStatus.lookup('00000000'), isNull);

      final by404 = OpenFoodFactsService(
          client: MockClient((_) async => http.Response('{}', 404)));
      expect(await by404.lookup('00000000'), isNull);
    });

    test('a failed request is reported as a failure, not as "not found"',
        () async {
      final down = OpenFoodFactsService(
          client: MockClient((_) async => http.Response('oops', 503)));
      expect(() => down.lookup('8901088136808'),
          throwsA(isA<BarcodeLookupException>()));

      final offline = OpenFoodFactsService(
          client: MockClient((_) async => throw Exception('no network')));
      expect(() => offline.lookup('8901088136808'),
          throwsA(isA<BarcodeLookupException>()));

      final garbage = OpenFoodFactsService(
          client: MockClient((_) async => http.Response('<html>', 200)));
      expect(() => garbage.lookup('8901088136808'),
          throwsA(isA<BarcodeLookupException>()));
    });
  });
}
