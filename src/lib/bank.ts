/**
 * Bank-transfer details are configuration, not code: they differ per deployment
 * and should never be committed. Read them from the environment and report
 * "not configured" rather than shipping placeholders.
 */

export interface BankDetails {
  bank_name: string
  account_name: string
  account_number: string
  branch: string
}

export function getBankDetails(): BankDetails | null {
  const bank_name = process.env.BANK_NAME
  const account_name = process.env.BANK_ACCOUNT_NAME
  const account_number = process.env.BANK_ACCOUNT_NUMBER
  const branch = process.env.BANK_BRANCH || ''

  if (!bank_name || !account_name || !account_number) return null

  return { bank_name, account_name, account_number, branch }
}

export function isBankConfigured(): boolean {
  return getBankDetails() !== null
}
