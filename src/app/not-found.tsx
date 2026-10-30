import Link from 'next/link'
import { ArrowLeft } from 'lucide-react'
import { Logo } from '@/components/logo'

export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-background px-4">
      <Link href="/" className="mb-8">
        <Logo size="md" />
      </Link>
      <p className="num text-5xl font-semibold tracking-tight text-white">404</p>
      <h1 className="mt-3 text-lg font-semibold text-white">That page isn&apos;t here</h1>
      <p className="mt-1 max-w-sm text-center text-sm text-gray-400">
        The link may be old, or the address may have a typo.
      </p>
      <Link href="/dashboard" className="btn btn-primary mt-6">
        <ArrowLeft className="h-4 w-4" />
        Back to the journal
      </Link>
    </div>
  )
}
