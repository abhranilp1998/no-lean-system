import 'package:flutter_test/flutter_test.dart';
import 'package:no_lean/features/zones/presentation/offline_grid_layer.dart';

void main() {
  test('grid step keeps lines at least ~90 px apart', () {
    expect(gridStepDegrees(100000), 0.001);
    expect(gridStepDegrees(5), 20);
    expect(gridStepDegrees(1000) * 1000, greaterThanOrEqualTo(90));
  });

  test('scale bar rounds down to 1/2/5 steps', () {
    expect(niceScaleMeters(730), 500);
    expect(niceScaleMeters(1900), 1000);
    expect(niceScaleMeters(260), 200);
    expect(niceScaleMeters(0), 0);
  });
}
