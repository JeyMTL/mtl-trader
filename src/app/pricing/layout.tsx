import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Pricing',
  description: 'One journal, three plans. Start with a 3-day free trial, then pay monthly by card or bank transfer.',
  alternates: { canonical: '/pricing' },
  openGraph: {
    title: 'MTL Ledger pricing',
    description: 'Start with a 3-day free trial, then pay monthly by card or bank transfer.',
    url: '/pricing',
  },
}

export default function PricingLayout({ children }: { children: React.ReactNode }) {
  return children
}
