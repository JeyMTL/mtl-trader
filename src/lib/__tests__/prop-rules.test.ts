import { describe, expect, it } from 'vitest'
import { parsePropRules, propStatusLevel } from '@/lib/prop-rules'

const valid = {
  account_size: 10000,
  max_daily_loss_pct: 5,
  max_drawdown_pct: 10,
  trailing_drawdown: true,
  profit_target_pct: 10,
  min_trading_days: 5,
  consistency_pct: 30,
  started_on: '2026-06-01',
}

describe('parsePropRules', () => {
  it('accepts a normal evaluation', () => {
    const parsed = parsePropRules(valid)
    expect(parsed).toEqual({ ok: true, value: valid })
  })

  it('defaults a trailing drawdown and a start date when omitted', () => {
    const parsed = parsePropRules({ ...valid, trailing_drawdown: undefined, started_on: undefined })
    expect(parsed.ok).toBe(true)
    if (parsed.ok) {
      expect(parsed.value.trailing_drawdown).toBe(true)
      expect(parsed.value.started_on).toMatch(/^\d{4}-\d{2}-\d{2}$/)
    }
  })

  it('keeps a static drawdown when it is chosen explicitly', () => {
    const parsed = parsePropRules({ ...valid, trailing_drawdown: false })
    expect(parsed.ok && parsed.value.trailing_drawdown).toBe(false)
  })

  it('rejects an account size of zero, because every percentage divides by it', () => {
    expect(parsePropRules({ ...valid, account_size: 0 }).ok).toBe(false)
    expect(parsePropRules({ ...valid, account_size: 'abc' }).ok).toBe(false)
  })

  it('rejects impossible limits', () => {
    expect(parsePropRules({ ...valid, max_daily_loss_pct: 0 }).ok).toBe(false)
    expect(parsePropRules({ ...valid, max_daily_loss_pct: 80 }).ok).toBe(false)
    expect(parsePropRules({ ...valid, max_drawdown_pct: 150 }).ok).toBe(false)
    expect(parsePropRules({ ...valid, profit_target_pct: -1 }).ok).toBe(false)
    expect(parsePropRules({ ...valid, min_trading_days: 400 }).ok).toBe(false)
    expect(parsePropRules({ ...valid, consistency_pct: 0 }).ok).toBe(false)
    expect(parsePropRules({ ...valid, consistency_pct: 120 }).ok).toBe(false)
  })

  it('defaults the consistency limit when a client does not send one', () => {
    const parsed = parsePropRules({ ...valid, consistency_pct: undefined })
    expect(parsed.ok && parsed.value.consistency_pct).toBe(30)
  })

  it('rounds the account size to cents and the days to a whole number', () => {
    const parsed = parsePropRules({ ...valid, account_size: 10000.129, min_trading_days: 4.6 })
    expect(parsed.ok).toBe(true)
    if (parsed.ok) {
      expect(parsed.value.account_size).toBe(10000.13)
      expect(parsed.value.min_trading_days).toBe(5)
    }
  })

  it('refuses a payload that is not an object', () => {
    expect(parsePropRules(null).ok).toBe(false)
    expect(parsePropRules('rules').ok).toBe(false)
  })
})

describe('propStatusLevel', () => {
  it('maps the SQL status onto three display levels', () => {
    expect(propStatusLevel('ok')).toBe('ok')
    expect(propStatusLevel(undefined)).toBe('ok')
    expect(propStatusLevel('warn_daily')).toBe('warning')
    expect(propStatusLevel('warn_drawdown')).toBe('warning')
    expect(propStatusLevel('breach_daily')).toBe('breach')
    expect(propStatusLevel('breach_drawdown')).toBe('breach')
    expect(propStatusLevel('breach_consistency')).toBe('breach')
    expect(propStatusLevel('warn_consistency')).toBe('warning')
  })
})
