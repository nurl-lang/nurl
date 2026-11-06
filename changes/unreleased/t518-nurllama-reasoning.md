### Added

- **nurllama returns a reasoning model's reasoning apart from its answer**
  (Agora #518): `reasoning_content` on the OpenAI routes and `thinking` on
  ollama's, streamed and whole, and takes `reasoning_effort`,
  `chat_template_kwargs` and ollama's `think` as the model's chat template
  reads them.
