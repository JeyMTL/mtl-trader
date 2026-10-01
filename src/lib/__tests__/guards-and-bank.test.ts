import { describe, it, expect, afterEach } from 'vitest'
import { hasValidBearer } from '@/lib/auth-guards'
import { getBankDetails, isBankConfigured } from '@/lib/bank'

function reqWith(authorization?: string) {
  return new Request('http://localhost/api/cron/notifications', {
    headers: authorization ? { authorization } : {},
  })
}

describe('hasValidBearer', () => {
  it('accepts the exact secret and nothing else', () => {
    expect(hasValidBearer(reqWith('Bearer s3cret'), 's3cret')).toBe(true)
    expect(hasValidBearer(reqWith('Bearer wrong'), 's3cret')).toBe(false)
    expect(hasValidBearer(reqWith('s3cret'), 's3cret')).toBe(false)
    expect(hasValidBearer(reqWith(), 's3cret')).toBe(false)
  })

  it('fails closed when no secret is configured', () => {
    expect(hasValidBearer(reqWith('Bearer anything'), undefined)).toBe(false)
    expect(hasValidBearer(reqWith('Bearer anything'), '')).toBe(false)
  })

  it('rejects a length mismatch without throwing', () => {
    expect(hasValidBearer(reqWith('Bearer x'), 'much-longer-secret')).toBe(false)
  })
})

describe('bank config', () => {
  const original = { ...process.env }

  afterEach(() => {
    for (const key of ['BANK_NAME', 'BANK_ACCOUNT_NAME', 'BANK_ACCOUNT_NUMBER', 'BANK_BRANCH']) {
      if (original[key] === undefined) delete process.env[key]
      else process.env[key] = original[key]
    }
  })

  it('is unconfigured when the required values are missing', () => {
    delete process.env.BANK_NAME
    delete process.env.BANK_ACCOUNT_NAME
    delete process.env.BANK_ACCOUNT_NUMBER
    expect(getBankDetails()).toBeNull()
    expect(isBankConfigured()).toBe(false)
  })

  it('returns details once configured, with branch optional', () => {
    process.env.BANK_NAME = 'Test Bank'
    process.env.BANK_ACCOUNT_NAME = 'Jane Doe'
    process.env.BANK_ACCOUNT_NUMBER = '0001112223'
    delete process.env.BANK_BRANCH
    expect(getBankDetails()).toEqual({
      bank_name: 'Test Bank',
      account_name: 'Jane Doe',
      account_number: '0001112223',
      branch: '',
    })
    expect(isBankConfigured()).toBe(true)
  })
})
