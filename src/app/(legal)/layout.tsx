import Link from 'next/link'
import { Logo } from '@/components/logo'

export default function LegalLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-background">
      <header className="border-b border-border">
        <div className="mx-auto flex h-16 max-w-3xl items-center justify-between px-4">
          <Link href="/" className="flex items-center gap-2" aria-label="MTL Trader home">
            <Logo size="sm" />
          </Link>
          <nav className="flex items-center gap-4 text-xs text-gray-500">
            <Link href="/terms" className="hover:text-white">Terms</Link>
            <Link href="/privacy" className="hover:text-white">Privacy</Link>
            <Link href="/refunds" className="hover:text-white">Refunds</Link>
            <Link href="/support" className="hover:text-white">Support</Link>
          </nav>
        </div>
      </header>

      <main className="mx-auto max-w-3xl px-4 py-12">{children}</main>

      <footer className="border-t border-border py-8">
        <div className="mx-auto flex max-w-3xl flex-col items-center justify-between gap-2 px-4 text-xs text-gray-500 sm:flex-row">
          <p>&copy; 2026 MTL Trader. All rights reserved.</p>
          <div className="flex gap-4">
            <Link href="/terms" className="hover:text-white">Terms</Link>
            <Link href="/privacy" className="hover:text-white">Privacy</Link>
            <Link href="/refunds" className="hover:text-white">Refunds</Link>
            <Link href="/delete-account" className="hover:text-white">Delete account</Link>
            <Link href="/support" className="hover:text-white">Support</Link>
            <Link href="/" className="hover:text-white">Home</Link>
          </div>
        </div>
      </footer>
    </div>
  )
}
