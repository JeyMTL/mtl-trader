import type { NextConfig } from "next";

// Next.js hydrates from inline bootstrap scripts, which cannot be hashed from
// config, so `'unsafe-inline'` stays for scripts. Everything else is locked to
// the origins the app actually talks to; the dev server additionally needs
// eval for hot reloading, production does not.
const isDev = process.env.NODE_ENV !== 'production';

const CONTENT_SECURITY_POLICY = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ''}`,
  "style-src 'self' 'unsafe-inline'",
  "img-src 'self' data: blob: https://*.supabase.co",
  "media-src 'self' blob: https://*.supabase.co",
  "font-src 'self' data:",
  "connect-src 'self' https://*.supabase.co wss://*.supabase.co",
  "form-action 'self' https://www.paypal.com https://checkout.flutterwave.com",
  "frame-ancestors 'none'",
  "base-uri 'self'",
  "object-src 'none'",
].join('; ');

const nextConfig: NextConfig = {
  transpilePackages: ['xlsx'],
  // No reason to tell the internet which framework and version is behind this.
  poweredByHeader: false,
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'X-Frame-Options', value: 'DENY' },
          // Vercel terminates TLS but does not add HSTS itself. Two years, with
          // subdomains, so a first visit over http can never be the one that
          // leaks a session cookie.
          { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains' },
          { key: 'Content-Security-Policy', value: CONTENT_SECURITY_POLICY },
          // Journal capture needs the camera and microphone on this origin only.
          { key: 'Permissions-Policy', value: 'camera=(self), microphone=(self), geolocation=()' },
        ],
      },
      {
        // A journal is private: keep authenticated screens out of search indexes
        // even if a link leaks.
        source: '/dashboard/:path*',
        headers: [{ key: 'X-Robots-Tag', value: 'noindex, nofollow' }],
      },
    ]
  },
};

export default nextConfig;