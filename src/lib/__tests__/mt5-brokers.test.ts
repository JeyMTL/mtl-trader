import { describe, expect, it } from 'vitest'
import {
  MT5_BROKERS,
  classifyServer,
  findMt5Broker,
  searchMt5Brokers,
  serverGroups,
  serverSuggestions,
} from '@/lib/mt5-brokers'

describe('MT5 broker directory', () => {
  it('lists every broker alphabetically for an empty query', () => {
    const all = searchMt5Brokers('', 100)
    expect(all).toHaveLength(MT5_BROKERS.length)
    const names = all.map((broker) => broker.name)
    expect(names).toEqual([...names].sort((a, b) => a.localeCompare(b)))
  })

  it('has a unique name for every entry', () => {
    const names = MT5_BROKERS.map((broker) => broker.name)
    expect(new Set(names).size).toBe(names.length)
  })

  it('offers both a live and a demo/trial server for every broker', () => {
    // The picker is how a customer reaches a test account, so a broker with no
    // demo suggestion sends them to the live server by default.
    for (const broker of MT5_BROKERS) {
      expect(broker.servers.length).toBeGreaterThanOrEqual(2)
      expect(
        broker.servers.some((server) => /demo|trial|test/i.test(server)),
        `${broker.name} has no demo/trial server`
      )
      expect(
        broker.servers.some((server) => !/demo|trial|test/i.test(server)),
        `${broker.name} has no live server`
      )
    }
  })

  it('matches on a prefix', () => {
    const results = searchMt5Brokers('pep')
    expect(results[0]?.name).toBe('Pepperstone')
  })

  it('ignores case, punctuation and spacing', () => {
    for (const query of ['ic markets', 'ICMarkets', 'IC MARKETS.', '  ic-markets  ']) {
      expect(searchMt5Brokers(query)[0]?.name).toBe('IC Markets')
    }
  })

  it('finds a broker by a former name', () => {
    expect(searchMt5Brokers('HotForex')[0]?.name).toBe('HFM')
    expect(searchMt5Brokers('octafx')[0]?.name).toBe('Octa')
  })

  it('finds a broker from its server name', () => {
    expect(searchMt5Brokers('ICMarketsSC-Live01')[0]?.name).toBe('IC Markets')
  })

  it('matches words typed out of order', () => {
    expect(searchMt5Brokers('markets fusion')[0]?.name).toBe('Fusion Markets')
  })

  it('returns nothing for an unknown broker', () => {
    expect(searchMt5Brokers('definitely-not-a-broker')).toEqual([])
  })

  it('respects the limit and never returns a negative slice', () => {
    expect(searchMt5Brokers('', 5)).toHaveLength(5)
    expect(searchMt5Brokers('', 0)).toEqual([])
    expect(searchMt5Brokers('ic', -3)).toEqual([])
  })
})

describe('MT5 server suggestions', () => {
  it('returns known servers for a broker', () => {
    expect(serverSuggestions('IC Markets')).toContain('ICMarketsSC-Live01')
  })

  it('narrows by the query already in the field', () => {
    expect(serverSuggestions('IC Markets', 'demo')).toEqual([
      'ICMarketsSC-Demo',
      'ICMarketsEU-Demo',
    ])
  })

  it('surfaces an Exness demo server before a live one', () => {
    expect(serverSuggestions('Exness')[0]).toBe('Exness-MT5Trial8')
  })

  it('stays empty for a broker outside the directory', () => {
    expect(findMt5Broker('Some Local Broker')).toBeNull()
    expect(serverSuggestions('Some Local Broker')).toEqual([])
  })

  it('resolves a broker from a partial name', () => {
    expect(findMt5Broker('exne')?.name).toBe('Exness')
  })

  it('separates demo servers from live ones for the picker', () => {
    const groups = serverGroups('IC Markets')
    expect(groups.demo).toEqual(['ICMarketsSC-Demo', 'ICMarketsEU-Demo'])
    expect(groups.live).toContain('ICMarketsSC-Live01')
    expect(groups.live.every((server) => classifyServer(server) === 'live')).toBe(true)
  })

  it('never lets a long live list push the demo server out', () => {
    const groups = serverGroups('Exness', '', 1)
    expect(groups.demo).toEqual(['Exness-MT5Trial8'])
    expect(groups.live).toHaveLength(1)
  })

  it('reads trial and practice servers as demo', () => {
    expect(classifyServer('Exness-MT5Trial15')).toBe('demo')
    expect(classifyServer('Practice-Server')).toBe('demo')
    expect(classifyServer('Pepperstone-Live01')).toBe('live')
  })
})
