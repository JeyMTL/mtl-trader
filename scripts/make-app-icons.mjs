/**
 * Generates every app icon from one master image.
 *
 * The master is the rendered monogram artwork in `assets/brand/`. It is used as
 * artwork rather than redrawn: the bevel, the patina and the green arrow are the
 * brand, and a hand-approximated SVG lost all of it.
 *
 * Pipeline:
 *   1. crop the tile face out of the artwork (measured, not eyeballed)
 *   2. build ONE 1024px square master, upscaled once with Lanczos and given a
 *      light unsharp pass
 *   3. downsample every icon from that master
 *
 * Step 3 is why this produces better small icons than resampling the ~440px
 * tile 24 times: each size is one clean reduction of a large source instead of a
 * compound resample. The 1024 master is also written out as a file, because the
 * App Store wants exactly that and it must match the in-app mark.
 *
 * Honest ceiling: the artwork's tile is ~440px, so this 1024 is a 2.3x
 * interpolation with a gentle sharpen. Redraw the tile natively at 1024+ and
 * replace `assets/brand/app-icon-master.jpg` to remove that limit entirely.
 *
 * Two facts about the source drive the crop, both measured:
 *   - The tile face is blue-dominant (b - r > 10, dark); nothing else on the page
 *     is. Measured: x 486..921, y 109..556, with the mark inside occupying
 *     x 490..921, y 112..549 — so cropping the face cannot clip a letter.
 *   - Its rounded corners sit on a white page, so the square is masked with a
 *     rounded rect of a slightly larger radius and the cut corners flattened to
 *     the tile's own navy. No white can survive at any size.
 *
 * Run: node scripts/make-app-icons.mjs
 * Requires: sharp (already in node_modules)
 */

import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import sharp from 'sharp'

const ROOT = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')
const MASTER = join(ROOT, 'assets/brand/app-icon-master.jpg')
const MASTER_1024 = join(ROOT, 'assets/brand/app-icon-1024.png')

const luma = (r, g, b) => 0.299 * r + 0.587 * g + 0.114 * b

/** Tile face: blue over red, and dark. The page is a cool near-white, the drop
 *  shadow is neutral, and the gold wordmark is red-dominant — all excluded. */
const NAVY = (r, g, b) => b - r > 10 && luma(r, g, b) < 140

/** The single master every icon is reduced from. */
const MASTER_SIDE = 1024

/** Art inset inside the tile so a bevel edge never meets the icon border. */
const ART_INSET = 0.94

/** Corner radius of the final square. Larger than the artwork's ~0.21 so the
 *  mask always covers the white it was drawn on. */
const RADIUS = 0.245

/** Maskable web icons can be cropped to a circle, so the tile is inset. */
const MASKABLE_INSET = 0.82

/**
 * Adaptive icons crop to a mask and only guarantee the inner 72dp of 108dp, so
 * the mark is drawn at 62% and the rest is filled with the tile's own navy —
 * which is also the background layer, so the two meet invisibly.
 */
const ADAPTIVE_CONTENT = 0.62

async function analyse() {
  const { data, info } = await sharp(MASTER).removeAlpha().raw().toBuffer({ resolveWithObject: true })
  const { width, height, channels } = info

  let minX = width
  let minY = height
  let maxX = -1
  let maxY = -1
  let sumR = 0
  let sumG = 0
  let sumB = 0
  let sumN = 0

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * channels
      const r = data[i]
      const g = data[i + 1]
      const b = data[i + 2]
      if (!NAVY(r, g, b)) continue

      if (x < minX) minX = x
      if (x > maxX) maxX = x
      if (y < minY) minY = y
      if (y > maxY) maxY = y
      // The mean of the face is also the fill colour, so insets, adaptive
      // backgrounds and rebuilt corners use the artwork's own navy.
      sumR += r
      sumG += g
      sumB += b
      sumN += 1
    }
  }

  if (maxX < 0) throw new Error('no blue-dominant pixels found — is the master the right artwork?')

  return {
    tile: { x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1 },
    face: { r: Math.round(sumR / sumN), g: Math.round(sumG / sumN), b: Math.round(sumB / sumN), alpha: 1 },
  }
}

function roundedMask(side, radius) {
  return Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${side}" height="${side}">` +
      `<rect width="${side}" height="${side}" rx="${Math.round(side * radius)}" fill="#fff"/></svg>`,
  )
}

