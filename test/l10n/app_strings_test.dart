// Copyright (c) 2026 Chris Coetzee
// SPDX-License-Identifier: MIT
// The full license text is in LICENSE at the repository root.

import 'package:dji_mic_control/l10n/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppStrings localization (upstream PR #3)', () {
    test('normalizes locale to en or zh-CN', () {
      expect(AppStrings.normalizeLocale(null), 'en');
      expect(AppStrings.normalizeLocale(''), 'en');
      expect(AppStrings.normalizeLocale('en'), 'en');
      expect(AppStrings.normalizeLocale('zh-CN'), 'zh-CN');
      expect(AppStrings.normalizeLocale('fr-FR'), 'en');
    });

    test('translates known keys for zh-CN and falls back to English', () {
      expect(AppStrings.tr('en', 'SETTINGS'), 'SETTINGS');
      expect(AppStrings.tr('zh-CN', 'SETTINGS'), '设置');
      expect(AppStrings.tr('zh-CN', 'Receiver Gain'), '接收器增益');
      expect(AppStrings.tr('zh-CN', 'Monitoring Gain'), '监听增益');
      expect(AppStrings.tr('zh-CN', 'Untranslated literal'), 'Untranslated literal');
    });

    test('interpolates named parameters', () {
      expect(
        AppStrings.tr('en', 'Turn off "{name}" first', <String, Object>{'name': 'Safety Track'}),
        'Turn off "Safety Track" first',
      );
      expect(
        AppStrings.tr('zh-CN', 'Turn off "{name}" first', <String, Object>{'name': '安全音轨'}),
        '请先关闭“安全音轨”',
      );
    });
  });
}
