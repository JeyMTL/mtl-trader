/**
 * MT5 broker directory.
 *
 * The sync form used to ask for the broker name in a blank text field, which
 * meant a customer had to remember exactly what their terminal called it. This
 * is the list behind the searchable picker: the brokers a retail MT5 trader is
 * likely to hold an account with, each with the server families its terminal
 * shows — live **and** demo/trial — so both kinds of account are reachable from
 * the picker instead of only the live one.
 *
 * Two rules keep it honest:
 *
 *  - Names are the ones printed in the MT5 login dialog, not marketing names.
 *  - `servers` is a hint list, never a whitelist. Brokers add, rename and retire
 *    servers constantly, and numbering varies per account, so the form accepts
 *    any server the customer types and the API stores it as given. A suggestion
 *    is a shortcut for the common spelling, nothing more.
 *
 * Searching is plain substring matching over the name, aliases and servers,
 * ranked so an exact or prefix hit on the name comes first. It runs in the
 * browser and on the server from the same table, so the web form, the mobile
 * picker and `/api/brokers` can never disagree.
 */

export interface Mt5Broker {
  /** Broker name as MT5 shows it in its login dialog. */
  name: string
  /** Former names and common spellings, so "HotForex" still finds HFM. */
  aliases?: string[]
  /** Server names we can offer as one-tap suggestions. Free text is allowed. */
  servers: string[]
}

