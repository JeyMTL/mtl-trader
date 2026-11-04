/**
 * Generates every app icon from the vector master.
 *
 * The master is `assets/brand/app-icon.svg`, so the mark is geometry rather than
 * a photographed mockup. It is rasterised once at 1024px and every smaller icon
 * is a single clean reduction of that, instead of a compound resample of a small
 * tile.
 *
 * Pipeline:
 *   1. rasterise the SVG at 1024px, flattened onto the artwork's own navy
 *   2. read that navy from a corner pixel
 *   3. downsample every icon from that one master
 *
 * Step 2 matters: the colour fills every inset panel and the Android background
 * layer, so a launcher never shows a lighter square floating inside its mask.
 *
 * To change the mark, edit the SVG and re-run; nothing else needs touching.
 *
 * Run: node scripts/make-app-icons.mjs
 * Requires: sharp (already in node_modules)
 */

import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import sharp from 'sharp'

const ROOT = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')
const SVG = join(ROOT, 'assets/brand/app-icon.svg')
const MASTER_1024 = join(ROOT, 'assets/brand/app-icon-1024.png')

/** The single master every icon is reduced from. */
const MASTER_SIDE = 1024

/** Rasterise well above the master, then reduce once, so curve flattening and
 *  gradient banding never survive into the output pixels. */
const DENSITY = 384

/** The navy the artwork is drawn on — the fallback if a render has no pixel to
 *  sample. */
const FALLBACK_FACE = '#0b1a28'

/** Maskable web icons can be cropped to a circle, so the art is inset. */
const MASKABLE_INSET = 0.82

/**
 * Adaptive icons crop to a mask and only guarantee the inner 72dp of 108dp, so
 * the art is drawn slightly inside that safe zone and the rest is filled with
 * the artwork's own navy — which is also the background layer, so the two meet
 * invisibly.
 */
const ADAPTIVE_CONTENT = 0.9

async function buildMaster() {
  const square = await sharp(SVG, { density: DENSITY })
    .resize(MASTER_SIDE, MASTER_SIDE, { fit: 'cover', kernel: 'lanczos3' })
    .flatten({ background: FALLBACK_FACE })
    .png({ compressionLevel: 9 })
    .toBuffer()

  // The corner pixel is the artwork's own navy — the mark is inset from it — and
  // that exact colour has to fill the inset panels and the Android background
  // layer, or a launcher draws a lighter square inside its mask.
  const { data, info } = await sharp(square).raw().toBuffer({ resolveWithObject: true })
  if (info.channels < 3) throw new Error('master should render as RGB')
  const face = { r: data[0], g: data[1], b: data[2], alpha: 1 }

  return { square, face }
}

