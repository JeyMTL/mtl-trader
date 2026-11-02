/**
 * Provider adapters for the AI review: Gemini (the free tier, and the default),
 * Anthropic, and any gateway that speaks the OpenAI chat-completions protocol.
 *
 * The protocol is OpenAI-shaped because that is what Gemini's compatibility
 * layer speaks, not because OpenAI is a supported account: there is no OpenAI
 * key path here and no default vendor URL to fall back to.
 *
 * Implemented over `fetch` (injectable) so there is no SDK dependency and the
 * adapters stay unit-testable.
 */

import type { PromptContent, PromptMessage } from './types'

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>

export type ProviderName = 'anthropic' | 'openai-compatible' | 'gemini'

/**
 * Gemini's OpenAI-compatible endpoint (no trailing slash: the adapters append
 * `/chat/completions`). It has a free tier that needs no card, which is what
 * makes the AI review usable before there is any revenue to pay for it.
 */
export const GEMINI_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta/openai'
/**
 * Pinned rather than "latest" on purpose. On 2026-11-02 the `latest` flash and
 * 3.8 Flash were both answering 503 "experiencing high demand" (or hanging on
 * the compatibility layer) while 3.6 Flash answered in ~2s, and 2.5 Flash was
 * closed to new keys. A moving alias would put that outage in front of every
 * customer; override with GEMINI_MODEL when a newer one is actually healthy.
 */
export const GEMINI_DEFAULT_MODEL = 'gemini-3.6-flash'

export interface ProviderConfig {
  provider: ProviderName
  apiKey: string
  baseUrl: string
  model: string
  visionModel: string
}

export interface CompleteOptions {
  model?: string
  temperature?: number
  maxTokens?: number
  json?: boolean
  signal?: AbortSignal
}

export interface AiProvider {
  name: ProviderName
  model: string
  visionModel: string
  complete(messages: PromptMessage[], options?: CompleteOptions): Promise<string>
  stream(messages: PromptMessage[], options?: CompleteOptions): AsyncGenerator<string>
}

interface ParsedImage {
  mediaType: string
  data: string
}

export function parseDataUrl(dataUrl: string): ParsedImage | null {
  const match = /^data:([^;,]+);base64,(.+)$/i.exec(dataUrl.trim())
  if (!match) return null
  return { mediaType: match[1], data: match[2] }
}

/** Resolve provider config from the environment, or null if unconfigured. */
export function resolveProviderConfig(env: Record<string, string | undefined> = process.env): ProviderConfig | null {
  const explicit = env.AI_PROVIDER?.toLowerCase()
  const anthropicKey = env.ANTHROPIC_API_KEY
  const geminiKey = env.GEMINI_API_KEY

  let provider: ProviderName
  if (explicit === 'anthropic' || explicit === 'gemini' || explicit === 'openai-compatible') {
    provider = explicit
  } else if (anthropicKey) {
    // Last paid provider standing; the free Gemini tier is the fallback.
    provider = 'anthropic'
  } else if (geminiKey) {
    provider = 'gemini'
  } else {
    return null
  }

  if (provider === 'gemini') {
    if (!geminiKey) return null
    return {
      provider,
      apiKey: geminiKey,
      baseUrl: env.GEMINI_BASE_URL || GEMINI_BASE_URL,
      model: env.AI_MODEL || env.GEMINI_MODEL || GEMINI_DEFAULT_MODEL,
      visionModel:
        env.AI_VISION_MODEL || env.AI_MODEL || env.GEMINI_MODEL || GEMINI_DEFAULT_MODEL,
    }
  }

  if (provider === 'anthropic') {
    if (!anthropicKey) return null
    return {
      provider,
      apiKey: anthropicKey,
      baseUrl: env.ANTHROPIC_BASE_URL || 'https://api.anthropic.com/v1',
      model: env.AI_MODEL || env.ANTHROPIC_MODEL || 'claude-3-5-sonnet-latest',
      visionModel: env.AI_VISION_MODEL || env.AI_MODEL || env.ANTHROPIC_MODEL || 'claude-3-5-sonnet-latest',
    }
  }

  // A gateway must be configured in full: with no default vendor there is
  // nothing sensible to fall back to, and posting a journal to a URL nobody
  // chose would be worse than refusing.
  const baseUrl = env.AI_BASE_URL
  const apiKey = env.AI_API_KEY
  const model = env.AI_MODEL
  if (!baseUrl || !apiKey || !model) return null
  return {
    provider: 'openai-compatible',
    apiKey,
    baseUrl,
    model,
    visionModel: env.AI_VISION_MODEL || model,
  }
}

