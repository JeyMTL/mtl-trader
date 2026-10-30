import { NextResponse } from 'next/server'

/**
 * Structured, single-line JSON logs.
 *
 * Vercel captures stdout/stderr, so one JSON object per line is what the log
 * viewer and any downstream drain can actually query. Route handlers log the
 * real cause and return a generic message to the client, so database errors,
 * provider responses and stack traces stay in the logs instead of the browser.
 */

type Level = 'info' | 'warn' | 'error'

export interface LogFields {
  [key: string]: unknown
}

export function describeError(error: unknown): { name?: string; message: string; stack?: string } {
  if (error instanceof Error) {
    return { name: error.name, message: error.message, stack: error.stack }
  }
  if (typeof error === 'string') return { message: error }
  if (error && typeof error === 'object') {
    const record = error as Record<string, unknown>
    const message = typeof record.message === 'string' ? record.message : 'Unknown error'
    return { message }
  }
  return { message: 'Unknown error' }
}

export function logEvent(level: Level, event: string, fields: LogFields = {}): void {
  const payload: Record<string, unknown> = {
    level,
    event,
    at: new Date().toISOString(),
  }

  for (const [key, value] of Object.entries(fields)) {
    payload[key] = key === 'error' ? describeError(value) : value
  }

  const line = JSON.stringify(payload)
  if (level === 'error') console.error(line)
  else if (level === 'warn') console.warn(line)
  else console.log(line)
}

/**
 * Logs the real error and responds with a safe message. `status` defaults to 500
 * so an unhandled failure never looks like a client error.
 */
export function apiError(
  event: string,
  error: unknown,
  status = 500,
  publicMessage = 'Something went wrong. Please try again.'
): NextResponse {
  logEvent('error', event, { error, status })
  return NextResponse.json({ error: publicMessage }, { status })
}

/** 4xx helpers: expected refusals, logged at warn level without stack noise. */
export function apiWarn(
  event: string,
  message: string,
  status = 400,
  fields: LogFields = {}
): NextResponse {
  logEvent('warn', event, { ...fields, reason: message })
  return NextResponse.json({ error: message }, { status })
}
