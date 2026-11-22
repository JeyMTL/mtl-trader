import { permanentRedirect } from 'next/navigation'

/**
 * `/faq` is the address people type, share and remember; the answers themselves
 * live at `/support`, beside the contact address. A permanent redirect keeps
 * that one copy reachable under both names instead of letting two FAQ pages
 * drift apart.
 */
export default function FaqPage() {
  permanentRedirect('/support')
}
