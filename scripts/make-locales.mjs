#!/usr/bin/env node
// Builds the on-demand language packs and the class the app reads them through.
//
//   mobile_flutter/lib/l10n/app_en.arb        compiled into the app by gen-l10n
//   mobile_flutter/lib/l10n/packs/app_xx.arb  published as public/locales/xx.json
//
// A pack is a `key → template` map. Anything a pack leaves out falls back to the
// bundled English message, so a partial translation can be published safely.
//
// Run from the repository root:  node scripts/make-locales.mjs
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const l10nDir = path.join(root, 'mobile_flutter', 'lib', 'l10n');
const packsDir = path.join(l10nDir, 'packs');
const outDir = path.join(root, 'public', 'locales');
const readerPath = path.join(l10nDir, 'app_localizations_pack.dart');

const template = JSON.parse(
  fs.readFileSync(path.join(l10nDir, 'app_en.arb'), 'utf8'),
);
const keys = Object.keys(template).filter(
  (key) => !key.startsWith('@') && typeof template[key] === 'string',
);

// The runtime reader resolves the one ICU form the app uses — `{count, plural,
// …}` — and substitutes {placeholders}. A select or selectordinal (a choice
// that is not a count) still has no runtime support, so it is refused here
// rather than shipped as visible syntax.
const UNSUPPORTED = /\{\s*\w+\s*,\s*(select|selectordinal)\s*,/;
for (const key of keys) {
  if (UNSUPPORTED.test(template[key])) {
    throw new Error(
      `app_en.arb:${key} uses an ICU select. Extend ` +
        'AppLocalizationsPack._fill before publishing this message.',
    );
  }
}

const dartType = (type) =>
  ({ String: 'String', int: 'int', double: 'double', num: 'num', DateTime: 'DateTime' })[
    type
  ] ?? 'String';

const placeholders = (text) => [
  ...new Set([
    ...[...text.matchAll(/\{(\w+)\}/g)].map((match) => match[1]),
    // `{count, plural, …}` names its argument before the comma. A pack that
    // still holds the plain English shape ("{count} trades") uses the same
    // argument, so both spellings count as the same use of the placeholder.
    ...[...text.matchAll(/\{\s*(\w+)\s*,\s*plural\s*,/g)].map(
      (match) => match[1],
    ),
  ]),
];

// --- 1. the runtime reader -------------------------------------------------
const out = [
  '// GENERATED FILE — do not edit by hand.',
  '// Regenerate with `node scripts/make-locales.mjs` from lib/l10n/app_en.arb.',
  "import 'package:flutter/widgets.dart';",
  '',
  "import 'gen/app_localizations.dart';",
  "import 'gen/app_localizations_en.dart';",
  '',
  '/// Strings served from a downloaded language pack.',
  '///',
  '/// A pack is a key → template map. A key it leaves out falls back to the',
  '/// bundled English message, so a partial translation is always safe to ship.',
  'class AppLocalizationsPack extends AppLocalizations {',
  '  AppLocalizationsPack(Locale locale, Map<String, String> messages)',
  '      : _messages = messages,',
  '        super(locale.languageCode);',
  '',
  '  final Map<String, String> _messages;',
  '',
  '  static final AppLocalizations _en = AppLocalizationsEn();',
  '',
  '  String? _read(String key) => _messages[key];',
  '',
  '  /// Substitutes `{name}` with a value the screen already formatted, so',
  '  /// money, percentages and dates keep the shape the caller chose, and',
  '  /// resolves the one ICU form the app uses — `{count, plural, …}`.',
  '  ///',
  '  /// A pack is generated from the English ARB, so a translated pack can hold',
  '  /// either the English plural shape or a plain template; both render here.',
  '  static String _fill(String template, Map<String, Object?> values) {',
  '    var text = template;',
  '    for (var pass = 0; pass < 5; pass++) {',
  '      final plural = _icuPlural.firstMatch(text);',
  '      if (plural == null) break;',
  '      final name = plural.group(1)!;',
  '      var open = plural.start;',
  '      if (open < 0) break;',
  '      var depth = 0;',
  '      var close = open;',
  '      for (; close < text.length; close++) {',
  "        if (text[close] == '{') depth++;",
  "        if (text[close] == '}') {",
  '          depth--;',
  '          if (depth == 0) break;',
  '        }',
  '      }',
  '      if (close >= text.length) break;',
  '      final count = (values[name] as num?)?.toInt() ?? 0;',
  '      final body = text.substring(plural.end, close);',
  '      text = text.replaceRange(plural.start, close + 1, _pluralChoice(body, count));',
  '    }',
  '    for (final entry in values.entries) {',
  "      text = text.replaceAll('{${entry.key}}', '${entry.value}');",
  '    }',
  '    return text;',
  '  }',
  '',
  '  /// The start of a plural construct: `{count, plural,` in any position.',
  '  static final RegExp _icuPlural =',
  "      RegExp(r'\\{\\s*(\\w+)\\s*,\\s*plural\\s*,', dotAll: true);",
  '',
  '  /// The option that applies to [count]: an exact `=N` first, then `one` for',
  '  /// a count of one, then `other`.',
  '  static String _pluralChoice(String body, int count) {',
  '    final options = <String, String>{};',
  '    var i = 0;',
  '    while (i < body.length) {',
  '      final key = _pluralOption.matchAsPrefix(body, i);',
  '      if (key == null) {',
  '        i++;',
  '        continue;',
  '      }',
  '      var open = key.end;',
  '      while (open < body.length && body[open].trim().isEmpty) {',
  '        open++;',
  '      }',
  "      if (open >= body.length || body[open] != '{') {",
  '        i = key.end;',
  '        continue;',
  '      }',
  '      var depth = 0;',
  '      var close = open;',
  '      for (; close < body.length; close++) {',
  "        if (body[close] == '{') depth++;",
  "        if (body[close] == '}') {",
  '          depth--;',
  '          if (depth == 0) break;',
  '        }',
  '      }',
  '      if (close >= body.length) break;',
  '      options[key.group(0)!] = body.substring(open + 1, close);',
  '      i = close + 1;',
  '    }',
  "    return options['=$count'] ??",
  "        options[count == 1 ? 'one' : 'other'] ??",
  "        options['other'] ??",
  "        '';",
  '  }',
  '',
  '  static final RegExp _pluralOption =',
  "      RegExp(r'(=\\d+|zero|one|two|few|many|other)');",
];

for (const key of keys) {
  const meta = template[`@${key}`]?.placeholders ?? {};
  const names = Object.keys(meta);
  if (names.length === 0) {
    out.push('', '  @override', `  String get ${key} => _read('${key}') ?? _en.${key};`);
    continue;
  }
  const signature = names.map((name) => `${dartType(meta[name].type)} ${name}`).join(', ');
  const values = names.map((name) => `'${name}': ${name}`).join(', ');
  out.push(
    '',
    '  @override',
    `  String ${key}(${signature}) {`,
    `    final template = _read('${key}');`,
    `    if (template == null) return _en.${key}(${names.join(', ')});`,
    `    return _fill(template, <String, Object?>{${values}});`,
    '  }',
  );
}
out.push('}', '');
fs.writeFileSync(readerPath, out.join('\n'));

// --- 2. published packs ----------------------------------------------------
fs.mkdirSync(outDir, { recursive: true });
const produced = new Set(['manifest.json']);
const manifest = [];

for (const file of fs
  .readdirSync(packsDir)
  .filter((name) => name.endsWith('.arb'))
  .sort()) {
  const arb = JSON.parse(fs.readFileSync(path.join(packsDir, file), 'utf8'));
  const code = arb['@@locale'];
  if (!code) throw new Error(`${file}: missing @@locale`);
  if (code === 'en') continue;

  for (const key of Object.keys(arb)) {
    if (key.startsWith('@')) continue;
    if (!keys.includes(key)) {
      throw new Error(`${file}: "${key}" is not a message in app_en.arb`);
    }
  }

  const messages = {};
  for (const key of keys) {
    if (typeof arb[key] === 'string') messages[key] = arb[key];
  }
  if (Object.keys(messages).length === 0) continue;

  for (const [key, value] of Object.entries(messages)) {
    const expected = placeholders(template[key]).sort().join(',');
    const actual = placeholders(value).sort().join(',');
    if (expected !== actual) {
      throw new Error(
        `${file}: "${key}" uses {${actual}} but app_en.arb uses {${expected}}`,
      );
    }
  }

  const version = parseInt(
    crypto.createHash('sha256').update(JSON.stringify(messages)).digest('hex').slice(0, 8),
    16,
  );
  const body = JSON.stringify({ code, version, messages });
  fs.writeFileSync(path.join(outDir, `${code}.json`), body);
  produced.add(`${code}.json`);
  manifest.push({
    code,
    version,
    bytes: Buffer.byteLength(body),
    keys: Object.keys(messages).length,
  });
}

// A language that lost its pack must stop being advertised.
for (const file of fs.readdirSync(outDir)) {
  if (file.endsWith('.json') && !produced.has(file)) {
    fs.rmSync(path.join(outDir, file));
  }
}
fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify({ packs: manifest }));

const summary = manifest
  .map((pack) => `${pack.code} (${pack.keys} keys, ${pack.bytes} B)`)
  .join(', ');
console.log(
  `app_localizations_pack.dart: ${keys.length} messages\n` +
    `public/locales: ${manifest.length} pack(s) — ${summary || 'none'}`,
);
