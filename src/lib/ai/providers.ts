/**
 * Provider adapters for the AI review. Supports OpenAI, Anthropic, and any
 * OpenAI-compatible base URL, with vision image parts and token streaming.
 *
 * Implemented over `fetch` (injectable) and the OpenAI/Anthropic REST shapes so
 * there is no SDK dependency and the adapters stay unit-testable.
 */

import type { PromptContent, PromptMessage } from './types'

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>

export type ProviderName = 'openai' | 'anthropic' | 'openai-compatible'

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
  const openAiKey = env.OPENAI_API_KEY
  const anthropicKey = env.ANTHROPIC_API_KEY

  let provider: ProviderName
  if (explicit === 'anthropic' || explicit === 'openai' || explicit === 'openai-compatible') {
    provider = explicit
  } else if (anthropicKey && !openAiKey) {
    provider = 'anthropic'
  } else if (openAiKey) {
    provider = 'openai'
  } else if (anthropicKey) {
    provider = 'anthropic'
  } else {
    provider = 'openai'
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

  const apiKey = provider === 'openai-compatible' ? env.AI_API_KEY || openAiKey : openAiKey
  if (!apiKey) return null
  return {
    provider,
    apiKey,
    baseUrl:
      provider === 'openai-compatible'
        ? env.AI_BASE_URL || 'https://api.openai.com/v1'
        : env.OPENAI_BASE_URL || 'https://api.openai.com/v1',
    model: env.AI_MODEL || env.OPENAI_MODEL || 'gpt-4o-mini',
    visionModel: env.AI_VISION_MODEL || env.AI_MODEL || env.OPENAI_MODEL || 'gpt-4o-mini',
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

function openAiContent(content: string | PromptContent[]) {
  if (typeof content === 'string') return content
  return content.map((part) =>
    part.type === 'text'
      ? { type: 'text', text: part.text }
      : { type: 'image_url', image_url: { url: part.dataUrl } }
  )
}

function openAiMessages(messages: PromptMessage[]) {
  return messages.map((message) => ({ role: message.role, content: openAiContent(message.content) }))
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

function createOpenAiProvider(config: ProviderConfig, fetchImpl: FetchLike): AiProvider {
  return {
    name: config.provider,
    model: config.model,
    visionModel: config.visionModel,
    async complete(messages, options = {}) {
      const response = await fetchImpl(`${config.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${config.apiKey}`, 'Content-Type': 'application/json' },
        signal: options.signal,
        body: JSON.stringify({
          model: pickModel(config, messages, options),
          temperature: options.temperature ?? 0.3,
          max_tokens: options.maxTokens ?? 900,
          ...(options.json ? { response_format: { type: 'json_object' } } : {}),
          messages: openAiMessages(messages),
        }),
      })
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
        signal: options.signal,
        body: JSON.stringify({
          model: pickModel(config, messages, options),
          temperature: options.temperature ?? 0.3,
          max_tokens: options.maxTokens ?? 900,
          stream: true,
          messages: openAiMessages(messages),
        }),
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
      const response = await fetchImpl(`${config.baseUrl}/messages`, {
        method: 'POST',
        headers: {
          'x-api-key': config.apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
        },
        signal: options.signal,
        body: JSON.stringify({
          model: options.model || config.model,
          max_tokens: options.maxTokens ?? 900,
          temperature: options.temperature ?? 0.3,
          system,
          messages: converted,
        }),
      })
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
        signal: options.signal,
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
  return createOpenAiProvider(config, fetchImpl)
}
