/**
 * Generates every app icon from the master artwork.
 *
 * The master is a picture, not a drawing: the approved artwork sits at
 * `assets/brand/app-icon-source.jpg` (`.png` works too) and every icon below is
 * one clean reduction of it, cut from a single 1024px square. Nothing is redrawn
 * here, so what was approved is what ships.
 *
 * Pipeline:
 *   1. reduce the source to a 1024px square, flattened onto its own ground
 *   2. read the ground colour from a corner pixel
 *   3. downsample every icon from that one master
 *
 * Step 2 matters: that colour fills the Android background layer, so a launcher
 * never shows a lighter square floating inside its mask.
 *
 * The transparent logo renders are keyed off the same ground, because a picture
 * of a mark has no separate background layer to strip.
 *
 * To change the mark, replace the source picture and re-run; nothing else needs
 * touching.
 *
 * Run: node scripts/make-app-icons.mjs
 * Requires: sharp (already in node_modules)
 */

import { existsSync } from 'node:fs'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { basename, dirname, join } from 'node:path'
import sharp from 'sharp'

const ROOT = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')
const MASTER_1024 = join(ROOT, 'assets/brand/app-icon-1024.png')

/** The approved artwork, in the order it is looked for. */
const SOURCE_NAMES = [
  'assets/brand/app-icon-source.png',
  'assets/brand/app-icon-source.jpg',
  'assets/brand/app-icon-source.jpeg',
]
const SOURCE = SOURCE_NAMES.map((name) => join(ROOT, name)).find((path) => existsSync(path))

/** The single master every icon is reduced from. */
const MASTER_SIDE = 1024

/** The ground the artwork is drawn on — the fallback if a render has no pixel
 *  to sample. */
const FALLBACK_FACE = '#131210'

/**
 * How far a pixel has to be from the ground before it counts as artwork.
 *
 * The source is a JPEG, so the ground is not one exact value: near it is noise.
 * At or below KEY_CLEAR a pixel is background, at or above KEY_SOLID it is
 * opaque, and the band between keeps the anti-aliased edge instead of a jagged
 * cut-out. No part of the mark is anywhere near the ground, so nothing is lost.
 */
const KEY_CLEAR = 18
const KEY_SOLID = 60

/** Reduces the source to the one square every icon comes from, and reports the
 *  ground colour it is drawn on. */
async function buildMaster() {
  if (!SOURCE) {
    throw new Error(
      `missing master artwork: expected ${SOURCE_NAMES.join(', ')}`,
    )
  }

  const square = await sharp(SOURCE)
    .resize(MASTER_SIDE, MASTER_SIDE, { fit: 'cover', kernel: 'lanczos3' })
    .flatten({ background: FALLBACK_FACE })
    .png({ compressionLevel: 9 })
    .toBuffer()

  // The corner pixel is the artwork's own ground — the mark is inset from it —
  // and that exact colour has to fill the Android background layer, or a
  // launcher draws a lighter square inside its mask.
  const { data, info } = await sharp(square).raw().toBuffer({ resolveWithObject: true })
  if (info.channels < 3) throw new Error('master should render as RGB')
  const face = { r: data[0], g: data[1], b: data[2], alpha: 1 }

  return { square, face }
}

/** The same square with the ground keyed out, for the cut-out logo renders. */
async function keyedCutout(face) {
  const { data } = await sharp(SOURCE)
    .resize(MASTER_SIDE, MASTER_SIDE, { fit: 'cover', kernel: 'lanczos3' })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true })

  for (let i = 0; i < data.length; i += 4) {
    const distance = Math.hypot(
      data[i] - face.r,
      data[i + 1] - face.g,
      data[i + 2] - face.b,
    )
    const alpha =
      distance <= KEY_CLEAR
        ? 0
        : distance >= KEY_SOLID
          ? 255
          : Math.round(((distance - KEY_CLEAR) / (KEY_SOLID - KEY_CLEAR)) * 255)
    data[i + 3] = Math.min(data[i + 3], alpha)
  }

  return sharp(data, { raw: { width: MASTER_SIDE, height: MASTER_SIDE, channels: 4 } })
    .png({ compressionLevel: 9 })
    .toBuffer()
}

