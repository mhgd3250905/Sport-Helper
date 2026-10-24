import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/ui/legal_policy_page.dart';

void main() {
  test('policy navigation permits policy translations but rejects escapes', () {
    for (final url in [
      'https://smartfit-store.pages.dev/privacy/',
      'https://smartfit-store.pages.dev/privacy/en/',
      'https://smartfit-store.pages.dev/terms/',
      'https://smartfit-store.pages.dev/support/',
    ]) {
      expect(permitsLegalPolicyNavigation(url), isTrue, reason: url);
    }
    for (final url in [
      'http://smartfit-store.pages.dev/privacy/',
      'https://smartfit-store.pages.dev.evil.example/privacy/',
      'https://other.pages.dev/',
      'https://user@smartfit-store.pages.dev/privacy/',
      'https://smartfit-store.pages.dev:8443/privacy/',
      'file:///private/record.json',
      'javascript:alert(1)',
      'mailto:mhgd3250905@gmail.com',
    ]) {
      expect(permitsLegalPolicyNavigation(url), isFalse, reason: url);
    }
  });
}
