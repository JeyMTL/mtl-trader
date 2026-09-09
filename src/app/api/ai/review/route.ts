import { NextResponse } from 'next/server'
import { getAuthUser } from '@/lib/server-auth'

interface ReviewPayload {
  totalTrades: number
  wins: number
  losses: number
  winRate: number
  totalPnl: number
  profitFactor: number
  maxDrawdown: number
  expectancy: number
  avgWin: number
  avgLoss: number
  symbols: Array<{ symbol: string; trades: number; winRate: number; pnl: number }>
  weekdays: Array<{ day: string; wins: number; losses: number; pnl: number }>
  months: Array<{ month: string; pnl: number }>
}

export async function POST(req: Request) {
  try {
    const user = await getAuthUser(req)
    if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

    const apiKey = process.env.OPENAI_API_KEY
    if (!apiKey) {
      return NextResponse.json({ error: 'AI reviews are not configured yet. Add OPENAI_API_KEY in Vercel.' }, { status: 503 })
    }

    const summary = await req.json() as ReviewPayload
    if (!summary || typeof summary.totalTrades !== 'number') {
      return NextResponse.json({ error: 'Invalid analytics summary' }, { status: 400 })
    }

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: process.env.OPENAI_MODEL || 'gpt-4o-mini',
        temperature: 0.3,
        max_tokens: 700,
        messages: [
          {
            role: 'system',
            content: 'You are a careful trading journal analyst. Give concise, evidence-based educational feedback, not financial advice or predictions. Identify up to three strengths, up to three risks, and three specific journal or process actions. Do not recommend a specific asset, trade, entry, exit, or position size. Say when the sample is too small. Use headings and bullet points.',
          },
          {
            role: 'user',
            content: `Review this anonymized trading summary:\n${JSON.stringify(summary)}`,
          },
        ],
      }),
    })

    const data = await response.json() as { choices?: Array<{ message?: { content?: string } }>; error?: { message?: string } }
    if (!response.ok) {
      return NextResponse.json({ error: data.error?.message || 'AI provider request failed' }, { status: 502 })
    }

    const review = data.choices?.[0]?.message?.content
    if (!review) return NextResponse.json({ error: 'AI returned an empty review' }, { status: 502 })

    return NextResponse.json({ review })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