async function writePng(path, source, size, face) {
  await mkdir(dirname(path), { recursive: true })

  // Opaque on purpose: the App Store rejects an icon with an alpha channel, and
  // every launcher applies its own mask over an opaque square.
  await sharp(source)
    .resize(size, size, { kernel: 'lanczos3' })
    .flatten({ background: face })
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toFile(path)
}

async function writeCutout(path, cutout, size) {
  await mkdir(dirname(path), { recursive: true })
  await sharp(cutout)
    .resize(size, size, { kernel: 'lanczos3' })
    .png({ compressionLevel: 9 })
    .toFile(path)
}

/** file name under the iOS AppIcon set -> pixel size. Names must match Contents.json. */
const IOS = {
  'Icon-App-20x20@1x.png': 20,
  'Icon-App-20x20@2x.png': 40,
  'Icon-App-20x20@3x.png': 60,
  'Icon-App-29x29@1x.png': 29,
  'Icon-App-29x29@2x.png': 58,
  'Icon-App-29x29@3x.png': 87,
  'Icon-App-40x40@1x.png': 40,
  'Icon-App-40x40@2x.png': 80,
  'Icon-App-40x40@3x.png': 120,
  'Icon-App-60x60@2x.png': 120,
  'Icon-App-60x60@3x.png': 180,
  'Icon-App-76x76@1x.png': 76,
  'Icon-App-76x76@2x.png': 152,
  'Icon-App-83.5x83.5@2x.png': 167,
  'Icon-App-1024x1024@1x.png': 1024,
}

const ANDROID = {
  'mipmap-mdpi/ic_launcher.png': 48,
  'mipmap-hdpi/ic_launcher.png': 72,
  'mipmap-xhdpi/ic_launcher.png': 96,
  'mipmap-xxhdpi/ic_launcher.png': 144,
  'mipmap-xxxhdpi/ic_launcher.png': 192,
}

/** Adaptive icon foreground: a 108dp canvas. The supplied artwork already sits
 *  well inside its own tile, so it is not inset a second time — Android's mask
 *  crops the ground, which is the same colour as the background layer. */
const ADAPTIVE = {
  'drawable-mdpi/ic_launcher_foreground.png': 108,
  'drawable-hdpi/ic_launcher_foreground.png': 162,
  'drawable-xhdpi/ic_launcher_foreground.png': 216,
  'drawable-xxhdpi/ic_launcher_foreground.png': 324,
  'drawable-xxxhdpi/ic_launcher_foreground.png': 432,
}

const ADAPTIVE_XML = `<?xml version="1.0" encoding="utf-8"?>
<!-- Adaptive icon: Android 8+ masks the foreground itself, so the launcher
     artwork is split into a background colour and a foreground raster. Both are
     generated by scripts/make-app-icons.mjs. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
`