async function readError(response: Response): Promise<string> {
  try {
    const text = await response.text()
    try {
      const parsed = JSON.parse(text) as { error?: { message?: string } | string; message?: string }
      if (typeof parsed.error === 'string') return parsed.error
      if (parsed.error && typeof parsed.error === 'object' && parsed.error.message) return parsed.error.message
      if (parsed.message) return parsed.message
    } catch {
      // fall through to raw text
    }
    return text.slice(0, 400) || `HTTP ${response.status}`
  } catch {
    return `HTTP ${response.status}`
  }
}

async function* sseData(response: Response): AsyncGenerator<string> {
  const reader = response.body?.getReader()
  if (!reader) return
  const decoder = new TextDecoder()
  let buffer = ''
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    buffer += decoder.decode(value, { stream: true })
    let index = buffer.indexOf('\n')
    while (index !== -1) {
      const line = buffer.slice(0, index).trim()
      buffer = buffer.slice(index + 1)
      if (line.startsWith('data:')) yield line.slice(5).trim()
      index = buffer.indexOf('\n')
    }
  }
  const rest = buffer.trim()
  if (rest.startsWith('data:')) yield rest.slice(5).trim()
}

function compatibleContent(content: string | PromptContent[]) {
  if (typeof content === 'string') return content
  return content.map((part) =>
    part.type === 'text'
      ? { type: 'text', text: part.text }
      : { type: 'image_url', image_url: { url: part.dataUrl } }
  )
}

function compatibleMessages(messages: PromptMessage[]) {
  return messages.map((message) => ({ role: message.role, content: compatibleContent(message.content) }))
}

function anthropicMessages(messages: PromptMessage[]) {
  const system = messages.filter((m) => m.role === 'system')
  const rest = messages.filter((m) => m.role !== 'system')
  const systemText = system
    .map((m) => (typeof m.content === 'string' ? m.content : m.content.filter((p) => p.type === 'text').map((p) => (p as { text: string }).text).join('\n')))
    .join('\n\n')
  const converted = rest.map((message) => {
    if (typeof message.content === 'string') return { role: message.role, content: message.content }
    const content = message.content.map((part) => {
      if (part.type === 'text') return { type: 'text', text: part.text }
      const image = parseDataUrl(part.dataUrl)
      return image
        ? { type: 'image', source: { type: 'base64', media_type: image.mediaType, data: image.data } }
        : { type: 'text', text: '[unreadable image]' }
    })
    return { role: message.role, content }
  })
  return { system: systemText, messages: converted }
}

function hasImage(messages: PromptMessage[]): boolean {
  return messages.some((message) => Array.isArray(message.content) && message.content.some((part) => part.type === 'image'))
}

function pickModel(config: ProviderConfig, messages: PromptMessage[], options?: CompleteOptions): string {
  return options?.model || (hasImage(messages) ? config.visionModel : config.model)
}

/** Ceiling for one provider request. Overridable so tests (and the impatient) can shrink it. */
function providerTimeoutMs(): number {
  const configured = Number(process.env.AI_TIMEOUT_MS)
  // Below the route's 60s function budget on purpose: the request should fail
  // with a sentence we wrote, not be killed by the platform mid-write.
  return Number.isFinite(configured) && configured > 0 ? configured : 45_000
}

/**
 * A request signal that always gives up eventually.
 *
 * Without one, a saturated model on an OpenAI-compatible gateway neither
 * answers nor errors — it holds the socket. Observed for real: Gemini's
 * compatibility layer hung for over 45s on `gemini-3.8-flash` while the native
 * endpoint answered 503 "model is currently experiencing high demand" for the
 * same request. The customer saw a review that spun; a timeout at least turns
 * that into a failure they can retry.
 */
function requestSignal(signal?: AbortSignal): AbortSignal {
  const timeout = AbortSignal.timeout(providerTimeoutMs())
  return signal ? AbortSignal.any([signal, timeout]) : timeout
}

/** Turn a hung request into a sentence worth logging. */
async function runRequest(run: () => Promise<Response>): Promise<Response> {
  try {
    return await run()
  } catch (error) {
    if (error instanceof Error && (error.name === 'AbortError' || error.name === 'TimeoutError')) {
      throw new Error(
        `AI provider did not answer within ${Math.round(providerTimeoutMs() / 1000)}s. The model may be overloaded; try again.`
      )
    }
    throw error
  }
}

