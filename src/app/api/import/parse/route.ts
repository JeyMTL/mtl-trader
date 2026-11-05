import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'
import { rateLimit } from '@/lib/rate-limit'
import { apiError } from '@/lib/log'
import { extractTrades, parseFileToRows } from '@/lib/import-parser'

/**
 * Parses an uploaded history file with the same importer the web dashboard runs
 * in the browser, including the legacy `.xls` reader the phone build has no
 * equivalent for.
 *
 * This returns a preview, not an import: the caller writes the rows with its own
 * Supabase session, exactly as the web desk does. Only files the device cannot
 * read itself should come here.
 */

// Vercel caps a serverless request body at 4.5 MB; leave room for the envelope.
const MAX_PARSE_BYTES = 4 * 1024 * 1024

export async function POST(req: Request) {
  const user = await getAuthUser(req)
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const limit = await rateLimit(`import-parse:${user.id}`, 30, 60 * 60 * 1000)
  if (!limit.ok) {
    return NextResponse.json(
      { error: 'Too many imports. Try again shortly.' },
      {
        status: 429,
        headers: { 'Retry-After': String(Math.ceil(limit.retryAfterMs / 1000)) },
      }
    )
  }

  let form: FormData
  try {
    form = await req.formData()
  } catch {
    return NextResponse.json(
      { error: 'Send the file as a form upload.' },
      { status: 400 }
    )
  }

  const file = form.get('file')
  if (!(file instanceof File)) {
    return NextResponse.json({ error: 'No file was uploaded.' }, { status: 400 })
  }
  if (file.size > MAX_PARSE_BYTES) {
    const size = (file.size / (1024 * 1024)).toFixed(1)
    return NextResponse.json(
      {
        error: `That file is ${size} MB. Excel parsing on the server is limited to 4 MB — save it as .xlsx or CSV, which the app reads on the phone.`,
      },
      { status: 413 }
    )
  }

  try {
    const rows = await parseFileToRows(file)
    if (rows.length === 0) {
      return NextResponse.json(
        {
          error:
            'No readable data in this file. Export it as CSV from MT5 or your broker and try again.',
        },
        { status: 422 }
      )
    }
    return NextResponse.json({ trades: extractTrades(rows) })
  } catch (error) {
    return apiError(
      'import.parse',
      error,
      422,
      'Could not read this file. Try exporting it as CSV.'
    )
  }
}
