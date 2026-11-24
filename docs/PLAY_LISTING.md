# Google Play store listing — copy and assets

Everything the Play Console's **Store listing → Default** asks for, ready to
paste. Limits are Play's; the character counts below are the real ones.

## App name (30 max, used: 27)

```text
MTL Ledger: Trading Journal
```

## Short description (80 max)

```text
Journal every trade, find your edge, fix the leaks that cost you money.
```

## Full description (4000 max)

```text
MTL Ledger is a trading journal for Forex and CFD traders who want to know whether they really have an edge — and where it comes from.

Log a trade in seconds: symbol, direction, entry, stop, target, size and result, with an optional chart screenshot or voice note attached. Your notes stay with the trade, and strategy tags let you compare the setups you actually trade.

WHAT YOU SEE

• Dashboard — equity curve, balance, win rate, profit factor, expectancy and maximum drawdown, updated as you log.
• P&L calendar — a month heatmap of profit and loss, so streaks, revenge days and dead weeks are visible at a glance.
• Analytics — results by hour and session, so you can tell a real edge from a lucky run.
• AI journal summary — your own notes and statistics are sent to an AI model, which writes back a summary of what your results show: where the numbers came from, what looks strong and what looks risky. It reads your journal and describes it; it does not rate you or suggest a trade. Optional, and you can ignore it.
• Daily stop — set a loss limit and the journal refuses new entries once you reach it. On Android you can also let it cover MetaTrader 5 on your phone for the rest of the day; that optional part uses Android's Accessibility service only to notice when MetaTrader 5 is in front (it never reads screen content) and to draw the cover over it, is switched on in Android Settings, and can be turned off there at any time.
• Journal — chart screenshots and voice notes kept with each trade.
• Backtester — test entry and exit rules you wrote yourself against saved past sessions, with win rate, profit factor and drawdown for those rules. It is a simulation on stored history: nothing connects to a broker and no order is placed.

Read at a glance between sessions: dark interface, gold accents, monospaced numbers, charts that fit a phone.

PLANS

A 3-day trial unlocks everything, with no card required. After it ends you stay on the Free plan: 30 trades a month, your journal and charts, the time edge, the setup matrix and the prop-firm simulator. Basic adds the full calendar and analytics, time edge, the setup matrix, the chart desk with levels pinned straight off the chart, 30s and 45s candles, MT5 sync, the soft daily lock, prop-firm rules, photos and voice notes; Pro adds the hard lock, 40 AI journal summaries a month, the backtester with saved runs, the rules builder that turns a description of your own conditions into editable test rules, market replay, notifications and the 5s, 10s and 15s candles, plus priority support. Basic and Pro log unlimited trades, so paying never means logging fewer trades than the trial allowed; Free is the one tier with a monthly cap.

Subscriptions bought in this app are sold and billed by Google Play, and you can manage or cancel them any time from your Play account.

YOUR DATA

Your trades are yours. You can delete your account and its data from Settings at any time. Data is encrypted in transit, never sold, and never used for advertising. Privacy policy: https://mtlledger.com/privacy

MTL Ledger is a record-keeping and analysis tool for trades you place yourself. It does not place orders, does not connect to a broker to trade, and does not provide investment advice.
```

## Graphics already rendered

| Console field | File | Verified |
| --- | --- | --- |
| App icon (512×512, 32-bit PNG, no alpha) | `store/icon-512.png` | 512×512, RGB, no alpha channel |
| Feature graphic (1024×500) | `store/feature-graphic.png` | 1024×500, RGB |

Regenerate the feature graphic after editing `store/feature-graphic.html` with
`node scripts/make-store-graphics.mjs`. The icon is rendered from the approved
artwork at `assets/brand/app-icon-source.jpg`: replace that picture, then run
`node scripts/make-app-icons.mjs`, which rewrites `store/icon-512.png`.

## Screenshots (2–8, 1080×1920)

Five finished files in `store/mockups/`, each 1080×1920 (exactly 9:16), RGB
JPEG with no alpha. Upload in filename order — the first is what search results
and the listing show before a tap:

| Order | File | Screen |
| --- | --- | --- |
| 1 | `01-journal.jpg` | Journal — trade list with strategy tags |
| 2 | `02-desk.jpg` | Desk — balance, equity curve, drawdown |
| 3 | `03-analytics.jpg` | Analytics — performance summary |
| 4 | `04-chart-levels.jpg` | Chart — entry, stop and target levels |
| 5 | `05-calendar.jpg` | Calendar — monthly P&L heatmap |

Rebuilt from the artwork in `~/Downloads` and the captures in
`store/screenshots/` with:

```bash
python scripts/prep-gemini-mockups.py   # crops the status bar, feathers, backdrops
node scripts/make-gemini-mockups.mjs    # Chrome -> 1080×1920 PNG
```

Then one Pillow pass converts the PNGs in `store/.gemini/` to RGB JPEG, because
Play rejects screenshots carrying an alpha channel.

Known soft spots: `02-desk.jpg` still shows the unloaded skeleton card under the
equity curve, and `05-calendar.jpg` has a month with a single winning day.
Re-capture those two and rerun both commands; the layout picks the new content
up unchanged.

The flat, frameless versions in `store/screenshots/` are the fallback — same
screens, no phone and no caption.

## Fields that are not on the Assets step

- Privacy policy URL: `https://mtlledger.com/privacy`
- Account deletion URL: `https://mtlledger.com/delete-account`
- Support / website: `https://mtlledger.com` (`/support` returns 200)
- Contact email: `support@mtlledger.com`
