### Added

- **nurllama renders GLM's chat templates** (Agora #517): GLM-5.2 / 5.3
  and GLM-5 / 5.1 (and GLM-4.7), byte-identical to HF's
  `apply_chat_template`; they were taken for phi3's.

### Fixed

- **nurllama ends a generation on the model's end-of-turn and
  end-of-message ids** (`tokenizer.ggml.eot_token_id` / `eom_token_id`),
  not only on eos — a GLM reply ran on into the next turn.
