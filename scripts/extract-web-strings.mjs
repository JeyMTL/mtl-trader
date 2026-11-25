#!/usr/bin/env node
// Builds the English catalog used by the web translation layer.
//
// The web app predates a message catalog, so strings are harvested from the
// source instead of being hand-copied into a second list that would drift. The
// runtime translates rendered text and attributes by exact phrase, so every
// key here has to be the phrase a user actually sees.
//
//   node scripts/extract-web-strings.mjs
import fs from 'node:fs'
import path from 'node:path'
import parser from '@babel/parser'
import traverseModule from '@babel/traverse'

const traverse = traverseModule.default ?? traverseModule

const root = path.resolve(import.meta.dirname, '..')
const outFile = path.join(root, 'public', 'locales', 'web', 'en.json')

const displayKeys = new Set([
  'action',
  'answer',
  'caption',
  'confirmText',
  'cancelText',
  'cta',
  'description',
  'detail',
  'empty',
  'emptyText',
  'heading',
  'helper',
  'hint',
  'label',
  'message',
  'name',
  'placeholder',
  'question',
  'subtitle',
  'summary',
  'tagline',
  'text',
  'title',
])

const textAttributes = new Set([
  'alt',
  'aria-label',
  'cancelLabel',
  'confirmLabel',
  'description',
  'emptyMessage',
  'heading',
  'helper',
  'hint',
  'label',
  'message',
  'placeholder',
  'subtitle',
  'tagline',
  'title',
])

const skipElements = new Set(['code', 'pre', 'script', 'style'])