export const MT5_BROKERS: Mt5Broker[] = [
  { name: 'IC Markets', aliases: ['ICMarkets'], servers: [
      'ICMarketsSC-Live01', 'ICMarketsSC-Live02', 'ICMarketsEU-Live01',
      'ICMarketsSC-Demo', 'ICMarketsEU-Demo',
    ] },
  { name: 'Pepperstone', servers: [
      'Pepperstone-Live01', 'Pepperstone-Live02',
      'Pepperstone-Demo01', 'Pepperstone-Demo02',
    ] },
  { name: 'Exness', servers: [
      // Exness names demo servers `Exness-MT5Trial<N>` (Trial2, Trial8, Trial15…);
      // "Exness-Demo" is not a real server and MT5 rejects the login. Trial
      // first, because a test account is what most people connect before going
      // live.
      'Exness-MT5Trial8', 'Exness-MT5Trial15', 'Exness-MT5Trial2',
      'Exness-MT5Real8', 'Exness-MT5Real2',
    ] },
  { name: 'XM', aliases: ['XM Global', 'XMGlobal'], servers: [
      'XMGlobal-Real 5', 'XMGlobal-Real 8',
      'XMGlobal-Demo 5', 'XMGlobal-Demo 8',
    ] },
  { name: 'FXTM', aliases: ['ForexTime'], servers: [
      'FXTM-Live01', 'FXTM-Live02', 'FXTM-Demo01', 'FXTM-Demo02',
    ] },
  { name: 'RoboForex', servers: [
      'RoboForex-Pro', 'RoboForex-ECN', 'RoboForex-Demo',
    ] },
  { name: 'Tickmill', servers: [
      'Tickmill-Live', 'TickmillUK-Live', 'Tickmill-Demo', 'TickmillUK-Demo',
    ] },
  { name: 'Vantage', aliases: ['Vantage FX', 'Vantage Markets'], servers: [
      'VantageInternational-Live 1', 'VantageInternational-Live 10',
      'VantageInternational-Demo',
    ] },
  { name: 'FP Markets', aliases: ['First Prudential Markets', 'FPMarkets'], servers: [
      'FPMarkets-Live', 'FPMarkets-Live2', 'FPMarkets-Demo',
    ] },
  { name: 'Admirals', aliases: ['Admiral Markets', 'AdmiralMarkets'], servers: [
      'AdmiralMarkets-Live', 'AdmiralMarkets-Demo',
    ] },
  { name: 'Deriv', aliases: ['Binary.com'], servers: [
      'Deriv-Server', 'Deriv-Server 02', 'Deriv-Demo',
    ] },
  { name: 'Fusion Markets', servers: [
      'FusionMarkets-Live', 'FusionMarkets-Demo',
    ] },
  { name: 'ThinkMarkets', aliases: ['ThinkForex'], servers: [
      'ThinkMarkets-Live', 'ThinkMarkets-Demo',
    ] },
  { name: 'Eightcap', servers: ['Eightcap-Live', 'Eightcap-Demo'] },
  { name: 'Axi', aliases: ['AxiTrader'], servers: [
      'Axi-US50-Live', 'Axi-US50-Demo',
    ] },
  { name: 'MultiBank Group', aliases: ['MultiBank'], servers: [
      'MultiBank-Live', 'MultiBank-Demo',
    ] },
  { name: 'PU Prime', aliases: ['PUPrime'], servers: [
      'PUPrime-Live', 'PUPrime-Demo',
    ] },
  { name: 'JustMarkets', aliases: ['JustForex'], servers: [
      'JustMarkets-Live', 'JustMarkets-Demo',
    ] },
  { name: 'HFM', aliases: ['HotForex'], servers: ['HFM-Live', 'HFM-Demo'] },
  { name: 'FBS', servers: ['FBS-Real', 'FBS-Demo'] },
  { name: 'Octa', aliases: ['OctaFX'], servers: ['OctaFX-Real', 'OctaFX-Demo'] },
  { name: 'AvaTrade', aliases: ['Ava FX'], servers: ['Ava-Real', 'Ava-Demo'] },
  { name: 'XTB', aliases: ['X-Trade Brokers'], servers: ['XTB-MT5', 'XTB-Demo'] },
  { name: 'Alpari', servers: ['Alpari-MT5', 'Alpari-MT5-Demo'] },
  { name: 'InstaForex', servers: ['InstaForex-Server', 'InstaForex-Demo'] },
  { name: 'NordFX', servers: ['NordFX-Real', 'NordFX-Demo'] },
  { name: 'LiteFinance', aliases: ['LiteForex'], servers: [
      'LiteFinance-Live', 'LiteFinance-Demo',
    ] },
  { name: 'FXCM', servers: ['FXCM-Live', 'FXCM-Demo'] },
  { name: 'OANDA', servers: ['OANDA-Live', 'OANDA-Demo'] },
  { name: 'Swissquote', servers: ['Swissquote-Live', 'Swissquote-Demo'] },
  { name: 'Dukascopy', aliases: ['Dukascopy Bank'], servers: [
      'Dukascopy-Live', 'Dukascopy-Demo',
    ] },
  { name: 'Capital.com', aliases: ['Capital Com'], servers: [
      'Capital-Live', 'Capital-Demo',
    ] },
  { name: 'Skilling', servers: ['Skilling-Live', 'Skilling-Demo'] },
  { name: 'BlackBull Markets', aliases: ['BlackBull'], servers: [
      'BlackBull-Live', 'BlackBull-Demo',
    ] },
  { name: 'ACY Securities', aliases: ['ACY'], servers: [
      'ACY-Live', 'ACY-Demo',
    ] },
  { name: 'Errante', servers: ['Errante-Live', 'Errante-Demo'] },
  { name: 'M4Markets', servers: ['M4Markets-Live', 'M4Markets-Demo'] },
  { name: 'Scope Markets', servers: ['ScopeMarkets-Live', 'ScopeMarkets-Demo'] },
  { name: 'CPT Markets', servers: ['CPTMarkets-Live', 'CPTMarkets-Demo'] },
  { name: 'FinPros', servers: ['FinPros-Live', 'FinPros-Demo'] },
  { name: 'Hantec Markets', aliases: ['Hantec'], servers: [
      'HantecMarkets-Live', 'HantecMarkets-Demo',
    ] },
  { name: 'Doo Prime', aliases: ['DooPrime'], servers: [
      'DooPrime-Live', 'DooPrime-Demo',
    ] },
  { name: 'BDSwiss', servers: ['BDSwiss-Live', 'BDSwiss-Demo'] },
  { name: 'FXPrimus', aliases: ['FXPRIMUS'], servers: [
      'FXPrimus-Live', 'FXPrimus-Demo',
    ] },
  { name: 'Weltrade', servers: ['Weltrade-Live', 'Weltrade-Demo'] },
  { name: 'AMarkets', servers: ['AMarkets-Live', 'AMarkets-Demo'] },
  { name: 'FreshForex', servers: ['FreshForex-Live', 'FreshForex-Demo'] },
  { name: 'Forex4you', servers: ['Forex4you-Live', 'Forex4you-Demo'] },
  { name: 'Grand Capital', servers: ['GrandCapital-Live', 'GrandCapital-Demo'] },
  { name: 'Gerchik & Co', aliases: ['Gerchik'], servers: [
      'Gerchik-Live', 'Gerchik-Demo',
    ] },
  { name: 'FxPro', servers: [
      'FxPro-Live01', 'FxPro-Live02', 'FxPro-Demo01',
    ] },
  { name: 'City Index', servers: ['CityIndex-Live', 'CityIndex-Demo'] },
  { name: 'Trade Nation', servers: ['TradeNation-Live', 'TradeNation-Demo'] },
  { name: 'StarTrader', servers: ['StarTrader-Live', 'StarTrader-Demo'] },
  { name: 'INFINOX', servers: ['INFINOX-Live', 'INFINOX-Demo'] },
  { name: 'CXM Direct', servers: ['CXM-Live', 'CXM-Demo'] },
  { name: 'VPFX', servers: ['VPFX-Live', 'VPFX-Demo'] },
  { name: 'LandPrime', servers: ['LandPrime-Live', 'LandPrime-Demo'] },
  { name: 'Moneta Markets', servers: ['MonetaMarkets-Live', 'MonetaMarkets-Demo'] },
  { name: 'XS.com', aliases: ['XS'], servers: ['XS-Live', 'XS-Demo'] },
  { name: 'ZFX', servers: ['ZFX-Live', 'ZFX-Demo'] },
  { name: 'DBG Markets', servers: ['DBGMarkets-Live', 'DBGMarkets-Demo'] },
  { name: 'Windsor Brokers', servers: ['Windsor-Live', 'Windsor-Demo'] },
  { name: 'Amana Capital', servers: ['AmanaCapital-Live', 'AmanaCapital-Demo'] },
  { name: 'ADSS', servers: ['ADSS-Live', 'ADSS-Demo'] },
  { name: 'Equiti', servers: ['Equiti-Live', 'Equiti-Demo'] },
  { name: 'Ox Securities', servers: ['OxSecurities-Live', 'OxSecurities-Demo'] },
  { name: 'Taurex', servers: ['Taurex-Live', 'Taurex-Demo'] },
  { name: 'TradeQuo', servers: ['TradeQuo-Live', 'TradeQuo-Demo'] },
  { name: 'GMI Edge', aliases: ['GMI'], servers: ['GMIEdge-Live', 'GMIEdge-Demo'] },
  { name: 'Traders Trust', aliases: ['TTCM'], servers: [
      'TradersTrust-Live', 'TradersTrust-Demo',
    ] },
  { name: 'OneRoyal', servers: ['OneRoyal-Live', 'OneRoyal-Demo'] },
  { name: 'IronFX', servers: ['IronFX-Live', 'IronFX-Demo'] },
  { name: 'TeleTrade', servers: ['TeleTrade-Live', 'TeleTrade-Demo'] },
  { name: 'FIBO Group', servers: ['FIBO-Live', 'FIBO-Demo'] },
  { name: 'LQDFX', servers: ['LQDFX-Live', 'LQDFX-Demo'] },
  { name: 'Purple Trading', servers: ['PurpleTrading-Live', 'PurpleTrading-Demo'] },
  { name: 'CFI', aliases: ['CFI Financial'], servers: ['CFI-Live', 'CFI-Demo'] },
  { name: 'easyMarkets', servers: ['easyMarkets-Live', 'easyMarkets-Demo'] },
]

