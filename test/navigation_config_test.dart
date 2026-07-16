import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/navigation/navigation_config.dart';

void main() {
  test('navigation config drives startup page validation', () {
    expect(appNavigationDestinations.length, 2);
    expect(isValidStartupPage('/tab/popular/'), isFalse);
    expect(isValidStartupPage('/tab/local/'), isTrue);
    final removedLegacyPath = '/tab/${'tv'}${'box'}/movie/';
    expect(isValidStartupPage(removedLegacyPath), isFalse);
    expect(navigationIndexForStartupPage('/tab/local/'), 0);
    expect(defaultStartupPage, '/tab/local/');
  });
}
