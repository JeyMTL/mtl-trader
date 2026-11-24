import { describe, it, expect } from 'vitest'
import { hasValidBearer } from '@/lib/auth-guards'

function reqWith(authorization?: string) {
  return new Request('http://localhost/api/admin/reconcile', {
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
