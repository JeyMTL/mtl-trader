# Google Play store listing — copy and assets

Everything the Play Console's **Store listing → Default** asks for, ready to
paste. Limits are Play's; the character counts below are the real ones.

## App name (30 max, used: 27)

```text
MTL Trader: Trading Journal
```

## Short description (80 max)

```text
Journal every trade, find your edge, fix the leaks that cost you money.
```

## Full description (4000 max)

```text
MTL Trader is a trading journal for Forex and CFD traders who want to know whether they really have an edge — and where it comes from.

Log a trade in seconds: symbol, direction, entry, stop, target, size and result, with an optional chart screenshot or voice note attached. Your notes stay with the trade, and strategy tags let you compare the setups you actually trade.

WHAT YOU SEE

• Dashboard — equity curve, balance, win rate, profit factor, expectancy and maximum drawdown, updated as you log.
• P&L calendar — a month heatmap of profit and loss, so streaks, revenge days and dead weeks are visible at a glance.
• Analytics — results by hour and session, so you can tell a real edge from a lucky run.
• AI trade review — your own notes and your own statistics are sent to an AI model, which writes back the mistakes you keep repeating. Optional, and you can ignore it.
• Journal — chart screenshots and voice notes kept with each trade.
• Backtester — replay past setups and see how a change to your rules would have played out.

Read at a glance between sessions: dark interface, gold accents, monospaced numbers, charts that fit a phone.

PLANS

A 30-day trial unlocks everything, with no card required. After it ends, your journal and analytics stay readable, and a subscription reopens the desk. Basic adds the full calendar, time edge, charts, photos and voice notes and 30 AI reviews a month; Pro raises the review allowance and adds the backtester and market replay. Every plan logs unlimited trades — paying never means logging fewer trades than the trial allowed.

Subscriptions bought in this app are sold and billed by Google Play, and you can manage or cancel them any time from your Play account.

YOUR DATA

Your trades are yours. You can delete your account and its data from Settings at any time. Data is encrypted in transit, never sold, and never used for advertising. Privacy policy: https://mtl-trader.vercel.app/privacy

MTL Trader is a record-keeping and analysis tool for trades you place yourself. It does not place orders, does not connect to a broker to trade, and does not provide investment advice.
```

## Graphics already rendered

| Console field | File | Verified |
| --- | --- | --- |
| App icon (512×512, 32-bit PNG, no alpha) | `store/icon-512.png` | 512×512, RGB, no alpha channel |
| Feature graphic (1024×500) | `store/feature-graphic.png` | 1024×500, RGB |

Regenerate either after editing its source with
`node scripts/make-store-graphics.mjs`.

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

- Privacy policy URL: `https://mtl-trader.vercel.app/privacy`
- Account deletion URL: `https://mtl-trader.vercel.app/delete-account`
- Support / website: `https://mtl-trader.vercel.app` (`/support` returns 200)
- Contact email: `jfx064@gmail.com`