/**
 * Case- and punctuation-insensitive form used for every comparison, so
 * "ICMarketsSC-Live01", "ic markets" and "IC MARKETS." all meet in the middle.
 */
export function normalizeBrokerQuery(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
}

interface Entry {
  broker: Mt5Broker
  name: string
  words: string[]
  aliases: string[]
  servers: string[]
}

const ENTRIES: Entry[] = MT5_BROKERS.map((broker) => {
  const name = normalizeBrokerQuery(broker.name)
  return {
    broker,
    name,
    words: name.split(' ').filter(Boolean),
    aliases: (broker.aliases ?? [])
      .map((alias) => normalizeBrokerQuery(alias))
      .filter(Boolean),
    servers: broker.servers.map((server) => normalizeBrokerQuery(server)),
  }
})

/**
 * Lower is better. Anything unmatched returns -1 and drops out of the list.
 * An exact name beats a prefix, a prefix beats a word prefix, and everything
 * name-shaped beats a hit inside a server name.
 */
function rank(entry: Entry, phrase: string, terms: string[]): number {
  if (entry.name === phrase) return 0
  if (entry.name.startsWith(phrase)) return 1
  if (entry.words.some((word) => word.startsWith(phrase))) return 2
  if (entry.aliases.some((alias) => alias === phrase || alias.startsWith(phrase))) {
    return 3
  }
  if (entry.name.includes(phrase)) return 4
  if (entry.aliases.some((alias) => alias.includes(phrase))) return 5
  if (entry.servers.some((server) => server.includes(phrase))) return 6

  // Words typed out of order ("markets fusion") still match as long as every
  // one of them lands somewhere in the name or an alias.
  const scattered = terms.every(
    (term) =>
      entry.name.includes(term) || entry.aliases.some((alias) => alias.includes(term))
  )
  return scattered ? 7 : -1
}