async function main() {
  const { square, face } = await buildMaster()
  const cutout = await keyedCutout(face)
  console.log(
    `master: ${basename(SOURCE)} -> ${MASTER_SIDE}px, ground rgb(${face.r}, ${face.g}, ${face.b})`,
  )

  await writeFile(MASTER_1024, square)

  const iconSet = join(ROOT, 'mobile_flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset')
  const res = join(ROOT, 'mobile_flutter/android/app/src/main/res')

  let count = 0
  for (const [name, size] of Object.entries(IOS)) {
    await writePng(join(iconSet, name), square, size, face)
    count += 1
  }
  for (const [name, size] of Object.entries(ANDROID)) {
    await writePng(join(res, name), square, size, face)
    count += 1
  }
  for (const [name, size] of Object.entries(ADAPTIVE)) {
    await writePng(join(res, name), square, size, face)
    count += 1
  }

  // Adaptive icon descriptors + the background colour they reference.
  const anydpi = join(res, 'mipmap-anydpi-v26')
  await mkdir(anydpi, { recursive: true })
  await writeFile(join(anydpi, 'ic_launcher.xml'), ADAPTIVE_XML, 'utf8')
  await writeFile(join(anydpi, 'ic_launcher_round.xml'), ADAPTIVE_XML, 'utf8')
  // The adaptive background must be the same ground the foreground carries, or
  // a seam shows where a launcher draws the two layers together — and the icon
  // must never read as a light square on a dark home screen.
  const hex = `#${[face.r, face.g, face.b].map((v) => v.toString(16).padStart(2, '0')).join('').toUpperCase()}`
  await writeFile(
    join(res, 'values/ic_launcher_background.xml'),
    `<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">${hex}</color>\n</resources>\n`,
    'utf8',
  )

  await writePng(join(ROOT, 'public/icon-192.png'), square, 192, face)
  await writePng(join(ROOT, 'public/icon-512.png'), square, 512, face)
  // A maskable icon may be cropped to a circle; the artwork's own margins are
  // already wide enough that no second inset is needed.
  await writePng(join(ROOT, 'public/icon-512-maskable.png'), square, 512, face)
  await writePng(join(ROOT, 'public/apple-touch-icon.png'), square, 180, face)
  // The Play Console listing icon is a separate upload from the APK's icons.
  await writePng(join(ROOT, 'store/icon-512.png'), square, 512, face)
  count += 5

  // The in-app mark, bundled by the Flutter app (see pubspec.yaml).
  await writePng(join(ROOT, 'mobile_flutter/assets/brand/app_icon.png'), square, 512, face)
  count += 1

  // Plain pictures of the mark, for anywhere it is used as a logo rather than a
  // launcher tile: the square tile itself, and the same art cut out of its
  // ground so it can sit on any background.
  await writePng(join(ROOT, 'assets/brand/logo-1024.png'), square, 1024, face)
  await writeCutout(join(ROOT, 'assets/brand/logo-transparent-1024.png'), cutout, 1024)
  count += 2

  // The sizes a logo is actually asked for: 512 is what the Play listing and
  // most profile uploads want, 256 and 128 cover headers and avatars. Each is a
  // single reduction of the same master, never a resize of another icon.
  for (const size of [512, 256, 128]) {
    await writePng(join(ROOT, `assets/brand/logo-${size}.png`), square, size, face)
    count += 1
  }
  for (const size of [512, 256]) {
    await writeCutout(join(ROOT, `assets/brand/logo-transparent-${size}.png`), cutout, size)
    count += 1
  }

  // A favicon is read at 16-32px, where thin detail turns to noise. Embedding a
  // 64px PNG in the SVG keeps the real artwork and stays crisp on retina tabs.
  const faviconPng = await sharp(square).resize(64, 64, { kernel: 'lanczos3' }).png({ compressionLevel: 9 }).toBuffer()
  await writeFile(
    join(ROOT, 'public/favicon.svg'),
    `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">` +
      `<image width="64" height="64" href="data:image/png;base64,${faviconPng.toString('base64')}"/></svg>`,
    'utf8',
  )

  // The AppIcon set must cover every entry Contents.json asks for.
  const contents = JSON.parse(await readFile(join(iconSet, 'Contents.json'), 'utf8'))
  const wanted = contents.images.map((image) => image.filename).filter(Boolean)
  const missing = wanted.filter((name) => !(name in IOS))
  if (missing.length) {
    throw new Error(`Contents.json wants icons this script does not write: ${missing.join(', ')}`)
  }

  console.log(`${count} PNGs written, favicon.svg rewritten (64px embedded)`)
  console.log(`AppIcon entries covered: ${wanted.length}/${wanted.length}`)
}

main().catch((error) => {
  console.error(error.message)
  process.exit(1)
})
