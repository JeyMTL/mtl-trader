'use client'

import { useEffect } from 'react'

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string }
  reset: () => void
}) {
  useEffect(() => {
    console.error('Application error', error)
  }, [error])

  return (
    <html lang="en">
      <body style={{ margin: 0, background: '#08090c', color: '#e9ecf1', fontFamily: 'system-ui, sans-serif' }}>
        <main style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '24px' }}>
          <div style={{ maxWidth: '420px', textAlign: 'center' }}>
            <p style={{ fontSize: '11px', letterSpacing: '0.14em', textTransform: 'uppercase', color: '#98a1b0' }}>
              MTL Trader
            </p>
            <h1 style={{ margin: '8px 0 0', fontSize: '22px', fontWeight: 600, letterSpacing: '-0.02em' }}>
              Something broke
            </h1>
            <p style={{ margin: '8px 0 0', fontSize: '14px', lineHeight: 1.6, color: '#98a1b0' }}>
              The app hit an unexpected error. Reloading is safe; nothing was saved mid-request.
            </p>
            <button
              onClick={reset}
              style={{
                marginTop: '20px',
                padding: '10px 18px',
                borderRadius: '10px',
                border: '1px solid #d5a44e',
                background: '#d5a44e',
                color: '#120d04',
                fontSize: '14px',
                fontWeight: 600,
                cursor: 'pointer',
              }}
            >
              Reload
            </button>
          </div>
        </main>
      </body>
    </html>
  )
}
