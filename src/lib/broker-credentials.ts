import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto'

/**
 * Investor-password storage for hosted MT5 sync.
 *
 * A phone can't run an Expert Advisor, so a customer who only has the mobile app
 * cannot push their own trades. The alternative the category uses (Plancana,
 * TradeZella, TradesViz, TraderDNA) is that the service logs in with the
 * account's **investor** password — the read-only credential MT5 already
 * provides — and streams history from its own side.
 *
 * That means we hold a credential, so it is encrypted at rest with AES-256-GCM
 * and the key never lives in the database. The master (trading) password is
 * never accepted anywhere: only the investor password grants read-only access,
 * so a leak of this table cannot move money. Changing the investor password in
 * the MT5 app invalidates our copy, which is the customer's revoke button.
 *
 * `SYNC_CREDENTIAL_KEY` is 32 random bytes, base64 encoded:
 *   node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"
 */

const ALGORITHM = 'aes-256-gcm'
const IV_BYTES = 12
const FORMAT_VERSION = 'v1'
const KEY_BYTES = 32

export function credentialKeyConfigured(): boolean {
  return Boolean(process.env.SYNC_CREDENTIAL_KEY)
}

function key(): Buffer {
  const raw = process.env.SYNC_CREDENTIAL_KEY
  if (!raw) {
    throw new Error('SYNC_CREDENTIAL_KEY is not configured')
  }
  const decoded = Buffer.from(raw, 'base64')
  if (decoded.length !== KEY_BYTES) {
    throw new Error(
      `SYNC_CREDENTIAL_KEY must decode to ${KEY_BYTES} bytes, base64 encoded (got ${decoded.length})`
    )
  }
  return decoded
}

/**
 * Seals a credential for storage. The output is
 * `v1:<iv>:<authTag>:<ciphertext>`, all base64, so a future key rotation or
 * algorithm change can be detected rather than silently mis-decrypted.
 */
export function encryptCredential(plaintext: string): string {
  if (!plaintext) throw new Error('Nothing to encrypt')
  const iv = randomBytes(IV_BYTES)
  const cipher = createCipheriv(ALGORITHM, key(), iv)
  const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()])
  const tag = cipher.getAuthTag()
  return [
    FORMAT_VERSION,
    iv.toString('base64'),
    tag.toString('base64'),
    ciphertext.toString('base64'),
  ].join(':')
}

/**
 * Opens a sealed credential. Throws on a wrong key, a truncated value or any
 * tampering, because GCM authenticates the ciphertext — a corrupted row must
 * fail loudly instead of authenticating the broker with a garbage password.
 */
export function decryptCredential(payload: string): string {
  const parts = payload.split(':')
  if (parts.length !== 4 || parts[0] !== FORMAT_VERSION) {
    throw new Error('Unrecognised credential format')
  }
  const [, ivPart, tagPart, ciphertextPart] = parts
  const decipher = createDecipheriv(ALGORITHM, key(), Buffer.from(ivPart, 'base64'))
  decipher.setAuthTag(Buffer.from(tagPart, 'base64'))
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertextPart, 'base64')),
    decipher.final(),
  ]).toString('utf8')
}

// ---------------------------------------------------------------------------
// Input normalisation
//
// These run before anything is stored, so a typo is rejected with a message
// instead of becoming a session that fails to connect ten minutes later.
// ---------------------------------------------------------------------------

/**
 * An MT5 server name as shown in the terminal's login dialog, e.g.
 * `MetaQuotes-Demo`, `ICMarketsSC-Live12` or `Exness-MT5Trial15`.
 *
 * Server names are free-form on the broker side: dots, hyphens, underscores,
 * digits, spaces, and the occasional `+`, `#`, `&`, `'` or `/`. An allowlist of
 * "reasonable" characters rejected real accounts (`Server/../../etc` was the
 * test case that motivated it), so anything printable is accepted now.
 *
 * The value is only ever a login parameter and a stored column — never a path,
 * a URL or a header — so the one thing that must not survive is a control
 * character, which is what would break a header or split a log line.
 */
export function normalizeServerName(raw: unknown): string | null {
  if (typeof raw !== 'string') return null
  if (/[\u0000-\u001f\u007f]/.test(raw)) return null
  const value = raw.trim().replace(/\s+/g, ' ')
  if (value.length < 1 || value.length > 100) return null
  return value
}

/** An MT5 account number: digits only, the same length range MT5 accepts. */
export function normalizeAccountLogin(raw: unknown): string | null {
  if (typeof raw !== 'string' && typeof raw !== 'number') return null
  const value = String(raw).trim()
  if (!/^\d{3,20}$/.test(value)) return null
  return value
}

export function normalizeBrokerName(raw: unknown): string | null {
  if (typeof raw !== 'string') return null
  const value = raw.trim().replace(/\s+/g, ' ')
  if (value.length < 1 || value.length > 100) return null
  return value
}

/**
 * The investor password. MT5 allows short ones, so only the obviously
 * impossible is refused; whitespace is preserved because it can be significant
 * and trimming it would lock the customer out.
 */
export function validateInvestorPassword(raw: unknown): string | null {
  if (typeof raw !== 'string') return null
  if (raw.length < 1 || raw.length > 64) return null
  if (/[\r\n]/.test(raw)) return null
  return raw
}

/**
 * `12345678` -> `•••••678`. Shown back to the customer so they can confirm they
 * pasted the right account without the number being broadcast on a screen share.
 */
export function maskLogin(login: string): string {
  if (login.length <= 3) return '•'.repeat(login.length)
  return `${'•'.repeat(Math.min(login.length - 3, 8))}${login.slice(-3)}`
}
