// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { MarketView } from '@/components/market-view'

function frame(): HTMLIFrameElement {
  return screen.getByTitle(/market chart by TradingView/i) as HTMLIFrameElement
}

describe('MarketView', () => {
  afterEach(() => {
    cleanup()
  })

  it('renders the TradingView frame on the default instrument', () => {
    render(<MarketView />)

    const url = new URL(frame().getAttribute('src') ?? '')
    expect(url.host).toBe('s.tradingview.com')
    expect(url.searchParams.get('symbol')).toBe('FX:EURUSD')
    expect(url.searchParams.get('interval')).toBe('15')

    // It says whose prices these are; the old chart's claims are gone.
    expect(screen.getByText(/Live market prices from TradingView/i)).toBeTruthy()
    expect(screen.queryByText(/saved to your account/i)).toBeNull()
  })

  it('reloads the frame when the instrument or size changes', () => {
    render(<MarketView />)

    fireEvent.change(screen.getByLabelText('Instrument'), { target: { value: 'XAUUSD' } })
    expect(new URL(frame().getAttribute('src') ?? '').searchParams.get('symbol')).toBe(
      'OANDA:XAUUSD'
    )

    fireEvent.click(screen.getByRole('button', { name: '1h' }))
    expect(new URL(frame().getAttribute('src') ?? '').searchParams.get('interval')).toBe('60')
  })

  it('opens on the requested instrument when the view carries one', () => {
    render(<MarketView initialSymbol="NAS100" />)

    expect(new URL(frame().getAttribute('src') ?? '').searchParams.get('symbol')).toBe(
      'CAPITALCOM:US100'
    )
  })
})
