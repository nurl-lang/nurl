### Added

- **nurllama runs a Hugging Face checkpoint directory directly** (Agora
  #520): config.json, tokenizer.json and the safetensors shards, with no
  GGUF copy — llama, mistral, qwen2, qwen3 and glm_moe_dsa, any linear
  stored as EXL3 run as EXL3.

### Fixed

- **tokenizer: a llama3 GGUF (`llama-bpe`) is split as llama3 splits**
  (digits in threes, ignore_merges), not the gpt2 way.
