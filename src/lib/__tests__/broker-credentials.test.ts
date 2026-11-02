import { describe, expect, it, beforeEach, afterEach } from 'vitest'
import {
  credentialKeyConfigured,
  decryptCredential,
  encryptCredential,
  maskLogin,
  normalizeAccountLogin,
  normalizeBrokerName,
  normalizeServerName,
  validateInvestorPassword,
} from '@/lib/broker-credentials'

const KEY_A = Buffer.alloc(32, 1).toString('base64')
const KEY_B = Buffer.alloc(32, 2).toString('base64')

describe('credential encryption', () => {
  const original = process.env.SYNC_CREDENTIAL_KEY

  beforeEach(() => {
    process.env.SYNC_CREDENTIAL_KEY = KEY_A
  })

  afterEach(() => {
    if (original === undefined) delete process.env.SYNC_CREDENTIAL_KEY
    else process.env.SYNC_CREDENTIAL_KEY = original
  })

  it('round-trips a password', () => {
    const sealed = encryptCredential('inv-Passw0rd!')
    expect(sealed.startsWith('v1:')).toBe(true)
    expect(sealed).not.toContain('inv-Passw0rd!')
    expect(decryptCredential(sealed)).toBe('inv-Passw0rd!')
  })

  it('produces a different ciphertext each time', () => {
    expect(encryptCredential('same')).not.toBe(encryptCredential('same'))
  })

  it('refuses to decrypt with a different key', () => {
    const sealed = encryptCredential('secret')
    process.env.SYNC_CREDENTIAL_KEY = KEY_B
    expect(() => decryptCredential(sealed)).toThrow()
  })

  it('detects tampering with the ciphertext', () => {
    const sealed = encryptCredential('secret')
    const parts = sealed.split(':')
    const flipped = Buffer.from(parts[3], 'base64')
    flipped[0] = flipped[0] ^ 0xff
    parts[3] = flipped.toString('base64')
    expect(() => decryptCredential(parts.join(':'))).toThrow()
  })

  it('rejects an unknown format version instead of guessing', () => {
    expect(() => decryptCredential('v2:a:b:c')).toThrow(/Unrecognised credential format/)
  })

  it('fails closed when no key is configured', () => {
    delete process.env.SYNC_CREDENTIAL_KEY
    expect(credentialKeyConfigured()).toBe(false)
    expect(() => encryptCredential('secret')).toThrow(/SYNC_CREDENTIAL_KEY is not configured/)
  })

  it('rejects a key of the wrong length', () => {
    process.env.SYNC_CREDENTIAL_KEY = Buffer.alloc(16, 9).toString('base64')
    expect(() => encryptCredential('secret')).toThrow(/32 bytes/)
  })
})

describe('connection input validation', () => {
  it('accepts real MT5 server names', () => {
    expect(normalizeServerName('  ICMarketsSC-Live12  ')).toBe('ICMarketsSC-Live12')
    expect(normalizeServerName('Deriv-Server 02')).toBe('Deriv-Server 02')
    expect(normalizeServerName('Exness-MT5Trial15')).toBe('Exness-MT5Trial15')
  })

  it('accepts every server spelling a broker may use', () => {
    // Brokers are free to punctuate server names however they like; an
    // allowlist here rejected real accounts, so only control characters fail.
    for (const server of [
      'MetaQuotes-Demo',
      'XMGlobal-Real 5',
      'Forex.com-Live 1',
      'Trade#1-Demo',
      'R&D-Live',
      "O'Hara-Live",
      'server/../../etc',
    ]) {
      expect(normalizeServerName(server)).toBe(server)
    }
  })

  it('rejects server names that are empty, too long or carry control characters', () => {
    expect(normalizeServerName('')).toBeNull()
    expect(normalizeServerName('   ')).toBeNull()
    expect(normalizeServerName('a'.repeat(101))).toBeNull()
    expect(normalizeServerName('evil\r\nX-Injected: 1')).toBeNull()
    expect(normalizeServerName('tab\tseparated')).toBeNull()
    expect(normalizeServerName(42)).toBeNull()
  })

  it('accepts digits-only account numbers only', () => {
    expect(normalizeAccountLogin('12345678')).toBe('12345678')
    expect(normalizeAccountLogin(87654321)).toBe('87654321')
    expect(normalizeAccountLogin(' 100200300 ')).toBe('100200300')
    expect(normalizeAccountLogin('1234 5678')).toBeNull()
    expect(normalizeAccountLogin('12')).toBeNull()
    expect(normalizeAccountLogin('1'.repeat(21))).toBeNull()
    expect(normalizeAccountLogin('abc12345')).toBeNull()
  })

  it('trims a broker name but rejects an empty one', () => {
    expect(normalizeBrokerName('  IC Markets ')).toBe('IC Markets')
    expect(normalizeBrokerName('   ')).toBeNull()
  })

  it('keeps password whitespace but rejects newlines', () => {
    expect(validateInvestorPassword(' pass word ')).toBe(' pass word ')
    expect(validateInvestorPassword('line\r\nbreak')).toBeNull()
    expect(validateInvestorPassword('')).toBeNull()
    expect(validateInvestorPassword('x'.repeat(65))).toBeNull()
    expect(validateInvestorPassword(null)).toBeNull()
  })

  it('masks all but the last three digits', () => {
    expect(maskLogin('12345678')).toBe('•••••678')
    expect(maskLogin('123')).toBe('•••')
    expect(maskLogin('1234')).toBe('•234')
  })
})
