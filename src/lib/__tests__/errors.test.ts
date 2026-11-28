import { describe, expect, it } from 'vitest'
import { errorText, publicErrorMessage } from '../errors'

const FALLBACK = 'Could not save your profile. Please try again.'

describe('publicErrorMessage', () => {
  it('hides PostgREST and RLS text behind the screen fallback', () => {
    for (const message of [
      'new row violates row-level security policy for table "users"',
      'permission denied for table trades',
      'relation "public.settings" does not exist',
      'duplicate key value violates unique constraint "users_email_key"',
      'Database error saving new user',
      'Supabase is unreachable',
    ]) {
      expect(publicErrorMessage(new Error(message), FALLBACK)).toBe(FALLBACK)
    }
  })

  it('turns connection failure into a sentence about the connection', () => {
    expect(publicErrorMessage(new Error('TypeError: Failed to fetch'), FALLBACK)).toBe(
      'Could not connect. Check your connection and try again.'
    )
    expect(publicErrorMessage(new Error('Upstream timed out'), FALLBACK)).toBe(
      'Could not connect. Check your connection and try again.'
    )
  })

  it('says what the sign-in problem actually is', () => {
    expect(publicErrorMessage(new Error('Invalid login credentials'), FALLBACK)).toBe(
      'The email or password is incorrect.'
    )
    expect(publicErrorMessage(new Error('User already registered'), FALLBACK)).toBe(
      'An account with that email address already exists. Try signing in instead.'
    )
    expect(publicErrorMessage(new Error('Email not confirmed'), FALLBACK)).toBe(
      'Confirm your email address first — the verification link is in your inbox.'
    )
    expect(publicErrorMessage(new Error('Email rate limit exceeded'), FALLBACK)).toBe(
      'Too many attempts. Please wait a moment and try again.'
    )
    expect(publicErrorMessage(new Error('JWT expired'), FALLBACK)).toBe(
      'Your session has expired. Sign in again.'
    )
  })

  it('keeps a message the app wrote itself', () => {
    expect(publicErrorMessage(new Error('Type DELETE to confirm.'), FALLBACK)).toBe(
      'Type DELETE to confirm.'
    )
  })

  it('falls back for empty, missing and JSON-shaped errors', () => {
    expect(publicErrorMessage(null, FALLBACK)).toBe(FALLBACK)
    expect(publicErrorMessage(undefined, FALLBACK)).toBe(FALLBACK)
    expect(publicErrorMessage(new Error('{}'), FALLBACK)).toBe(FALLBACK)
    expect(publicErrorMessage({ message: '{"code":"PGRST301"}' }, FALLBACK)).toBe(FALLBACK)
    expect(publicErrorMessage(new Error('   '), FALLBACK)).toBe(FALLBACK)
  })

  it('reads the message out of objects, strings and real errors', () => {
    expect(errorText(new Error('boom'))).toBe('boom')
    expect(errorText(' boom ')).toBe('boom')
    expect(errorText({ message: 'boom' })).toBe('boom')
    expect(errorText({ error_description: 'boom' })).toBe('boom')
    expect(errorText(42)).toBe('')
  })
})
