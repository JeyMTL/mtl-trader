import { describe, expect, it } from 'vitest'
import nextConfig from '../../../next.config'

type HeaderRule = { source: string; headers: Array<{ key: string; value: string }> }

async function rules(): Promise<HeaderRule[]> {
  return (await nextConfig.headers?.()) as HeaderRule[]
}

function valuesFor(rule: HeaderRule): Map<string, string> {
  return new Map(rule.headers.map((header) => [header.key.toLowerCase(), header.value]))
}

describe('security headers', () => {
  it('sets the isolation headers on every response', async () => {
    const global = (await rules()).find((rule) => rule.source === '/(.*)')
    expect(global).toBeDefined()
    const values = valuesFor(global as HeaderRule)

    expect(values.get('x-content-type-options')).toBe('nosniff')
    expect(values.get('x-frame-options')).toBe('DENY')
    // allow-popups, because Google Identity Services returns the sign-in
    // credential from a popup through window.opener and plain same-origin severs
    // that relationship. Everything else stays cross-origin isolated.
    expect(values.get('cross-origin-opener-policy')).toBe('same-origin-allow-popups')
    expect(values.get('cross-origin-resource-policy')).toBe('same-origin')
    expect(values.get('origin-agent-cluster')).toBe('?1')
    expect(values.get('x-permitted-cross-domain-policies')).toBe('none')
    expect(values.get('strict-transport-security')).toContain('max-age=')
    expect(values.get('referrer-policy')).toBe('strict-origin-when-cross-origin')
  })

  it('keeps the CSP locked to self with no framing and no plugins', async () => {
    const global = (await rules()).find((rule) => rule.source === '/(.*)') as HeaderRule
    const csp = valuesFor(global).get('content-security-policy') ?? ''

    expect(csp).toContain("default-src 'self'")
    expect(csp).toContain("frame-ancestors 'none'")
    expect(csp).toContain("object-src 'none'")
    expect(csp).toContain("script-src-attr 'none'")
    expect(csp).toContain("base-uri 'self'")
    expect(csp).not.toContain("default-src *")
  })

  it('frames only the vendors that serve their own content', async () => {
    const global = (await rules()).find((rule) => rule.source === '/(.*)') as HeaderRule
    const frameSrc =
      (valuesFor(global).get('content-security-policy') ?? '')
        .split(';')
        .map((directive) => directive.trim())
        .find((directive) => directive.startsWith('frame-src')) ?? ''

    // The market view is a TradingView iframe; nothing else may be framed, and
    // the app may still not be framed by anyone.
    expect(frameSrc).toContain('https://*.tradingview.com')
    expect(frameSrc).not.toContain("'self'")
  })

  it('denies capabilities a journal never needs', async () => {
    const global = (await rules()).find((rule) => rule.source === '/(.*)') as HeaderRule
    const policy = valuesFor(global).get('permissions-policy') ?? ''

    expect(policy).toContain('camera=(self)')
    expect(policy).toContain('microphone=(self)')
    expect(policy).toContain('geolocation=()')
    expect(policy).toContain('usb=()')
    expect(policy).toContain('browsing-topics=()')
  })

  it('keeps authenticated screens out of search indexes', async () => {
    const dashboard = (await rules()).find((rule) => rule.source === '/dashboard/:path*')
    expect(dashboard).toBeDefined()
    expect(valuesFor(dashboard as HeaderRule).get('x-robots-tag')).toBe('noindex, nofollow')
  })
})
