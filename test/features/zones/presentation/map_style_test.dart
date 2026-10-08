import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/core/theme/app_theme.dart';
import 'package:no_lean/features/zones/presentation/map_style.dart';

void main() {
  double luminance(Color c) => c.computeLuminance();

  test('neon matrix turns light OSM land dark and dark labels bright', () {
    const land = Color(0xFFF2EFE9); // OSM background
    const label = Color(0xFF333333); // OSM text
    const water = Color(0xFFAAD3DF);
    final darkLand = applyColorMatrix(noLeanTileMatrix, land);
    final brightLabel = applyColorMatrix(noLeanTileMatrix, label);
    final darkWater = applyColorMatrix(noLeanTileMatrix, water);

    expect(luminance(darkLand), lessThan(.03));
    expect(luminance(brightLabel), greaterThan(.4));
    expect(luminance(darkWater), greaterThan(luminance(darkLand)));
    // Cyan-tinted: blue/green dominate red after restyling.
    expect(brightLabel.b, greaterThan(brightLabel.r));
    expect(brightLabel.g, greaterThan(brightLabel.r));
    // Alpha passes through untouched.
    expect(applyColorMatrix(noLeanTileMatrix, land).a, 1);
  });

  test('pure white lifts to the app ink, not absolute black', () {
    final white = applyColorMatrix(noLeanTileMatrix, Colors.white);
    expect((white.r * 255).round(), (ink.r * 255).round());
    expect((white.b * 255).round(), (ink.b * 255).round());
  });
}
