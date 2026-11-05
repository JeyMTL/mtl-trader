import { readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

import { describe, expect, it } from 'vitest'

/**
 * The database is the one dependency CI cannot run. This test closes the gap
 * offline: it rebuilds the column set from the migrations in order, then checks
 * that the columns the code writes are actually defined somewhere.
 *
 * It exists because the benchmark/stress columns were added to an insert before
 * the matching migration reached every environment — a save that failed at
 * runtime and only showed up in the logs.
 */

const root = process.cwd()
const migrationsDir = join(root, 'supabase/migrations')
const migrations = readdirSync(migrationsDir)
  .filter((name) => name.endsWith('.sql'))
  .sort()

function withoutComments(sql: string): string {
  return sql.replace(/--[^\n]*/g, '')
}

/** Splits a CREATE TABLE body on top-level commas, not commas inside `(…)`. */
function splitColumns(body: string): string[] {
  const parts: string[] = []
  let depth = 0
  let current = ''
  for (const character of body) {
    if (character === '(') depth += 1
    if (character === ')') depth -= 1
    if (character === ',' && depth === 0) {
      parts.push(current)
      current = ''
      continue
    }
    current += character
  }
  parts.push(current)

  return parts
    .map((part) => part.trim())
    .filter((part) => part.length > 0)
    .filter(
      (part) =>
        !/^(constraint|primary\s+key|foreign\s+key|unique|check)\b/i.test(part)
    )
    .map((part) => part.match(/^"?([a-z_][a-z0-9_]*)"?/i)?.[1] ?? '')
    .filter((column) => column.length > 0)
}

function columnsByTable(): Map<string, Set<string>> {
  const tables = new Map<string, Set<string>>()
  const add = (table: string, column: string) => {
    const name = table.toLowerCase()
    const columns = tables.get(name) ?? new Set<string>()
    columns.add(column.toLowerCase())
    tables.set(name, columns)
  }

  for (const file of migrations) {
    const sql = withoutComments(readFileSync(join(migrationsDir, file), 'utf8'))

    const creates =
      /CREATE\s+TABLE(?:\s+IF\s+NOT\s+EXISTS)?\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\(([\s\S]*?)\n\s*\);/gi
    for (const match of sql.matchAll(creates)) {
      const [, table = '', body = ''] = match
      for (const column of splitColumns(body)) add(table, column)
    }

    // One ALTER statement can add several columns, and only the first carries
    // `ALTER TABLE`. Match the statement, then pull every ADD COLUMN out of it.
    const alterStatements =
      /ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:public\.)?([a-z_][a-z0-9_]*)([\s\S]*?);/gi
    for (const statement of sql.matchAll(alterStatements)) {
      const table = statement[1] ?? ''
      const body = statement[2] ?? ''
      const added =
        /ADD\s+COLUMN(?:\s+IF\s+NOT\s+EXISTS)?\s+"?([a-z_][a-z0-9_]*)"?/gi
      for (const column of body.matchAll(added)) {
        add(table, column[1] ?? '')
      }
    }
  }

  return tables
}

/** Column names at the top level of the backtest insert object. */
function backtestInsertColumns(): string[] {
  const route = readFileSync(
    join(root, 'src/app/api/backtest/route.ts'),
    'utf8'
  )
  const insert = route.match(
    /\.from\('backtests'\)[\s\S]*?\.insert\(\{([\s\S]*?)\n\s*\}\)/
  )
  expect(insert, 'could not find the backtests insert in the route').toBeTruthy()
  return [
    ...(insert?.[1] ?? '').matchAll(/^\s+([a-z_][a-z0-9_]*):/gm),
  ].map((match) => match[1] ?? '')
}

const tables = columnsByTable()

describe('migrations', () => {
  it('are uniquely named and date-ordered', () => {
    expect(new Set(migrations).size).toBe(migrations.length)
    for (const file of migrations) {
      expect(file).toMatch(/^\d{8}_[a-z0-9_]+\.sql$/)
    }
    const dates = migrations.map((file) => file.slice(0, 8))
    expect([...dates].sort()).toEqual(dates)
  })
})

describe('code and schema agree', () => {
  it('defines every column the backtest save writes', () => {
    const columns = tables.get('backtests')
    expect(columns, 'no backtests table in the migrations').toBeDefined()

    const written = backtestInsertColumns()
    // If the parser stops matching, fail rather than pass on an empty list.
    expect(written.length).toBeGreaterThanOrEqual(15)

    for (const column of written) {
      expect(
        columns?.has(column),
        `src/app/api/backtest/route.ts writes backtests.${column}, but no migration creates it`
      ).toBe(true)
    }
  })

  it('keeps the robustness columns in the schema', () => {
    const columns = tables.get('backtests')
    expect(columns?.has('benchmark')).toBe(true)
    expect(columns?.has('stress')).toBe(true)
  })

  it('defines every column the phone writes when importing trades', () => {
    const columns = tables.get('trades')
    expect(columns, 'no trades table in the migrations').toBeDefined()

    const phoneImportColumns = [
      'user_id',
      'symbol',
      'type',
      'entry_price',
      'exit_price',
      'lot_size',
      'stop_loss',
      'take_profit',
      'pnl',
      'commission',
      'swap',
      'open_time',
      'close_time',
      'ticket',
      'import_id',
    ]

    for (const column of phoneImportColumns) {
      expect(
        columns?.has(column),
        `mobile_flutter/lib/services/journal_api.dart writes trades.${column}, but no migration creates it`
      ).toBe(true)
    }
  })
})
