'use client'

import { useEffect, useRef, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { completeGoogleSignIn } from '@/lib/google-signin'
import { publicErrorMessage } from '@/lib/errors'

/**
 * Google's own rendered button, wired to Google Identity Services.
 *
 * The credential callback fires with a signed ID token while the browser stays
 * on this origin, which keeps the account chooser branded with our domain.
 * Google requires their button artwork for this flow, so the markup comes from
 * their script rather than a styled <button>.
 */

type CredentialResponse = { credential?: string }

type GoogleIdentity = {
  accounts: {
    id: {
      initialize: (config: {
        client_id: string
        callback: (response: CredentialResponse) => void
        ux_mode?: 'popup' | 'redirect'
        auto_select?: boolean
      }) => void
      renderButton: (parent: HTMLElement, options: Record<string, unknown>) => void
    }
  }
}

declare global {
  interface Window {
    google?: GoogleIdentity
  }
}

const SCRIPT_ID = 'google-identity-services'
let loader: Promise<GoogleIdentity> | null = null

function loadGoogleIdentity(): Promise<GoogleIdentity> {
  if (typeof window === 'undefined') {
    return Promise.reject(new Error('Google sign-in is only available in the browser.'))
  }
  if (window.google?.accounts?.id) return Promise.resolve(window.google)

  if (!loader) {
    loader = new Promise<GoogleIdentity>((resolve, reject) => {
      const existing = document.getElementById(SCRIPT_ID) as HTMLScriptElement | null
      const script = existing ?? document.createElement('script')

      const onLoad = () => {
        if (window.google?.accounts?.id) resolve(window.google)
        else reject(new Error('Google sign-in failed to initialise.'))
      }
      const onError = () =>
        reject(new Error('Could not load Google sign-in. Check your connection and try again.'))

      script.addEventListener('load', onLoad)
      script.addEventListener('error', onError)

      if (!existing) {
        script.id = SCRIPT_ID
        script.src = 'https://accounts.google.com/gsi/client'
        script.async = true
        script.defer = true
        document.head.appendChild(script)
      }
    })

    // A failed load must be retryable: drop the memo so the next click tries again.
    loader.catch(() => {
      loader = null
    })
  }

  return loader
}

/**
 * Identity Services only works once `https://mtlledger.com` is listed under
 * Authorized JavaScript origins for the OAuth client. Until that is saved,
 * Google answers the popup with "Access blocked: no registered origin", which
 * the page cannot detect — the popup never calls back. So the branded flow is
 * opt-in: set NEXT_PUBLIC_GOOGLE_GIS=1 after the origin is registered, and this
 * component renders the proven Supabase redirect flow until then.
 */
const gisEnabled = process.env.NEXT_PUBLIC_GOOGLE_GIS === '1'

const BUTTON_CLASS =
  'w-full flex items-center justify-center gap-2 bg-background border border-border hover:border-primary text-white py-3 rounded-xl font-semibold transition-colors disabled:opacity-50 disabled:cursor-not-allowed'

export function GoogleSignInButton({
  text = 'continue_with',
  onStart,
  onError,
  disabled = false,
}: {
  text?: 'signin_with' | 'signup_with' | 'continue_with'
  onStart?: () => void
  onError: (message: string) => void
  disabled?: boolean
}) {
  const container = useRef<HTMLDivElement>(null)
  const [ready, setReady] = useState(false)
  const clientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID

  // Callbacks are held in a ref so a parent re-render cannot re-initialise the
  // button (which would redraw it and drop the in-flight popup). Synced in an
  // effect because refs must not be written during render.
  const handlers = useRef({ onStart, onError })
  useEffect(() => {
    handlers.current = { onStart, onError }
  }, [onStart, onError])

  useEffect(() => {
    const node = container.current
    if (!clientId || !node) return

    let cancelled = false

    loadGoogleIdentity()
      .then((google) => {
        if (cancelled || !container.current) return

        google.accounts.id.initialize({
          client_id: clientId,
          ux_mode: 'popup',
          auto_select: false,
          callback: (response) => {
            if (!response.credential) {
              handlers.current.onError('Google did not return a sign-in token. Please try again.')
              return
            }
            handlers.current.onStart?.()
            void completeGoogleSignIn(response.credential).then((result) => {
              if (!result.ok) handlers.current.onError(result.error)
            })
          },
        })

        container.current.innerHTML = ''
        google.accounts.id.renderButton(container.current, {
          type: 'standard',
          theme: 'filled_black',
          size: 'large',
          text,
          shape: 'rectangular',
          logo_alignment: 'left',
          width: 320,
        })
        setReady(true)
      })
      .catch((error: unknown) => {
        if (cancelled) return
        handlers.current.onError(
          publicErrorMessage(error, 'Could not load Google sign-in. Check your connection and try again.')
        )
      })

    return () => {
      cancelled = true
    }
  }, [clientId, text])

  if (!gisEnabled) {
    // Supabase's hosted redirect: always works, but Google's chooser names the
    // project's <ref>.supabase.co because that is the redirect host.
    return (
      <button
        type="button"
        disabled={disabled}
        onClick={async () => {
          handlers.current.onStart?.()
          const { error } = await supabase.auth.signInWithOAuth({
            provider: 'google',
            options: {
              redirectTo: `${window.location.origin}/auth/callback`,
              queryParams: { prompt: 'select_account' },
            },
          })
          // On success the browser leaves for Google, so nothing below runs.
          if (error) {
            handlers.current.onError(
              publicErrorMessage(error, 'Google sign-in could not start. Please try again.')
            )
          }
        }}
        className={BUTTON_CLASS}
      >
        <span className="text-[15px] font-extrabold leading-none">G</span>
        {text === 'signin_with' ? 'Sign in with Google' : 'Continue with Google'}
      </button>
    )
  }

  if (!clientId) {
    return (
      <p className="text-center text-xs text-danger">
        Google sign-in is not configured: set NEXT_PUBLIC_GOOGLE_CLIENT_ID.
      </p>
    )
  }

  return (
    <div
      className={`flex min-h-[44px] w-full items-center justify-center transition-opacity ${
        disabled ? 'pointer-events-none opacity-50' : ''
      }`}
    >
      <div ref={container} aria-busy={!ready} />
    </div>
  )
}
