import 'package:flutter_test/flutter_test.dart';
import 'package:scontrini/version.dart';

void main() {
  test('build locale', () => expect(versionLabel(version: '', build: ''), 'sviluppo'));
  test('build di CI', () => expect(versionLabel(version: '2026.11.5', build: '57'), '2026.11.5 (build 57)'));
  test('senza numero di build', () => expect(versionLabel(version: '2026.11.5', build: ''), '2026.11.5'));
  test('nei test non ci sono --dart-define', () => expect(versionLabel(), 'sviluppo'));
}
