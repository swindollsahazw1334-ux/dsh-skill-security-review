import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

/**
 * Bundled `plugin-security-review` skill provider.
 *
 * The body lives in assets/security-review/SKILL.md. That file keeps its YAML
 * frontmatter so it also works when copied into a filesystem skill root; the
 * frontmatter is stripped here because the provider supplies name and
 * description separately.
 */

// Mirrors BUNDLED_SKILL_RANK from @deepseek-ai/dsh-skill. Hard-coded on purpose:
// the bundle then has zero runtime dependencies and cannot break when a host
// package is missing or renamed.
const BUNDLED_SKILL_RANK = 600

const PROVIDER_NAME = 'dsh-security-review'
const SKILL_NAME = 'plugin-security-review'
const SKILL_DESCRIPTION =
  '安装第三方 DSH 插件（bundle / npm 包）之前的安全审查流程：拉 npm 元数据、解包做静态扫描（安装钩子、危险调用、网络与凭据访问、依赖树）、给出 A/B/C 分级结论与文件行号证据，并在隔离的 quarantine profile 里做动态验证。'

const SKILL_BODY_URL = new URL('../assets/security-review/SKILL.md', import.meta.url)
const RESOURCE_BASE = {
  kind: 'directory',
  path: fileURLToPath(new URL('../assets/security-review/', import.meta.url)),
}

const FRONTMATTER = /^---\r?\n[\s\S]*?\r?\n---\r?\n/

const CANDIDATE = {
  name: SKILL_NAME,
  description: SKILL_DESCRIPTION,
  invocation: { modelInvocable: true, userInvocable: true },
  provider: PROVIDER_NAME,
  source: 'bundled',
  resourceBase: RESOURCE_BASE,
  rank: BUNDLED_SKILL_RANK,
  locator: SKILL_BODY_URL,
}

const provider = {
  name: PROVIDER_NAME,
  list: () => Promise.resolve([CANDIDATE]),
  async get() {
    const raw = await readFile(SKILL_BODY_URL, 'utf8')
    return {
      name: CANDIDATE.name,
      description: CANDIDATE.description,
      invocation: CANDIDATE.invocation,
      provider: CANDIDATE.provider,
      source: CANDIDATE.source,
      resourceBase: RESOURCE_BASE,
      content: raw.replace(FRONTMATTER, ''),
    }
  },
}

/** Cordis plugin name. */
export const name = 'skill-security-review'
/** Service required by the bundled provider. */
export const inject = ['skills']
/** Register the bundled provider on `ctx.skills`. */
export function apply(ctx) {
  ctx.skills.registerProvider(() => provider)
}
