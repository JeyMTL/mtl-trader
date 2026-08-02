import { NextResponse } from 'next/server'
import { PLANS } from '@/lib/plans'

export async function GET() {
  return NextResponse.json(PLANS)
}
