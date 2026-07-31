import 'package:flutter_test/flutter_test.dart';

import 'package:drip/sample_data.dart';

void main() {
  test('product search supports natural multiword queries', () {
    final runner = products.first;

    expect(runner.matches('black runner'), isTrue);
    expect(runner.matches('nike size-does-not-exist'), isFalse);
  });

  test('product search includes description, size, and price', () {
    final runner = products.first;

    expect(runner.matches(runner.sizes.first), isTrue);
    expect(runner.matches(runner.price.toStringAsFixed(0)), isTrue);
    expect(runner.matches(runner.description.split(' ').first), isTrue);
  });
}
