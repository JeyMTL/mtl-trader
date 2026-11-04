#!/usr/bin/env node
/**
 * Renders the Play Store assets that can be generated from a file.
 *
 * Google asks for a 1024x500 PNG feature graphic. Keeping the design in HTML and
 * screenshotting it means the file can be edited without an image editor and
 * re-exported exactly, rather than a binary in the repo with no source.
 *
 *   node scripts/make-store-graphics.mjs
 *
 * Uses the installed Chrome, the same way a person would. There is deliberately
 * no headless-browser dependency: adding Puppeteer for one screenshot would cost
 * more than it saves, and this script is run by hand a few times a year.
 */

import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, statSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')

const CHROME_CANDIDATES = [
  process.env.CHROME_PATH,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
  '/usr/bin/chromium-browser',
]

function findChrome() {
  const found = CHROME_CANDIDATES.find((path) => path && existsSync(path))
  if (!found) {
    console.error(
      'Could not find Chrome. Set CHROME_PATH to the executable and run again.'
    )
    process.exit(1)
  }
  return found
}

const targets = [
  {
    source: join(root, 'store', 'feature-graphic.html'),
    output: join(root, 'store', 'feature-graphic.png'),
    width: 1024,
    height: 500,
  },
]

const chrome = findChrome()
mkdirSync(join(root, 'store'), { recursive: true })

for (const target of targets) {
  if (!existsSync(target.source)) {
    console.error(`Missing source: ${target.source}`)
    process.exit(1)
  }

  // A fresh --user-data-dir per run: reusing the default profile makes Chrome
  // hand the screenshot request to an already-running instance, which writes
  // nothing and exits 0 — the failure mode that looks like success.
  execFileSync(
    chrome,
    [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--no-first-run',
      '--no-default-browser-check',
      `--user-data-dir=${join(root, 'store', '.chrome-profile')}`,
      `--window-size=${target.width},${target.height}`,
      `--screenshot=${target.output}`,
      pathToFileURL(target.source).href,
    ],
    { stdio: 'inherit', timeout: 60_000 }
  )

  if (!existsSync(target.output)) {
    console.error(`Chrome exited without writing ${target.output}`)
    process.exit(1)
  }

  const { size } = statSync(target.output)
  console.log(`${target.output}  ${target.width}x${target.height}  ${Math.round(size / 1024)} KB`)
}