const codeLike = [
  /^[a-z][a-z0-9_-]*$/,
  /https?:\/\//i,
  /^mailto:/i,
  /^@\//,
  /^\/[a-z]/i,
  /^[.#][a-z]/i,
  /className/,
  /var\(--/,
  /=>/,
  /&&|\|\|/,
  /process\./,
  /localStorage|sessionStorage/,
  /supabase/i,
  /content-type|application\/json|text\/|image\/|audio\//i,
  /^select |^insert |^update |^delete from /i,
  /\bpx\b|\brem\b|\bvh\b|\bvw\b/,
  /[{}]/,
  /[\\<>]/,
  /^[\d\s.,:%$+\-–—/()]+$/,
  /^-?\d*\.?\d+(?:em|rem|px|vh|vw|%)$/,
  /^(?:rgb|hsl|var|calc)\(/,
  /^#[0-9a-f]{3,8}$/i,
  /^\d+(?:\.\d+)?[A-Za-z%]?$/,
  /^[A-Z0-9_]+(?:\.[A-Z0-9_]+)+$/,
  /^\d{4}-\d{2}-\d{2}/,
  /^T\d{2}:\d{2}/,
  /^\d+(?:\.\d+)?(?:px|rem|em|%)\s+/,
  /\d+px\s+solid\b/i,
]

function looksLikeClassList(text) {
  const tokens = text.split(' ').filter(Boolean)
  const cssToken =
    /^(?:sm:|md:|lg:|xl:|2xl:|hover:|focus:|active:|disabled:|group-|dark:|rtl:)?(?:flex|grid|block|inline|hidden|absolute|relative|fixed|sticky|h-|w-|p[trblxy]?-|m[trblxy]?-|text-|bg-|border|rounded|gap-|items-|justify-|font-|leading-|tracking-|opacity-|shadow|z-|top-|bottom-|left-|right-|inset-|overflow-|pointer-|cursor-|select-|transition|translate-|scale-|rotate-|space-|divide-|ring-|outline-|fill-|stroke-|aspect-|object-|order-|col-|row-|place-|content-|self-|basis-|grow|shrink|truncate|whitespace-|break-|uppercase|lowercase|capitalize|italic|underline|line-through|sr-only|eyebrow|prose)/
  if (tokens.some((token) => cssToken.test(token))) return true
  if (tokens.length < 2) return false
  const utilityTokens = tokens.filter((token) =>
    /^(?:sm:|md:|lg:|xl:|2xl:|hover:|focus:|active:|disabled:|group-|dark:|rtl:)?-?[a-z]+-[a-z0-9./[\]%#-]+$/.test(token)
  )
  if (tokens.length === 2) return utilityTokens.length === 2
  return utilityTokens.length >= Math.min(3, Math.ceil(tokens.length / 2))
}

const hasLetters = /[A-Za-z\u00c0-\u024f\u0370-\u03ff\u0400-\u04ff\u0590-\u05ff\u0600-\u06ff\u0900-\u097f\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]/

const strings = new Set()

function normalize(value) {
  return value.replace(/\s+/g, ' ').trim()
}

function looksUsable(value, { allowSingle = false, allowLowercase = false } = {}) {
  const text = normalize(value)
  if (text.length < 2 || !hasLetters.test(text)) return false
  if (!allowSingle && !text.includes(' ') && text.length < 4) return false
  if (looksLikeClassList(text)) return false
  if (allowLowercase && /^[a-z][a-z0-9_-]*$/.test(text)) return true
  return !codeLike.some((pattern) => pattern.test(text))
}

function add(value, options) {
  const text = normalize(value)
  if (looksUsable(text, options)) strings.add(text)
}

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name)
    if (entry.isDirectory()) walk(file)
    else if (/\.(ts|tsx)$/.test(entry.name) && !/\.test\.|\.spec\./.test(entry.name)) parse(file)
  }
}

function parse(file) {
  const source = fs.readFileSync(file, 'utf8')
  let ast
  try {
    ast = parser.parse(source, {
      sourceType: 'module',
      plugins: ['jsx', 'typescript'],
      errorRecovery: true,
    })
  } catch {
    return
  }

  traverse(ast, {
    JSXText(path) {
      const parent = path.findParent(
        (candidate) =>
          candidate.isJSXElement() &&
          skipElements.has(candidate.node.openingElement.name.name)
      )
      if (parent) return
      add(path.node.value)
    },

    JSXAttribute(path) {
      const name = path.node.name?.name
      if (typeof name !== 'string' || !textAttributes.has(name)) return
      if (path.node.value?.type !== 'StringLiteral') return
      add(path.node.value.value, { allowSingle: true, allowLowercase: true })
    },

    StringLiteral(path) {
      const value = path.node.value
      if (!value) return
      const parent = path.parentPath

      // The plan catalogue is rendered indirectly through cards, so every
      // human-readable literal in it is a potential key (IDs are filtered by
      // the lowercase-token rule).
      if (file.endsWith('plans.ts')) add(value, { allowSingle: true })

      if (parent?.isObjectProperty()) {
        const key = parent.node.key
        const keyName =
          key?.type === 'Identifier' ? key.name : key?.type === 'StringLiteral' ? key.value : null
        if (keyName && displayKeys.has(keyName)) {
          // `name: 'mt5'` and similar identifiers are not display copy.
          if (keyName === 'name' && /^[a-z0-9_-]+$/.test(value)) return
          add(value, { allowSingle: true })
        }
      }

      if (parent?.isArrayExpression()) {
        add(value)
      }

      if (parent?.isJSXExpressionContainer()) {
        add(value, { allowSingle: true })
      }

      if (path.findParent((candidate) => candidate.isJSXExpressionContainer())) {
        add(value, { allowSingle: true })
      }

      if (parent?.isCallExpression()) {
        const callee = parent.node.callee
        const name = callee?.type === 'Identifier' ? callee.name : null
        if (name && ['toast', 'setError', 'setMessage', 'setStatus', 'alert', 'fillText', 'strokeText'].includes(name)) {
          add(value, { allowSingle: true })
        }
      }
    },
  })
}

walk(path.join(root, 'src', 'app'))
walk(path.join(root, 'src', 'components'))
parse(path.join(root, 'src', 'lib', 'plans.ts'))

// Rendered from constants rather than TSX, so the AST walk cannot see them.
strings.add('Start 3-day free trial')
strings.add('3-day free trial · No credit card required · Web + Android')
// The legal authority banner is rendered by the translation layer, not a page.
strings.add('This is a machine translation. The English version is authoritative.')

const keys = [...strings].sort((a, b) => a.localeCompare(b))
const catalog = Object.fromEntries(keys.map((key) => [key, key]))
fs.mkdirSync(path.dirname(outFile), { recursive: true })
fs.writeFileSync(outFile, `${JSON.stringify(catalog, null, 2)}\n`)
console.log(`public/locales/web/en.json: ${keys.length} strings`)
console.log(keys.slice(0, 12).map((key) => `  ${key}`).join('\n'))
