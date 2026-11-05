import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Pricing',
  description: 'One journal, three plans. Start with a 14-day free trial, then pay monthly by PayPal or bank transfer.',
  alternates: { canonical: '/pricing' },
  openGraph: {
    title: 'MTL Trader pricing',
    description: 'Start with a 14-day free trial, then pay monthly by PayPal or bank transfer.',
    url: '/pricing',
  },
}

export default function PricingLayout({ children }: { children: React.ReactNode }) {
  return children
}
