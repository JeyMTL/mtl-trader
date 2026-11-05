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

// The runtime reader substitutes {placeholders}; it does not implement ICU
// plural/select. Refusing here is better than shipping a message that renders
// its own syntax on screen.
const COMPLEX = /\{\s*\w+\s*,\s*(plural|select|selectordinal)\s*,/;
for (const key of keys) {
  if (COMPLEX.test(template[key])) {
    throw new Error(
      `app_en.arb:${key} uses an ICU plural/select. Extend ` +
        'AppLocalizationsPack._fill before publishing this message.',
    );
  }
}

const dartType = (type) =>
  ({ String: 'String', int: 'int', double: 'double', num: 'num', DateTime: 'DateTime' })[
    type
  ] ?? 'String';

const placeholders = (text) => [
  ...new Set([...text.matchAll(/\{(\w+)\}/g)].map((match) => match[1])),
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
  '  /// money, percentages and dates keep the shape the caller chose.',
  '  static String _fill(String template, Map<String, Object?> values) {',
  '    var text = template;',
  '    for (final entry in values.entries) {',
  "      text = text.replaceAll('{${entry.key}}', '${entry.value}');",
  '    }',
  '    return text;',
  '  }',
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
