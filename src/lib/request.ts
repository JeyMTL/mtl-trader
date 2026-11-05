import { NextResponse } from 'next/server'

/**
 * Bounded request-body readers.
 *
 * Route handlers used `req.json()` directly, which buffers whatever the client
 * sends. Vercel caps a serverless request at 4.5 MB, but that is still enough
 * for an authenticated caller to make every instance parse a megabyte of JSON,
 * and it is far above what any of these endpoints actually accept. The readers
 * here stream the body, stop at the limit and refuse anything that is not JSON,
 * so the error is explicit instead of becoming a provider timeout.
 */

export const DEFAULT_MAX_JSON_BYTES = 64 * 1024
export const MAX_WEBHOOK_BYTES = 1024 * 1024

export class RequestBodyError extends Error {
  constructor(
    readonly status: 400 | 413 | 415,
    message: string
  ) {
    super(message)
    this.name = 'RequestBodyError'
  }
}

export type BodyReadResult<T> =
  | { ok: true; value: T }
  | { ok: false; response: NextResponse }

function errorResponse(error: RequestBodyError): NextResponse {
  return NextResponse.json({ error: error.message }, { status: error.status })
}

/** Reads at most `maxBytes` of the request body as UTF-8 text. */
export async function readTextLimited(req: Request, maxBytes = MAX_WEBHOOK_BYTES): Promise<string> {
  const declared = Number(req.headers.get('content-length') ?? '')
  if (Number.isFinite(declared) && declared > maxBytes) {
    throw new RequestBodyError(413, 'Request body is too large.')
  }

  if (!req.body) return ''

  const reader = req.body.getReader()
  const chunks: Uint8Array[] = []
  let total = 0

  try {
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      if (!value) continue
      total += value.byteLength
      if (total > maxBytes) {
        await reader.cancel().catch(() => undefined)
        throw new RequestBodyError(413, 'Request body is too large.')
      }
      chunks.push(value)
    }
  } finally {
    reader.releaseLock()
  }

  const merged = new Uint8Array(total)
  let offset = 0
  for (const chunk of chunks) {
    merged.set(chunk, offset)
    offset += chunk.byteLength
  }
  return new TextDecoder().decode(merged)
}

/**
 * Parses a JSON request body with a hard byte ceiling.
 *
 * `allowEmpty` keeps the old `.catch(() => ({}))` behaviour for endpoints whose
 * body is optional; every other caller gets a 400 for an empty body instead of
 * silently operating on `{}`.
 */
export async function readJsonBody<T = Record<string, unknown>>(
  req: Request,
  options: { maxBytes?: number; allowEmpty?: boolean } = {}
): Promise<BodyReadResult<T>> {
  const { maxBytes = DEFAULT_MAX_JSON_BYTES, allowEmpty = false } = options

  const contentType = (req.headers.get('content-type') ?? '').split(';')[0].trim().toLowerCase()
  if (contentType && contentType !== 'application/json') {
    return { ok: false, response: errorResponse(new RequestBodyError(415, 'Send the request as JSON.')) }
  }

  let raw: string
  try {
    raw = await readTextLimited(req, maxBytes)
  } catch (error: unknown) {
    if (error instanceof RequestBodyError) {
      return { ok: false, response: errorResponse(error) }
    }
    throw error
  }

  if (!raw.trim()) {
    if (allowEmpty) return { ok: true, value: {} as T }
    return { ok: false, response: errorResponse(new RequestBodyError(400, 'Missing request body.')) }
  }

  try {
    return { ok: true, value: JSON.parse(raw) as T }
  } catch {
    return { ok: false, response: errorResponse(new RequestBodyError(400, 'Invalid JSON.')) }
  }
}

/** Reads a raw text body (webhooks) with the same ceiling. */
export async function readRawBody(req: Request, maxBytes = MAX_WEBHOOK_BYTES): Promise<BodyReadResult<string>> {
  try {
    return { ok: true, value: await readTextLimited(req, maxBytes) }
  } catch (error: unknown) {
    if (error instanceof RequestBodyError) {
      return { ok: false, response: errorResponse(error) }
    }
    throw error
  }
}
