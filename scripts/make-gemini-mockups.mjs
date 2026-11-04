#!/usr/bin/env node
/**
 * Renders the Play Store screenshots from the Gemini artwork in Downloads.
 * 1080x1920, exactly 9:16, RGB JPEG once converted (Play rejects alpha).
 *
 *   python scripts/prep-gemini-mockups.py
 *   node scripts/make-gemini-mockups.mjs
 *   (PNG -> JPEG, see the note at the bottom)
 *
 * Chrome is driven the same way scripts/make-store-graphics.mjs drives it: a
 * fresh --user-data-dir per shot, so a running browser cannot swallow the
 * screenshot and exit 0 having written nothing.
 */

import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const work = join(root, 'store', '.gemini')

const CHROME_CANDIDATES = [
  process.env.CHROME_PATH,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
]

// Captions describe what the screen actually shows. No prices, no ratings, no
// superlatives — baked text falls under the same misleading-content policy as
// the store description.
const slides = [
  {
    out: '01-journal',
    kind: 'art',
    headline: ['Every trade,', 'logged in seconds.'],
    sub: 'Symbol, size, result and strategy tags.',
  },
  {
    out: '02-desk',
    kind: 'art',
    headline: ['Your account on', 'one screen.'],
    sub: 'Balance, equity curve and drawdown.',
  },
  {
    out: '03-analytics',
    kind: 'phone',
    headline: ['See which setups', 'actually pay.'],
    sub: 'Expectancy, profit factor and drawdown.',
  },
  {
    out: '04-chart-levels',
    kind: 'art',
    headline: ['Mark entry, stop', 'and target.'],
    sub: 'Drag the levels, then confirm into the form.',
  },
  {
    out: '05-calendar',
    kind: 'art',
    headline: ['Spot streaks and', 'dead weeks.'],
    sub: 'A P&L heatmap for the whole month.',
  },
]

function artMarkup(slide) {
  // The baked phone already carries its own bezel, shadow and backdrop, all
  // feathered into the blurred copy of the same scene behind it.
  return `<img class="art" src="${slide.out}-art.png" alt="" />`
}

function phoneMarkup(slide) {
  return `<div class="phone">
        <div class="screen">
          <img src="${slide.out}-screen.jpg" alt="" />
          <div class="island"></div>
        </div>
      </div>`
}

function page(slide) {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>MTL Trader — ${slide.out}</title>
    <style>
      * { box-sizing: border-box; margin: 0; padding: 0; }
      body {
        width: 1080px;
        height: 1920px;
        overflow: hidden;
        background: #05070b;
        font-family: "Segoe UI", Inter, Arial, sans-serif;
        -webkit-font-smoothing: antialiased;
      }
      .stage { position: relative; width: 1080px; height: 1920px; overflow: hidden; }
      .bg {
        position: absolute;
        inset: 0;
        background: url("${slide.out}-bg.jpg") center / cover no-repeat;
      }
      .head { position: absolute; left: 86px; top: 100px; width: 908px; }
      h1 {
        font-size: 64px;
        line-height: 1.14;
        font-weight: 300;
        letter-spacing: -0.8px;
        color: #f3f0e9;
      }
      h1 span { display: block; color: #c2985e; }
      .sub {
        margin-top: 26px;
        font-size: 26px;
        line-height: 1.4;
        font-weight: 400;
        color: #9c9a94;
      }
      .art {
        position: absolute;
        left: 50%;
        top: 358px;
        transform: translateX(-50%);
        height: 1500px;
        width: auto;
      }
      .phone {
        position: absolute;
        left: 50%;
        top: 358px;
        transform: translateX(-50%);
        width: 730px;
        height: 1168px;
        padding: 22px;
        border-radius: 58px;
        background: linear-gradient(160deg, #44474d 0%, #191c20 42%, #0a0c0f 100%);
        box-shadow:
          0 0 0 2px rgba(196, 198, 204, 0.42),
          0 0 0 7px rgba(16, 18, 22, 0.95),
          0 34px 74px rgba(0, 0, 0, 0.62);
      }
      .screen {
        position: relative;
        width: 686px;
        height: 1124px;
        border-radius: 40px;
        overflow: hidden;
        background: #000;
      }
      /* Fitted exactly: the screenshot is cropped to the screen's aspect, so
         nothing is centre-cropped and no edge sits closer than the other. */
      .screen img { display: block; width: 100%; height: 100%; }
      .island {
        position: absolute;
        top: 16px;
        left: 50%;
        transform: translateX(-50%);
        width: 150px;
        height: 26px;
        border-radius: 999px;
        background: #05070a;
      }
    </style>
  </head>
  <body>
    <div class="stage">
      <div class="bg"></div>
      <div class="head">
        <h1>${slide.headline[0]}<span>${slide.headline[1]}</span></h1>
        <div class="sub">${slide.sub}</div>
      </div>
      ${slide.kind === 'art' ? artMarkup(slide) : phoneMarkup(slide)}
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

mkdirSync(work, { recursive: true })

let failures = 0

for (const slide of slides) {
  const html = join(work, `${slide.out}.html`)
  const png = join(work, `${slide.out}.png`)
  const needs = slide.kind === 'art' ? `${slide.out}-art.png` : `${slide.out}-screen.jpg`
  const bg = `${slide.out}-bg.jpg`
  if (!existsSync(join(work, bg))) {
    console.error(`Missing ${bg} — run: python scripts/prep-gemini-mockups.py`)
    failures += 1
    continue
  }

  if (!existsSync(join(work, needs))) {
    console.error(`Missing ${needs} — run: python scripts/prep-gemini-mockups.py`)
    failures += 1
    continue
  }

  writeFileSync(html, page(slide))

  execFileSync(
    chrome,
    [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--allow-file-access-from-files',
      '--force-device-scale-factor=1',
      '--no-first-run',
      '--no-default-browser-check',
      '--virtual-time-budget=3000',
      `--user-data-dir=${join(work, `.chrome-${slide.out}`)}`,
      '--window-size=1080,1920',
      `--screenshot=${png}`,
      pathToFileURL(html).href,
    ],
    { stdio: 'inherit', timeout: 90_000 }
  )

  if (!existsSync(png)) {
    console.error(`Chrome exited without writing ${png}`)
    failures += 1
    continue
  }

  console.log(`${slide.out}.png  ${Math.round(statSync(png).size / 1024)} KB`)
}

process.exit(failures ? 1 : 0)
