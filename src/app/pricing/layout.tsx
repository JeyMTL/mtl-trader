import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Pricing',
  description: 'One journal, three plans. Start with a 3-day free trial, then pay by card, monthly or yearly.',
  alternates: { canonical: '/pricing' },
  openGraph: {
    title: 'MTL Ledger pricing',
    description: 'Start with a 3-day free trial, then pay by card, monthly or yearly.',
    url: '/pricing',
  },
}

export default function PricingLayout({ children }: { children: React.ReactNode }) {
  return children
}
