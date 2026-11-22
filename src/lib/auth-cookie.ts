import type { CookieOptions } from '@supabase/ssr'

/**
 * How long the auth cookies are allowed to live.
 *
 * `@supabase/ssr` currently defaults to 400 days, and today's behaviour is a
 * persistent cookie: close the browser and the session is still there. Saying it
 * out loud means a library upgrade that shortens the default, or a client
 * constructed without options, cannot quietly turn the journal into something
 * that asks for a password every morning.
 */
export const AUTH_COOKIE_OPTIONS: CookieOptions = {
  path: '/',
  sameSite: 'lax',
  // Secure cookies are dropped over plain http, which is how the app runs in
  // development, so this follows the scheme rather than being always on.
  secure: process.env.NODE_ENV === 'production',
  maxAge: 400 * 24 * 60 * 60,
}
