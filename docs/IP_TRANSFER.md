# Software Transfer & IP Assignment (Template)

> **Template only — not legal advice.** Have a qualified attorney review and
> complete this before signing. Replace every `[...]` placeholder.

## 1. Parties

- **Assignor (seller):** Jeremiah Chipeta, [address], [email]
- **Assignee (buyer):** [legal name], [address], [email]

## 2. Subject matter

The software known as **MTL Trader** (the "Software"), comprising the source
code, documentation, database migrations, and design assets in the repository
`[repo URL]` at the commit identified in Appendix A.

## 3. Assets transferred

Mark each that applies and transfer it on the closing date:

- [ ] Source repository (including full git history in its cleaned state)
- [ ] Domains and DNS: `[domain(s)]`
- [ ] Vercel project and deployment configuration
- [ ] Supabase project (organization, database, auth configuration, RLS policies)
- [ ] PayPal business/REST app (client ID/secret, webhook subscription)
- [ ] Resend account and verified sending domain, if transferred
- [ ] Mobile build assets and Capacitor configuration
- [ ] Design/brand assets and the `docs/` materials

## 4. Rights assigned

Upon full payment, the Assignor assigns to the Assignee all right, title, and
interest in the Software and the assets in Section 3, including copyright and
all associated intellectual property, subject to Section 6 (third-party
components).

## 5. Consideration

Purchase price: **USD $[amount]**, payable as: [terms].

## 6. Third-party components

The Software depends on third-party software and services, including Next.js,
React, Supabase, PayPal, Resend, and Capacitor, each governed by its own license
or terms. These are **not** transferred by this agreement; the Assignee is
responsible for their own accounts and compliance.

## 7. Disclosures and warranty limits

The Assignee acknowledges:

- The Software is an **early-stage MVP**, sold "as is".
- Several integrations require the Assignee's own credentials and setup
  (`RESEND_API_KEY`, `EMAIL_FROM`, `PAYPAL_WEBHOOK_ID`, `BANK_*`).
- The Assignor has removed personal financial data from the repository and its
  history. The Assignee should verify this via `git log --stat`.
- No guarantee of fitness for a particular purpose, uptime, or revenue.

## 8. Confidentiality

Each party keeps the other's non-public business and technical information
confidential, except as required by law.

## 9. Governing law

This agreement is governed by the laws of [jurisdiction].

## 10. Signatures

| | Assignor | Assignee |
|---|---|---|
| Name | | |
| Signature | | |
| Date | | |

---

## Appendix A — Handoff checklist

Complete in order at closing:

1. **Freeze the repo.** Ensure the working tree is clean and pushed; tag it
   (`git tag v1.0-sale`).
2. **Verify data purge.** `git log --all --stat -- trade_data.json trades.xlsx
   public/trades_clean.csv` returns nothing.
3. **Rotate every secret.** The seller's `CRON_SECRET`, PayPal keys, Supabase
   service-role key, and Resend key must be revoked/rotated before transfer.
4. **Transfer ownership** of the repo, Vercel project, Supabase project, DNS,
   PayPal app, and Resend account.
5. **Re-issue credentials** to the Assignee; never hand over the seller's
   existing live secrets.
6. **Apply migrations** in `supabase/migrations/` in filename order on the
   Assignee's Supabase project.
7. **Set environment variables** using `.env.example` as the checklist.
8. **Smoke-test:** `npm run build`, `npm test`,
   `scripts/check-payments.mjs --verify`, `scripts/check-notifications.mjs`.
9. **Remove seller access** and confirm the Assignee can deploy independently.

## Appendix B — Known limitations to disclose

- Mobile wrapper (Capacitor) is a shell; push notifications are not configured
  (`google-services.json` absent).
- Bank-transfer activation still requires manual admin approval.
- Notification emails and webhook reconciliation are inert until the related
  environment variables are set.
- `@next/swc-win32-x64-msvc` fails on some Windows machines and falls back to
  WASM; the build still succeeds.
