#!/usr/bin/env node
/**
 * Renders the Play Store phone screenshots in the marketing layout: warm paper
 * background, a centred headline, black feature pills, and the real capture on
 * a phone frame as the hero. 1080x1920, exactly 9:16.
 *
 *   node scripts/make-phone-mockups.mjs
 *
 * Chrome is driven the same way scripts/make-store-graphics.mjs drives it: a
 * fresh --user-data-dir per shot, so a running browser cannot swallow the
 * screenshot and exit 0 having written nothing.
 *
 * Output is PNG because that is all Chrome writes. Convert to JPEG before
 * upload — Play rejects screenshots with an alpha channel.
 */

import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const work = join(root, 'store', '.mockups')
const shots = join(root, 'store', 'screenshots')

const CHROME_CANDIDATES = [
  process.env.CHROME_PATH,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
]

// Every pill describes something the app actually does — Play's misleading
// content policy applies to text baked into a screenshot as much as to the
// description. No prices, no ratings, no "best" claims.
const mockups = [
  {
    shot: '02-journal.jpg',
    headline: 'Log a trade in <em>seconds</em>.',
    chips: ['Symbol, size and result', 'Strategy tags', 'Chart screenshots', 'Voice notes'],
  },
  {
    shot: '01-desk.jpg',
    headline: 'Your account on <em>one</em> screen.',
    chips: ['Equity curve', 'Win rate and profit factor', 'Best and worst trade', 'Deposits tracked'],
  },
  {
    shot: '03-analytics.jpg',
    headline: 'See which setups <em>actually</em> pay.',
    chips: ['Expectancy per trade', 'Profit factor', 'Max drawdown', 'Monthly P&L'],
  },
  {
    shot: '05-chart-levels.jpg',
    headline: 'Mark entry, stop and <em>target</em>.',
    chips: ['Drag levels on the chart', 'Live OANDA quotes', 'Confirm into the form', 'Nothing saved early'],
  },
  {
    shot: '04-calendar.jpg',
    headline: 'Spot streaks and <em>dead weeks</em>.',
    chips: ['P&L heatmap by day', 'Daily totals', 'Winning and losing days', 'Month summary'],
  },
]