async function writePng(path, source, size, { inset = 1, face }) {
  await mkdir(dirname(path), { recursive: true })

  let pipeline
  if (inset < 1) {
    const inner = Math.round(size * inset)
    // No feathered edge is needed: the master's own background is the fill
    // colour, so the inset panel dissolves into it.
    const art = await sharp(source).resize(inner, inner, { kernel: 'lanczos3' }).png().toBuffer()

    pipeline = sharp({ create: { width: size, height: size, channels: 4, background: face } }).composite([
      { input: art, top: Math.round((size - inner) / 2), left: Math.round((size - inner) / 2), blend: 'over' },
    ])
  } else {
    pipeline = sharp(source).resize(size, size, { kernel: 'lanczos3' })
  }

  // Opaque on purpose: the App Store rejects an icon with an alpha channel, and
  // every launcher applies its own mask over an opaque square.
  await pipeline
    .flatten({ background: face })
    .png({ compressionLevel: 9, adaptiveFiltering: true })
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

/** Adaptive icon foreground: 108dp canvas, mark in the middle 62%. */
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

/** The artwork without its background, for the cut-out logo render. The ground
 *  is one identifiable group in the SVG, and failing loudly beats quietly
 *  writing an opaque file and calling it transparent. */
async function markOnlySvg() {
  const source = await readFile(SVG, 'utf8')
  const stripped = source.replace(/\s*<g id="ground">[\s\S]*?<\/g>/, '')
  if (stripped === source) throw new Error('app-icon.svg has no <g id="ground"> group to strip')
  return stripped
}

async function main() {
  const { square, face } = await buildMaster()
  const cutoutSource = await markOnlySvg()
  console.log(`vector master: ${MASTER_SIDE}px, face rgb(${face.r}, ${face.g}, ${face.b})`)

  await writeFile(MASTER_1024, square)

  const iconSet = join(ROOT, 'mobile_flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset')
  const res = join(ROOT, 'mobile_flutter/android/app/src/main/res')

  let count = 0
  for (const [name, size] of Object.entries(IOS)) {
    await writePng(join(iconSet, name), square, size, { face })
    count += 1
  }
  for (const [name, size] of Object.entries(ANDROID)) {
    await writePng(join(res, name), square, size, { face })
    count += 1
  }
  for (const [name, size] of Object.entries(ADAPTIVE)) {
    await writePng(join(res, name), square, size, { inset: ADAPTIVE_CONTENT, face })
    count += 1
  }

  // Adaptive icon descriptors + the background colour they reference.
  const anydpi = join(res, 'mipmap-anydpi-v26')
  await mkdir(anydpi, { recursive: true })
  await writeFile(join(anydpi, 'ic_launcher.xml'), ADAPTIVE_XML, 'utf8')
  await writeFile(join(anydpi, 'ic_launcher_round.xml'), ADAPTIVE_XML, 'utf8')
  // The adaptive background must be the same navy the foreground is padded with,
  // so no seam shows where a launcher draws the two layers together — and so the
  // icon never reads as a light square on a dark home screen.
  const hex = `#${[face.r, face.g, face.b].map((v) => v.toString(16).padStart(2, '0')).join('').toUpperCase()}`
  await writeFile(
    join(res, 'values/ic_launcher_background.xml'),
    `<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">${hex}</color>\n</resources>\n`,
    'utf8',
  )

  await writePng(join(ROOT, 'public/icon-192.png'), square, 192, { face })
  await writePng(join(ROOT, 'public/icon-512.png'), square, 512, { face })
  await writePng(join(ROOT, 'public/icon-512-maskable.png'), square, 512, { inset: MASKABLE_INSET, face })
  await writePng(join(ROOT, 'public/apple-touch-icon.png'), square, 180, { face })
  count += 4

  // The in-app mark, bundled by the Flutter app (see pubspec.yaml).
  await writePng(join(ROOT, 'mobile_flutter/assets/brand/app_icon.png'), square, 512, { face })
  count += 1

  // Plain pictures of the mark, for anywhere it is used as a logo rather than a
  // launcher tile: the square tile itself, and the same art cut out of its
  // ground so it can sit on any background.
  await writePng(join(ROOT, 'assets/brand/logo-1024.png'), square, 1024, { face })
  await sharp(Buffer.from(cutoutSource), { density: DENSITY })
    .resize(MASTER_SIDE, MASTER_SIDE, { fit: 'cover', kernel: 'lanczos3' })
    .png({ compressionLevel: 9 })
    .toFile(join(ROOT, 'assets/brand/logo-transparent-1024.png'))
  count += 2

  // The sizes a logo is actually asked for: 512 is what the Play listing and
  // most profile uploads want, 256 and 128 cover headers and avatars. Each is a
  // single reduction of the same master, never a resize of another icon.
  for (const size of [512, 256, 128]) {
    await writePng(join(ROOT, `assets/brand/logo-${size}.png`), square, size, { face })
    count += 1
  }
  for (const size of [512, 256]) {
    await sharp(Buffer.from(cutoutSource), { density: DENSITY })
      .resize(size, size, { fit: 'cover', kernel: 'lanczos3' })
      .png({ compressionLevel: 9 })
      .toFile(join(ROOT, `assets/brand/logo-transparent-${size}.png`))
    count += 1
  }

  // A favicon is read at 16-32px, where the thin bars turn to noise. Embedding a
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
