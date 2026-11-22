/**
 * The one place an error becomes words a trader can read.
 *
 * Provider errors are written for developers: Supabase answers with PostgREST
 * codes and "row-level security" text, Vercel with request ids, market and
 * payment vendors with their own failures. None of that helps somebody trying
 * to save a trade, and some of it names infrastructure we would rather not
 * advertise. Screens call this with their own fallback sentence; known problems
 * get a useful message, everything technical is replaced by the fallback.
 */

const CONNECTION =
  /failed to fetch|network ?error|networkerror|load failed|timed? ?out|offline|econn|enotfound|fetch failed|socket hang up/i
const RATE_LIMIT = /rate limit|too many (requests|attempts)|email rate limit|slow down/i
const DUPLICATE_EMAIL = /user already registered|already (been )?registered|email (address )?already/i
const BAD_CREDENTIALS = /invalid login credentials|invalid email or password|wrong password/i
const UNCONFIRMED = /email not confirmed|confirm your email/i
const WEAK_PASSWORD = /password should be at least|weak password|password is too short/i
const EXPIRED_SESSION = /jwt|token (has )?expired|refresh token|invalid claim|not authenticated|session (is )?(missing|expired)/i

/** Names, codes and vocabulary that belong in the logs, not on the screen. */
const VENDOR =
  /supabase|postgres|postgrest|pgrst|row[- ]level|rls|duplicate key|violates .*constraint|schema cache|relation .*does not exist|column .*does not exist|permission denied|database error|vercel|server components render|digest:|internal server error|service[_ ]role|api key|openai|anthropic|gemini|paddle|paypal|oanda|econnrefused/i

/** The message inside anything thrown, rejected or returned with a message. */
export function errorText(error: unknown): string {
  if (typeof error === 'string') return error.trim()
  if (error instanceof Error) return error.message.trim()
  if (error && typeof error === 'object') {
    const record = error as { message?: unknown; error_description?: unknown }
    if (typeof record.message === 'string') return record.message.trim()
    if (typeof record.error_description === 'string') return record.error_description.trim()
  }
  return ''
}

/**
 * A sentence for the screen. `fallback` says what failed and what to do; it is
 * returned for anything technical, empty, or shaped like a JSON blob.
 */
export function publicErrorMessage(error: unknown, fallback: string): string {
  const text = errorText(error)
  if (!text || text === '{}' || text.startsWith('{')) return fallback

  if (CONNECTION.test(text)) {
    return 'Could not reach the server. Check your connection and try again.'
  }
  if (RATE_LIMIT.test(text)) {
    return 'Too many attempts. Please wait a moment and try again.'
  }
  if (DUPLICATE_EMAIL.test(text)) {
    return 'An account with that email address already exists. Try signing in instead.'
  }
  if (BAD_CREDENTIALS.test(text)) {
    return 'The email or password is incorrect.'
  }
  if (UNCONFIRMED.test(text)) {
    return 'Confirm your email address first — the verification link is in your inbox.'
  }
  if (WEAK_PASSWORD.test(text)) {
    return 'Choose a longer password, at least 8 characters.'
  }
  if (EXPIRED_SESSION.test(text)) {
    return 'Your session has expired. Sign in again.'
  }
  if (VENDOR.test(text)) return fallback

  return text
}
