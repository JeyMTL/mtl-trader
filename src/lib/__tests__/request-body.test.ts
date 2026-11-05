import { describe, expect, it } from 'vitest'
import { readJsonBody, readRawBody, readTextLimited } from '@/lib/request'

function jsonRequest(body: string, headers: Record<string, string> = {}) {
  return new Request('http://localhost/api/test', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body,
  })
}

describe('bounded request bodies', () => {
  it('parses valid JSON', async () => {
    const result = await readJsonBody<{ planId?: string }>(jsonRequest('{"planId":"pro"}'))
    expect(result.ok).toBe(true)
    if (result.ok) expect(result.value.planId).toBe('pro')
  })

  it('rejects a declared length above the ceiling', async () => {
    const result = await readJsonBody(
      jsonRequest('{}', { 'content-length': String(2048) }),
      { maxBytes: 1024 }
    )
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.response.status).toBe(413)
  })

  it('stops streaming once the body exceeds the ceiling without a content-length', async () => {
    const result = await readJsonBody(jsonRequest(JSON.stringify({ pad: 'x'.repeat(4096) })), {
      maxBytes: 1024,
    })
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.response.status).toBe(413)
  })

  it('rejects a non-JSON content type', async () => {
    const result = await readJsonBody(
      new Request('http://localhost/api/test', {
        method: 'POST',
        headers: { 'content-type': 'text/plain' },
        body: '{"a":1}',
      })
    )
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.response.status).toBe(415)
  })

  it('rejects malformed JSON with 400 rather than throwing', async () => {
    const result = await readJsonBody(jsonRequest('{nope'))
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.response.status).toBe(400)
  })

  it('allows an empty body only when the caller opts in', async () => {
    const request = new Request('http://localhost/api/test', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
    })
    expect((await readJsonBody(request)).ok).toBe(false)
    expect((await readJsonBody(request, { allowEmpty: true })).ok).toBe(true)
  })

  it('caps raw webhook bodies', async () => {
    const request = new Request('http://localhost/api/webhook', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: 'x'.repeat(4096),
    })
    const result = await readRawBody(request, 1024)
    expect(result.ok).toBe(false)
    if (!result.ok) expect(result.response.status).toBe(413)
  })

  it('reads a body under the limit intact', async () => {
    await expect(readTextLimited(jsonRequest('{"a":1}'), 1024)).resolves.toBe('{"a":1}')
  })
})
