import { afterEach, describe, expect, it } from 'vitest'
import { isSoloMode, isSoloOwner, mayReadMarketData, soloUserId } from '@/lib/solo'

const OWNER = 'e6b89ecc-c85c-4216-bec5-ee8a72ca2ee6'
const STRANGER = '11111111-2222-3333-4444-555555555555'

afterEach(() => {
  delete process.env.SOLO_USER_ID
})

describe('solo mode', () => {
  it('is off, and lets everyone through, when no owner is configured', () => {
    expect(soloUserId()).toBeNull()
    expect(isSoloMode()).toBe(false)
    expect(mayReadMarketData(OWNER)).toBe(true)
    expect(mayReadMarketData(STRANGER)).toBe(true)
    expect(mayReadMarketData(null)).toBe(true)
  })

  it('serves the owner and refuses everyone else', () => {
    process.env.SOLO_USER_ID = OWNER

    expect(isSoloMode()).toBe(true)
    expect(isSoloOwner(OWNER)).toBe(true)
    expect(mayReadMarketData(OWNER)).toBe(true)
    expect(mayReadMarketData(STRANGER)).toBe(false)
  })

  it('fails closed for a missing id once an owner is set', () => {
    process.env.SOLO_USER_ID = OWNER

    // An unauthenticated read must never be treated as the owner.
    expect(mayReadMarketData(null)).toBe(false)
    expect(mayReadMarketData(undefined)).toBe(false)
    expect(mayReadMarketData('')).toBe(false)
  })

  it('ignores case and surrounding whitespace', () => {
    process.env.SOLO_USER_ID = `  ${OWNER.toUpperCase()}  `

    expect(soloUserId()).toBe(OWNER)
    expect(mayReadMarketData(OWNER.toUpperCase())).toBe(true)
    expect(mayReadMarketData(` ${OWNER} `)).toBe(true)
  })

  it('treats a blank value as unset rather than as an owner named ""', () => {
    process.env.SOLO_USER_ID = '   '

    expect(soloUserId()).toBeNull()
    expect(isSoloOwner('')).toBe(false)
    expect(mayReadMarketData(STRANGER)).toBe(true)
  })
})