async function buildMaster() {
  const { tile, face } = await analyse()
  const inner = Math.round(MASTER_SIDE * ART_INSET)
  const offset = Math.round((MASTER_SIDE - inner) / 2)

  // Trimmed 2px inside the detected face: the boundary row/column carries a
  // blend of the tile and the page it stands on, which otherwise survives as a
  // 1px white line down the icon's right edge.
  const TRIM = 2

  // Squaring the face stretches it by the difference between its sides — 3% on
  // this master, below the point of visibility on a bevel edge. Cropping to a
  // square instead would shave the arrow head off the right edge.
  const art = await sharp(MASTER)
    .extract({ left: tile.x + TRIM, top: tile.y + TRIM, width: tile.w - TRIM * 2, height: tile.h - TRIM * 2 })
    .resize(inner, inner, { kernel: 'lanczos3' })
    // One gentle unsharp pass after the upscale. Any stronger and the bevel
    // picks up dark halos that read as dirt at 48px.
    .sharpen({ sigma: 0.8, m1: 1.2, m2: 0.5 })
    .png()
    .toBuffer()

  const composed = await sharp({ create: { width: MASTER_SIDE, height: MASTER_SIDE, channels: 4, background: face } })
    .composite([{ input: art, top: offset, left: offset, blend: 'over' }])
    .png()
    .toBuffer()

  const square = await sharp(composed)
    .ensureAlpha()
    .composite([{ input: roundedMask(MASTER_SIDE, RADIUS), blend: 'dest-in' }])
    .flatten({ background: face })
    .png()
    .toBuffer()

  // The inset panels (maskable icon, adaptive foreground) need the colour the
  // artwork's face actually has *at its edge*, not its average: the face is
  // graded top-to-bottom, so a mean fill reads as a lighter square floating in
  // the artwork. Sampled from a corner-free strip near the top edge.
  const strip = await sharp(art)
    .extract({
      left: Math.round(inner * 0.2),
      top: Math.round(inner * 0.02),
      width: Math.round(inner * 0.6),
      height: Math.max(2, Math.round(inner * 0.02)),
    })
    .stats()
  const edgeFace = {
    r: Math.round(strip.channels[0].mean),
    g: Math.round(strip.channels[1].mean),
    b: Math.round(strip.channels[2].mean),
    alpha: 1,
  }

  return { square, face, edgeFace, tile }
}

async function writePng(path, source, size, { inset = 1, face, feather = 0 }) {
  await mkdir(dirname(path), { recursive: true })

  let pipeline
  if (inset < 1) {
    const inner = Math.round(size * inset)
    let art = await sharp(source).resize(inner, inner, { kernel: 'lanczos3' }).ensureAlpha().png().toBuffer()

    if (feather > 0) {
      // The artwork's own background is graded, so its straight edge never
      // matches a flat fill: inside a circular launcher mask that reads as a
      // square panel floating in the circle. A blurred alpha edge dissolves the
      // seam into the tile's own navy instead.
      const soft = Buffer.from(
        `<svg xmlns="http://www.w3.org/2000/svg" width="${inner}" height="${inner}">` +
          `<defs><filter id="f" x="-20%" y="-20%" width="140%" height="140%">` +
          `<feGaussianBlur stdDeviation="${Math.round(inner * feather)}"/></filter></defs>` +
          `<rect x="0" y="0" width="${inner}" height="${inner}" fill="#fff" filter="url(#f)"/></svg>`,
      )
      art = await sharp(art).composite([{ input: soft, blend: 'dest-in' }]).png().toBuffer()
    }

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

async function main() {
  const { square, face, edgeFace, tile } = await buildMaster()
  console.log(`tile face: ${tile.w}x${tile.h} at ${tile.x},${tile.y} -> ${MASTER_SIDE}px master`)
  console.log(`face colour: rgb(${face.r}, ${face.g}, ${face.b})  edge fill: rgb(${edgeFace.r}, ${edgeFace.g}, ${edgeFace.b})`)

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
    await writePng(join(res, name), square, size, { inset: ADAPTIVE_CONTENT, face, feather: 0.05 })
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
  await writePng(join(ROOT, 'public/icon-512-maskable.png'), square, 512, { inset: MASKABLE_INSET, face, feather: 0.05 })
  await writePng(join(ROOT, 'public/apple-touch-icon.png'), square, 180, { face })
  count += 4

  // The in-app mark, bundled by the Flutter app (see pubspec.yaml).
  await writePng(join(ROOT, 'mobile_flutter/assets/brand/app_icon.png'), square, 512, { face })
  count += 1

  // A favicon is read at 16-32px, where the bevel is noise. Embedding a 64px
  // PNG in the SVG keeps the real artwork and stays crisp on retina tabs.
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
