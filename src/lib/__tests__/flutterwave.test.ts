import { createHmac } from 'node:crypto'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import {
  isPaidPlanId,
  isValidFlutterwaveSignature,
} from '@/lib/flutterwave'

const originalSecret = process.env.FLUTTERWAVE_SECRET_HASH

beforeEach(() => {
  process.env.FLUTTERWAVE_SECRET_HASH = 'test-secret-hash'
})

afterEach(() => {
  if (originalSecret === undefined) delete process.env.FLUTTERWAVE_SECRET_HASH
  else process.env.FLUTTERWAVE_SECRET_HASH = originalSecret
})

describe('isPaidPlanId', () => {
  it('accepts paid plans and rejects the trial and unknown ids', () => {
    expect(isPaidPlanId('basic')).toBe(true)
    expect(isPaidPlanId('pro')).toBe(true)
    expect(isPaidPlanId('free')).toBe(false)
    expect(isPaidPlanId('enterprise')).toBe(false)
    expect(isPaidPlanId(null)).toBe(false)
    expect(isPaidPlanId(42)).toBe(false)
  })
})

describe('isValidFlutterwaveSignature', () => {
  it('accepts the dashboard secret hash', () => {
    expect(isValidFlutterwaveSignature('test-secret-hash', '{}')).toBe(true)
  })

  it('accepts an HMAC-SHA256 of the raw body', () => {
    const body = JSON.stringify({ event: 'charge.completed' })
    const signature = createHmac('sha256', 'test-secret-hash')
      .update(body)
      .digest('hex')
    expect(isValidFlutterwaveSignature(signature, body)).toBe(true)
  })

  it('rejects a wrong or missing signature', () => {
    expect(isValidFlutterwaveSignature('wrong', '{}')).toBe(false)
    expect(isValidFlutterwaveSignature(null, '{}')).toBe(false)
    expect(isValidFlutterwaveSignature('', '{}')).toBe(false)
  })

  it('rejects everything when no secret is configured', () => {
    delete process.env.FLUTTERWAVE_SECRET_HASH
    expect(isValidFlutterwaveSignature('test-secret-hash', '{}')).toBe(false)
  })
})
