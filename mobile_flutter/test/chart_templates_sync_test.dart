import 'package:flutter_test/flutter_test.dart';
import 'package:mtl_trader_mobile/core/chart_presets.dart';
import 'package:mtl_trader_mobile/core/chart_theme.dart';
import 'package:mtl_trader_mobile/services/chart_templates_sync.dart';

ChartPreset preset(String name, {int? editedAtMs, ChartStyle? style}) =>
    ChartPreset(
      name: name,
      style: style ?? ChartStyle.ink,
      editedAtMs: editedAtMs,
    );

void main() {
  group('template slugs', () {
    test('name identity ignores case and padding, like the server column', () {
      expect(ChartTemplatesSync.slugFor('  MTL '), 'mtl');
      expect(ChartTemplatesSync.slugFor('mtl'), 'mtl');
      expect(ChartTemplatesSync.slugFor('Night'), 'night');
    });
  });

  group('merging the phone with the account', () {
    test('unions both lists and lets the later edit win', () {
      final local = [
        preset('MTL', editedAtMs: 3000, style: ChartStyle.ink),
        preset('Dawn', editedAtMs: 500),
      ];
      final remote = {
        'mtl': preset('MTL', editedAtMs: 2000, style: ChartStyle.ink),
        'night': preset('Night', editedAtMs: 1000),
      };

      final merged = ChartTemplatesSync.mergePresets(local, remote);

      expect(merged.map((entry) => entry.name), ['MTL', 'Night', 'Dawn']);
      // The local MTL is newer, so its stamp stands.
      expect(merged.first.editedAtMs, 3000);
    });

    test('an account copy edited later replaces the device copy', () {
      final local = [preset('MTL', editedAtMs: 1000)];
      final remote = {'mtl': preset('MTL', editedAtMs: 9000)};

      final merged = ChartTemplatesSync.mergePresets(local, remote);

      expect(merged.single.editedAtMs, 9000);
    });

    test('a tie keeps the device copy, so the two desks agree', () {
      final local = [preset('MTL', editedAtMs: 1000)];
      final remote = {'mtl': preset('mtl', editedAtMs: 1000)};

      final merged = ChartTemplatesSync.mergePresets(local, remote);

      expect(merged.single.name, 'MTL');
    });

    test('an offline device keeps its own list when there is no account row', () {
      final local = [preset('MTL', editedAtMs: 10), preset('Night')];
      final merged = ChartTemplatesSync.mergePresets(local, const {});
      expect(merged.length, 2);
    });

    test('a remote row is read back in the shared vocabulary', () {
      final read = ChartTemplatesSync.presetFromRow(<String, dynamic>{
        'name': ' MTL ',
        'style': ChartStyle.ink.toJson(),
        'edited_at': '2026-11-22T18:00:00.000Z',
      });

      expect(read, isNotNull);
      expect(read!.name, 'MTL');
      expect(read.editedAtMs, DateTime.parse('2026-11-22T18:00:00.000Z').millisecondsSinceEpoch);
      expect(read.style.bull, ChartStyle.ink.bull);
    });

    test('a row without a usable name is ignored rather than guessed at', () {
      expect(
        ChartTemplatesSync.presetFromRow(<String, dynamic>{'name': '   '}),
        isNull,
      );
      expect(ChartTemplatesSync.presetFromRow(const <String, dynamic>{}), isNull);
    });
  });

  group('preset edit times', () {
    test('round-trip through the device copy', () {
      final stored = preset('MTL', editedAtMs: 1763000000000);
      final read = ChartPreset.fromJson(stored.toJson());
      expect(read?.editedAtMs, 1763000000000);
    });

    test('a preset saved before sharing has no stamp and still loads', () {
      final read = ChartPreset.fromJson(<String, Object?>{
        'name': 'Old',
        'style': ChartStyle.ink.toJson(),
      });
      expect(read, isNotNull);
      expect(read!.editedAtMs, isNull);
    });
  });
}
