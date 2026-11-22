/**
 * The account copy of the desk's chart templates.
 *
 * The browser keeps the list so a template is there before any request returns,
 * but the account is what makes "MTL" the same look on the phone. Every call
 * here is best-effort: a template is a preference, and a chart must still open
 * when the network is gone, so failures return a sentence instead of throwing.
 */

import { supabase } from '@/lib/supabase'
import {
  mergeTemplates,
  templateFromCloud,
  templateSlug,
  type ChartTemplate,
} from '@/lib/desk-settings'

export const CHART_TEMPLATES_TABLE = 'chart_templates'

export interface TemplatesResult {
  templates: ChartTemplate[]
  error: string | null
}

/** The one sentence the desk shows when the table has not been created yet. */
const MISSING_TABLE =
  'Chart templates are not shared yet — apply supabase/migrations/20261127_chart_templates.sql.'

function friendly(error: unknown): string {
  const message = String(error ?? '').toLowerCase()
  if (
    message.includes('42p01') ||
    message.includes('does not exist') ||
    message.includes('schema cache')
  ) {
    return MISSING_TABLE
  }
  if (message.includes('jwt') || message.includes('refresh token')) {
    return 'Signed out, so templates stayed on this device.'
  }
  return 'Could not reach the account, so templates stayed on this device.'
}

async function currentUserId(): Promise<string | null> {
  const { data, error } = await supabase.auth.getUser()
  if (error || !data.user) return null
  return data.user.id
}

export async function fetchCloudTemplates(): Promise<TemplatesResult> {
  try {
    const userId = await currentUserId()
    if (!userId) return { templates: [], error: null }
    const { data, error } = await supabase
      .from(CHART_TEMPLATES_TABLE)
      .select('name, style, edited_at')
      .eq('user_id', userId)
    if (error) throw error
    const templates: ChartTemplate[] = []
    for (const row of (data ?? []) as Record<string, unknown>[]) {
      const template = templateFromCloud(row)
      if (template) templates.push(template)
    }
    return { templates, error: null }
  } catch (error) {
    return { templates: [], error: friendly(error) }
  }
}

/**
 * Writes one template to the account.
 *
 * Upsert on `(user_id, slug)` rather than insert: saving under an existing name
 * is how a look is edited, and the slug is what makes "MTL" and "mtl" the same
 * template on both desks.
 */
export async function pushCloudTemplate(
  template: ChartTemplate
): Promise<string | null> {
  try {
    const userId = await currentUserId()
    if (!userId) return null
    const { error } = await supabase.from(CHART_TEMPLATES_TABLE).upsert(
      {
        user_id: userId,
        slug: templateSlug(template.name),
        name: template.name,
        style: template.style,
        edited_at: new Date(template.editedAt || Date.now()).toISOString(),
      },
      { onConflict: 'user_id,slug' }
    )
    if (error) throw error
    return null
  } catch (error) {
    return friendly(error)
  }
}

/**
 * Reconciles the device's list with the account's: newer copy wins, and anything
 * the account has never seen (or has older) is pushed up.
 *
 * Returns the merged list either way. A template list that cannot be reached is
 * still the trader's list, not an empty one.
 */
export async function syncTemplates(
  local: ChartTemplate[]
): Promise<TemplatesResult> {
  const { templates: cloud, error } = await fetchCloudTemplates()
  if (error) return { templates: local, error }

  const merged = mergeTemplates(local, cloud)
  const cloudBySlug = new Map(cloud.map((entry) => [templateSlug(entry.name), entry]))
  let pushError: string | null = null
  for (const template of merged) {
    const remote = cloudBySlug.get(templateSlug(template.name))
    if (remote && remote.editedAt >= template.editedAt) continue
    const failure = await pushCloudTemplate(template)
    if (failure) pushError = failure
  }
  return { templates: merged, error: pushError }
}

export async function deleteCloudTemplate(name: string): Promise<string | null> {
  try {
    const userId = await currentUserId()
    // No session: there is no account row this template could belong to.
    if (!userId) return null
    const { error } = await supabase
      .from(CHART_TEMPLATES_TABLE)
      .delete()
      .eq('user_id', userId)
      .eq('slug', templateSlug(name))
    if (error) throw error
    return null
  } catch (error) {
    return friendly(error)
  }
}