function createCompatibleProvider(config: ProviderConfig, fetchImpl: FetchLike): AiProvider {
  /**
   * Gemini 3.x are thinking models: the reasoning is spent from the same budget
   * as the visible reply, so the review's 900-token ceiling can be consumed
   * entirely by thinking and come back as an empty message — which the
   * normalizer then rejects as "no JSON object". A low reasoning effort plus a
   * raised ceiling keeps the JSON inside the budget. Other providers are left
   * exactly as they were.
   */
  const gemini = config.provider === 'gemini'
  const requestBody = (messages: PromptMessage[], options: CompleteOptions, stream: boolean) => ({
    model: pickModel(config, messages, options),
    temperature: options.temperature ?? 0.3,
    ...(gemini ? { reasoning_effort: 'low' } : {}),
    max_tokens: gemini ? Math.max(options.maxTokens ?? 900, 2000) : options.maxTokens ?? 900,
    ...(options.json ? { response_format: { type: 'json_object' } } : {}),
    ...(stream ? { stream: true } : {}),
    messages: compatibleMessages(messages),
  })

  return {
    name: config.provider,
    model: config.model,
    visionModel: config.visionModel,
    async complete(messages, options = {}) {
      const response = await runRequest(() =>
        fetchImpl(`${config.baseUrl}/chat/completions`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${config.apiKey}`, 'Content-Type': 'application/json' },
          signal: requestSignal(options.signal),
          body: JSON.stringify(requestBody(messages, options, false)),
        })
      )
      if (!response.ok) throw new Error(`AI provider error: ${await readError(response)}`)
      const data = (await response.json()) as { choices?: Array<{ message?: { content?: string } }> }
      const content = data.choices?.[0]?.message?.content
      if (!content) throw new Error('AI provider returned an empty response')
      return content
    },
    async *stream(messages, options = {}) {
      const response = await fetchImpl(`${config.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${config.apiKey}`, 'Content-Type': 'application/json' },
        signal: requestSignal(options.signal),
        body: JSON.stringify(requestBody(messages, options, true)),
      })
      if (!response.ok) throw new Error(`AI provider error: ${await readError(response)}`)
      for await (const data of sseData(response)) {
        if (!data || data === '[DONE]') continue
        try {
          const parsed = JSON.parse(data) as { choices?: Array<{ delta?: { content?: string } }> }
          const delta = parsed.choices?.[0]?.delta?.content
          if (delta) yield delta
        } catch {
          // ignore malformed keep-alive chunks
        }
      }
    },
  }
}

function createAnthropicProvider(config: ProviderConfig, fetchImpl: FetchLike): AiProvider {
  return {
    name: 'anthropic',
    model: config.model,
    visionModel: config.visionModel,
    async complete(messages, options = {}) {
      const { system, messages: converted } = anthropicMessages(messages)
      const response = await runRequest(() =>
        fetchImpl(`${config.baseUrl}/messages`, {
          method: 'POST',
          headers: {
            'x-api-key': config.apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
            signal: requestSignal(options.signal),
          body: JSON.stringify({
            model: options.model || config.model,
            max_tokens: options.maxTokens ?? 900,
            temperature: options.temperature ?? 0.3,
            system,
            messages: converted,
          }),
        })
      )
      if (!response.ok) throw new Error(`AI provider error: ${await readError(response)}`)
      const data = (await response.json()) as { content?: Array<{ type: string; text?: string }> }
      const text = (data.content || [])
        .filter((block) => block.type === 'text')
        .map((block) => block.text || '')
        .join('')
      if (!text) throw new Error('AI provider returned an empty response')
      return text
    },
    async *stream(messages, options = {}) {
      const { system, messages: converted } = anthropicMessages(messages)
      const response = await fetchImpl(`${config.baseUrl}/messages`, {
        method: 'POST',
        headers: {
          'x-api-key': config.apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
        },
        signal: requestSignal(options.signal),
        body: JSON.stringify({
          model: options.model || config.model,
          max_tokens: options.maxTokens ?? 900,
          temperature: options.temperature ?? 0.3,
          system,
          messages: converted,
          stream: true,
        }),
      })
      if (!response.ok) throw new Error(`AI provider error: ${await readError(response)}`)
      for await (const data of sseData(response)) {
        if (!data) continue
        try {
          const parsed = JSON.parse(data) as { type?: string; delta?: { text?: string } }
          if (parsed.type === 'content_block_delta' && parsed.delta?.text) yield parsed.delta.text
        } catch {
          // ignore malformed keep-alive chunks
        }
      }
    },
  }
}

export function createProvider(config: ProviderConfig, fetchImpl: FetchLike = fetch): AiProvider {
  if (config.provider === 'anthropic') return createAnthropicProvider(config, fetchImpl)
  return createCompatibleProvider(config, fetchImpl)
}
