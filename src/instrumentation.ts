import { describeError, logEvent } from '@/lib/log'

/**
 * Request-level error reporting.
 *
 * Next.js calls `onRequestError` for errors thrown while rendering a route or a
 * server component. Without this the only trace is a stack in the platform log,
 * which nobody is watching. Every error is emitted as one structured log line and
 * forwarded to `ERROR_REPORT_URL` when configured — point that at an error
 * tracker, a Slack webhook, or anything that accepts JSON.
 */
export async function onRequestError(
  error: unknown,
  request: { path?: string; method?: string },
  context: { routerKind?: string; routePath?: string; routeType?: string }
): Promise<void> {
  const details = describeError(error)

  logEvent('error', 'request.failed', {
    error,
    path: request?.path,
    method: request?.method,
    routerKind: context?.routerKind,
    routePath: context?.routePath,
    routeType: context?.routeType,
  })

  const reportUrl = process.env.ERROR_REPORT_URL
  if (!reportUrl) return

  try {
    await fetch(reportUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        service: 'mtl-trader',
        at: new Date().toISOString(),
        path: request?.path,
        method: request?.method,
        routePath: context?.routePath,
        message: details.message,
        name: details.name,
        stack: details.stack,
      }),
    })
  } catch {
    // Reporting must never break the request that failed.
  }
}
