import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/recovery/domain/dose_units.dart';

void main() {
  group('parseAmount', () {
    test('decimals, comma decimals and fractions', () {
      expect(parseAmount('2.5'), 2.5);
      expect(parseAmount('2,5'), 2.5);
      expect(parseAmount(' .5 '), .5);
      expect(parseAmount(',25'), .25);
      expect(parseAmount('1/2'), .5);
      expect(parseAmount('3 / 4'), .75);
      expect(parseAmount('1 1/2'), 1.5);
      expect(parseAmount('1½'), 1.5);
      expect(parseAmount('2 and a half'), 2.5);
      expect(parseAmount('half'), .5);
      expect(parseAmount('Quarter'), .25);
      expect(parseAmount('three quarters'), .75);
      expect(parseAmount('250'), 250);
    });

    test('zero, negative, ambiguous and junk are rejected', () {
      for (final bad in [
        '',
        '0',
        '0.0',
        '-1',
        '-2.5',
        '1/0',
        '0/4',
        '1,000', // thousands separator or 1.000? Refuse to guess.
        '1,2,3',
        '1.2.3',
        'lots',
        '2 bottles', // unit belongs in parseQuantityText
        'NaN',
        'Infinity',
      ]) {
        expect(parseAmount(bad), isNull, reason: bad);
      }
    });
  });

  group('parseMoney', () {
    test('rupee formats', () {
      expect(parseMoney('450'), 450);
      expect(parseMoney('₹1,200'), 1200);
      expect(parseMoney('Rs. 1,20,000'), 120000);
      expect(parseMoney('INR 99.50'), 99.5);
      expect(parseMoney('99,5'), 99.5);
      expect(parseMoney('0'), 0);
    });

    test('negatives and junk are rejected', () {
      expect(parseMoney('-50'), isNull);
      expect(parseMoney('abc'), isNull);
      expect(parseMoney(''), isNull);
    });
  });

  group('conversion', () {
    test('ml maths with the bottle size', () {
      expect(toMl(250, DoseUnit.ml, bottleMl: 100), 250);
      expect(toMl(1.5, DoseUnit.litre, bottleMl: 100), 1500);
      expect(toMl(2.5, DoseUnit.bottle, bottleMl: 100), 250);
      expect(toMl(2, DoseUnit.bottle, bottleMl: 120), 240);
      expect(toMl(2, DoseUnit.tablet, bottleMl: 100), isNull);
      expect(toMl(3, DoseUnit.drink, bottleMl: 100), isNull);
    });

    test('entered dose stores amount, unit, ml and the bottle size', () {
      final dose = DoseAmount.entered(2.5, DoseUnit.bottle, bottleMl: 100);
      expect(dose.toMetadata(), {
        'amount': 2.5,
        'unit': 'bottle',
        'amountMl': 250.0,
        'bottleMl': 100.0,
      });
      final tablets = DoseAmount.entered(2, DoseUnit.tablet, bottleMl: 100);
      expect(tablets.toMetadata(), {'amount': 2.0, 'unit': 'tablet'});
    });

    test('changing the bottle size does not rewrite a stored dose', () {
      final stored = DoseAmount.entered(
        2,
        DoseUnit.bottle,
        bottleMl: 100,
      ).toMetadata();
      // The user later switches to 250 ml bottles; reading uses stored ml.
      final read = DoseAmount.fromMetadata(stored)!;
      expect(read.amountMl, 200);
      expect(read.bottleMl, 100);
      expect(
        DoseAmount.entered(2, DoseUnit.bottle, bottleMl: 250).amountMl,
        500,
      );
    });

    test('zero, negative and absurd entries throw', () {
      expect(
        () => DoseAmount.entered(0, DoseUnit.ml, bottleMl: 100),
        throwsArgumentError,
      );
      expect(
        () => DoseAmount.entered(-1, DoseUnit.tablet, bottleMl: 100),
        throwsArgumentError,
      );
      expect(
        () => DoseAmount.entered(double.nan, DoseUnit.ml, bottleMl: 100),
        throwsArgumentError,
      );
      expect(
        () => DoseAmount.entered(25, DoseUnit.litre, bottleMl: 100),
        throwsArgumentError,
      );
      expect(
        () => DoseAmount.entered(1, DoseUnit.bottle, bottleMl: 0),
        throwsArgumentError,
      );
    });
  });

  group('parseQuantityText (legacy free text)', () {
    test('converts only exact matches', () {
      DoseAmount? parse(String text) => parseQuantityText(text, bottleMl: 100);
      expect(parse('250ml')!.amountMl, 250);
      expect(parse('250 ML')!.amountMl, 250);
      expect(parse('0.5 l')!.amountMl, 500);
      expect(parse('1,5 litres')!.amountMl, 1500);
      expect(parse('2.5 bottles')!.amountMl, 250);
      expect(parse('half a bottle')!.amountMl, 50);
      expect(parse('1/2 bottle')!.amountMl, 50);
      expect(parse('a bottle')!.amountMl, 100);
      expect(parse('2 tablets')!.unit, DoseUnit.tablet);
      expect(parse('2 tablets')!.amountMl, isNull);
      expect(parse('3 drinks')!.unit, DoseUnit.drink);
    });

    test('everything else stays as text', () {
      for (final text in [
        'half a cup',
        'a lot',
        'some',
        '2',
        '250ml and 2 tablets',
        '0 ml',
        '-1 bottle',
        '1,000 ml',
        'bottle',
      ]) {
        expect(parseQuantityText(text, bottleMl: 100), isNull, reason: text);
      }
    });
  });

  group('sanity prompts', () {
    DoseSanityCheck? check(double amount, DoseUnit unit) =>
        doseSanityCheck(amount, unit, bottleMl: 100);

    test('250 bottles suggests ml', () {
      final result = check(250, DoseUnit.bottle)!;
      expect(result.suggestedUnit, DoseUnit.ml);
      expect(result.message, contains('Did you mean 250 ml?'));
    });

    test('0.25 ml suggests litres; whole tiny ml suggests bottles', () {
      expect(check(.25, DoseUnit.ml)!.suggestedUnit, DoseUnit.litre);
      expect(check(2, DoseUnit.ml)!.suggestedUnit, DoseUnit.bottle);
    });

    test('12 L suggests ml; implausible counts warn', () {
      expect(check(12, DoseUnit.litre)!.suggestedUnit, DoseUnit.ml);
      expect(check(40, DoseUnit.tablet)!.suggestedUnit, isNull);
      expect(check(31, DoseUnit.drink), isNotNull);
    });

    test('plausible entries pass', () {
      expect(check(250, DoseUnit.ml), isNull);
      expect(check(2.5, DoseUnit.bottle), isNull);
      expect(check(.5, DoseUnit.litre), isNull);
      expect(check(2, DoseUnit.tablet), isNull);
      expect(check(4, DoseUnit.drink), isNull);
    });
  });

  test('display rounds only for display', () {
    expect(formatAmount(2.5), '2.5');
    expect(formatAmount(2), '2');
    expect(formatAmount(1 / 3), '0.33');
    expect(formatMl(250), '250 ml');
    expect(formatMl(7.25), '7.3 ml');
    expect(formatMl(1250), '1.25 L');
    expect(
      DoseAmount.entered(2.5, DoseUnit.bottle, bottleMl: 100).display,
      '2.5 bottles · 250 ml',
    );
    expect(
      DoseAmount.entered(1 / 3, DoseUnit.litre, bottleMl: 100).amountMl,
      closeTo(333.333, .001),
    );
  });
}
