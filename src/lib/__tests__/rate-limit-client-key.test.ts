import { describe, expect, it } from 'vitest'
import { clientKey } from '@/lib/rate-limit'

function requestWith(headers: Record<string, string>): Request {
  return new Request('https://app.test/api/whatever', { headers })
}

describe('clientKey', () => {
  it('ignores a spoofed first forwarded hop', () => {
    // The caller can send anything; the edge appends the real address last.
    const key = clientKey(
      requestWith({ 'x-forwarded-for': '1.2.3.4, 203.0.113.9' }),
      'checkout'
    )
    expect(key).toBe('checkout:203.0.113.9')
  })

  it('prefers the header the platform writes', () => {
    const key = clientKey(
      requestWith({
        'x-vercel-forwarded-for': '198.51.100.7',
        'x-forwarded-for': '1.2.3.4, 203.0.113.9',
      }),
      'checkout'
    )
    expect(key).toBe('checkout:198.51.100.7')
  })

  it('falls back to x-real-ip before the forwarded chain', () => {
    const key = clientKey(
      requestWith({ 'x-real-ip': '192.0.2.44', 'x-forwarded-for': '9.9.9.9' }),
      'checkout'
    )
    expect(key).toBe('checkout:192.0.2.44')
  })

  it('degrades to a single shared bucket with no headers at all', () => {
    expect(clientKey(requestWith({}), 'checkout')).toBe('checkout:unknown')
  })
})
