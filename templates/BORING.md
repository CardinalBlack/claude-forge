# Boring Paths

Files matching these patterns must use established, well-tested patterns. Novel patterns require explicit justification.

## Default boring-path patterns

- Auth flows — use the framework's auth, not a custom implementation
- HMAC verification — use stdlib `hmac` + `timingSafeEqual`, not a hand-rolled compare
- SQL migrations — use plain SQL with `IF NOT EXISTS` + idempotency, not a homegrown migration tool
- Date handling — use the platform's date library, not parse-by-string
- JSON parsing — wrap in try/catch with explicit error path, not assume well-formed
- Env-var validation — Zod schema at process start, not scattered checks

## Project-specific boring patterns

(populate per project)
