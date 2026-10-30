import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { ThemeProvider } from "@/lib/theme";
import { ToastProvider } from "@/components/toast";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const APP_URL = (process.env.NEXT_PUBLIC_APP_URL || 'https://mtl-trader.vercel.app').replace(/\/$/, '')

export const metadata: Metadata = {
  metadataBase: new URL(APP_URL),
  title: {
    default: 'MTL Trader - Professional Trading Journal',
    template: '%s — MTL Trader',
  },
  description: "Track, analyze, and improve your trading performance with MTL Trader. The professional trading journal for serious traders.",
  applicationName: 'MTL Trader',
  alternates: { canonical: '/' },
  openGraph: {
    type: 'website',
    siteName: 'MTL Trader',
    title: 'MTL Trader - Professional Trading Journal',
    description: 'Log every fill, read the decisions behind the P&L, and let the journal find your edge.',
    url: '/',
  },
  twitter: {
    card: 'summary_large_image',
    title: 'MTL Trader - Professional Trading Journal',
    description: 'Log every fill, read the decisions behind the P&L, and let the journal find your edge.',
  },
  icons: {
    icon: '/favicon.svg',
  },
  manifest: '/manifest.webmanifest',
  // Used when the app is opened from a phone browser / home-screen shortcut;
  // inside the Capacitor shell the native config takes over.
  appleWebApp: {
    capable: true,
    title: 'MTL Trader',
    statusBarStyle: 'black-translucent',
  },
  formatDetection: { telephone: false },
};

// `viewportFit: cover` plus the safe-area CSS in globals.css is what lets the
// app draw under the notch and home indicator instead of floating above it.
export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
  themeColor: [
    { media: '(prefers-color-scheme: dark)', color: '#08090c' },
    { media: '(prefers-color-scheme: light)', color: '#f6f4ef' },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-dvh flex flex-col bg-background text-foreground">
        <ThemeProvider>
          <ToastProvider>{children}</ToastProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