function page({ shot, headline, chips }) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>MTL Trader — ${shot}</title>
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body {
        width: 1080px;
        height: 1920px;
        overflow: hidden;
        background: #f4f1ea;
        color: #14161a;
        font-family: "Segoe UI", Inter, Arial, sans-serif;
        -webkit-font-smoothing: antialiased;
      }
      .stage {
        position: relative;
        width: 1080px;
        height: 1920px;
        overflow: hidden;
        background:
          radial-gradient(720px 720px at 90px 1520px, rgba(213, 164, 78, 0.20), transparent 70%),
          radial-gradient(560px 560px at 1000px 250px, rgba(213, 164, 78, 0.16), transparent 70%),
          #f4f1ea;
      }
      /* Decoration only: a soft gold pebble and ring, kept behind the phone. */
      .pebble {
        position: absolute;
        left: -80px;
        bottom: 150px;
        width: 400px;
        height: 360px;
        border-radius: 58% 42% 55% 45% / 50% 56% 44% 50%;
        background: radial-gradient(125% 125% at 32% 24%, #fffaf0 0%, #f2ddb2 34%, #dcb975 64%, #b98a3d 100%);
        box-shadow: inset -20px -26px 64px rgba(122, 82, 22, 0.26), 0 44px 90px rgba(120, 90, 40, 0.20);
        opacity: 0.92;
      }
      .ring {
        position: absolute;
        right: -90px;
        top: 120px;
        width: 330px;
        height: 330px;
        border-radius: 50%;
        border: 26px solid rgba(213, 164, 78, 0.24);
      }
      .top { position: relative; padding-top: 92px; text-align: center; }
      .wordmark {
        font-size: 20px;
        font-weight: 800;
        letter-spacing: 6px;
        color: #a8762a;
      }
      h1 {
        margin: 22px auto 0;
        max-width: 920px;
        font-size: 62px;
        line-height: 1.08;
        letter-spacing: -1.7px;
        font-weight: 800;
      }
      h1 em { font-style: normal; color: #b07a2a; }
      .chips {
        margin: 34px auto 0;
        max-width: 700px;
        display: flex;
        flex-wrap: wrap;
        justify-content: center;
        gap: 12px;
      }
      .chip {
        display: inline-flex;
        align-items: center;
        gap: 10px;
        padding: 12px 21px 13px;
        border-radius: 999px;
        background: #14161a;
        color: #f7f4ec;
        font-size: 21px;
        font-weight: 600;
        letter-spacing: 0.1px;
        box-shadow: 0 8px 20px rgba(20, 22, 26, 0.16);
      }
      .chip::before {
        content: "";
        width: 9px;
        height: 9px;
        border-radius: 50%;
        background: #d5a44e;
      }
      .phone {
        position: relative;
        margin: 58px auto 0;
        width: 772px;
        padding: 22px;
        border-radius: 76px;
        background: linear-gradient(160deg, #33363b, #101114);
        box-shadow:
          0 54px 96px rgba(70, 52, 20, 0.26),
          0 0 0 1px rgba(0, 0, 0, 0.25),
          inset 0 0 0 2px rgba(255, 255, 255, 0.06);
      }
      .screen {
        position: relative;
        width: 728px;
        height: 1294px;
        border-radius: 56px;
        overflow: hidden;
        background: #0b0d10;
      }
      .screen img { display: block; width: 728px; height: 1294px; }
      .island {
        position: absolute;
        top: 24px;
        left: 50%;
        transform: translateX(-50%);
        width: 198px;
        height: 32px;
        border-radius: 999px;
        background: #05070a;
      }
    </style>
  </head>
  <body>
    <div class="stage">
      <div class="ring"></div>
      <div class="pebble"></div>
      <div class="top">
        <div class="wordmark">MTL TRADER</div>
        <h1>${headline}</h1>
        <div class="chips">
          ${chips.map((chip) => `<span class="chip">${chip}</span>`).join('\n          ')}
        </div>
      </div>
      <div class="phone">
        <div class="screen">
          <img src="../screenshots/${shot}" alt="" />
          <div class="island"></div>
        </div>
      </div>
    </div>
  </body>
</html>
`
}

const chrome = CHROME_CANDIDATES.find((path) => path && existsSync(path))
if (!chrome) {
  console.error('Could not find Chrome. Set CHROME_PATH to the executable and run again.')
  process.exit(1)
}

rmSync(work, { recursive: true, force: true })
mkdirSync(work, { recursive: true })

let failures = 0

for (const mockup of mockups) {
  const name = mockup.shot.replace(/\.jpg$/, '')
  const source = join(work, `${name}.html`)
  const output = join(work, `${name}.png`)

  if (!existsSync(join(shots, mockup.shot))) {
    console.error(`Missing screenshot: ${mockup.shot}`)
    failures += 1
    continue
  }

  writeFileSync(source, page(mockup))

  execFileSync(
    chrome,
    [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--no-first-run',
      '--no-default-browser-check',
      '--virtual-time-budget=3000',
      `--user-data-dir=${join(work, `.chrome-${name}`)}`,
      '--window-size=1080,1920',
      `--screenshot=${output}`,
      pathToFileURL(source).href,
    ],
    { stdio: 'inherit', timeout: 90_000 }
  )

  if (!existsSync(output)) {
    console.error(`Chrome exited without writing ${output}`)
    failures += 1
    continue
  }

  const { size } = statSync(output)
  console.log(`${name}.png  ${Math.round(size / 1024)} KB`)
}

process.exit(failures ? 1 : 0)