/**
 * Every broker matching `query`, best match first. An empty query returns the
 * whole directory alphabetically, which is what the picker shows before the
 * customer types anything.
 */
export function searchMt5Brokers(query: string, limit = 20): Mt5Broker[] {
  const max = Math.max(0, Math.floor(limit))
  if (max === 0) return []

  const phrase = normalizeBrokerQuery(query)
  if (!phrase) {
    return [...MT5_BROKERS]
      .sort((a, b) => a.name.localeCompare(b.name))
      .slice(0, max)
  }

  const terms = phrase.split(' ').filter(Boolean)
  return ENTRIES.map((entry) => ({ entry, score: rank(entry, phrase, terms) }))
    .filter((row) => row.score >= 0)
    .sort(
      (a, b) =>
        a.score - b.score ||
        a.entry.broker.name.localeCompare(b.entry.broker.name)
    )
    .slice(0, max)
    .map((row) => row.entry.broker)
}

/** The directory entry for a name the customer picked or typed, if we have one. */
export function findMt5Broker(name: string): Mt5Broker | null {
  const target = normalizeBrokerQuery(name)
  if (!target) return null

  const exact = ENTRIES.find(
    (entry) =>
      entry.name === target ||
      entry.aliases.some((alias) => alias === target)
  )
  if (exact) return exact.broker

  const prefixed = ENTRIES.find(
    (entry) =>
      entry.name.startsWith(target) ||
      entry.aliases.some((alias) => alias.startsWith(target))
  )
  return prefixed ? prefixed.broker : null
}

/**
 * Known servers for the chosen broker, narrowed by whatever is already in the
 * server field. Empty when the broker is not in the directory — the field stays
 * free text.
 */
export function serverSuggestions(
  brokerName: string,
  query = '',
  limit = 8
): string[] {
  const broker = findMt5Broker(brokerName)
  if (!broker) return []

  const term = normalizeBrokerQuery(query)
  const servers = term
    ? broker.servers.filter((server) =>
        normalizeBrokerQuery(server).includes(term)
      )
    : broker.servers

  return servers.slice(0, Math.max(0, limit))
}

export type ServerKind = 'demo' | 'live'

/**
 * Whether a server name points at a demo/test account.
 *
 * MT5 has no flag to read before logging in, but every broker that ships a
 * separate demo server names it: Demo, Trial (Exness), Practice, Test. Anything
 * else is a live server.
 */
export function classifyServer(server: string): ServerKind {
  return /demo|trial|practice|test/i.test(server) ? 'demo' : 'live'
}

/**
 * Suggestions split by account type, so the form can label them instead of
 * showing one undifferentiated row.
 *
 * Each group is capped separately on purpose: a broker with a dozen live servers
 * must not push its one demo server off the list, because the demo server is
 * exactly what someone testing the app is looking for.
 */
export function serverGroups(
  brokerName: string,
  query = '',
  limitPerGroup = 4
): { demo: string[]; live: string[] } {
  const max = Math.max(0, Math.floor(limitPerGroup))
  const matches = serverSuggestions(brokerName, query, 100)
  return {
    demo: matches
      .filter((server) => classifyServer(server) === 'demo')
      .slice(0, max),
    live: matches
      .filter((server) => classifyServer(server) === 'live')
      .slice(0, max),
  }
}
