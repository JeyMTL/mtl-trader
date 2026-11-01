import { describe, expect, it } from 'vitest'
import { RPC_PROBES, classifyRpcProbe } from '@/lib/health-rpcs'

describe('RPC probe classification', () => {
  it('treats a missing function as missing', () => {
    expect(
      classifyRpcProbe(404, {
        code: 'PGRST202',
        message:
          'Could not find the function public.session_stats without parameters in the schema cache',
      })
    ).toBe('missing')
  })

  it('treats a renamed argument as missing, because callers break the same way', () => {
    expect(
      classifyRpcProbe(404, {
        code: 'PGRST202',
        message:
          'Searched for the function public.trade_page with parameters p_limit, p_session, but no matches were found',
      })
    ).toBe('missing')
  })

  it('treats permission denied as present: anon is not meant to execute these', () => {
    expect(classifyRpcProbe(403, { code: '42501', message: 'permission denied for function' })).toBe(
      'ready'
    )
    expect(classifyRpcProbe(401, {})).toBe('ready')
  })

  it('treats any executed answer as present', () => {
    expect(classifyRpcProbe(200, [])).toBe('ready')
    expect(classifyRpcProbe(204, null)).toBe('ready')
    expect(classifyRpcProbe(400, { code: '22P02', message: 'invalid input syntax for uuid' })).toBe(
      'ready'
    )
  })

  it('does not claim to know when the response says nothing useful', () => {
    expect(classifyRpcProbe(0, null)).toBe('unknown')
    expect(classifyRpcProbe(302, null)).toBe('ready')
  })
})

describe('RPC probe list', () => {
  it('names a migration for every dependency', () => {
    for (const probe of RPC_PROBES) {
      expect(probe.migration, probe.rpc).toMatch(/^\d{8}_.+\.sql$/)
      expect(probe.usedBy.length, probe.rpc).toBeGreaterThan(0)
    }
  })

  it('probes each function once', () => {
    const names = RPC_PROBES.map((probe) => probe.rpc)
    expect(new Set(names).size).toBe(names.length)
  })

  it('never probes with a real user id', () => {
    const serialised = JSON.stringify(RPC_PROBES)
    expect(serialised).not.toMatch(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-(?!0{12})/)
  })
})
