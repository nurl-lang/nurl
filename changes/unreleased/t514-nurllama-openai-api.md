### Added

- **nurllama serves an OpenAI-compatible API** (Agora #514):
  `/v1/chat/completions`, `/v1/completions` and `/v1/models` beside
  ollama's routes, with SSE streaming, usage, stop sequences and OpenAI's
  error shape; ollama's and OpenAI's routes run one generation loop.

### Fixed

- **nurllama: a token-auth server checks the token on every data route**
  (Agora #515) — ollama's `/api/*` routes answered without it.
- **nurllama: sampling with top-k off no longer takes O(vocabulary²)**
  a token, and generated text always reaches a client as valid UTF-8.
