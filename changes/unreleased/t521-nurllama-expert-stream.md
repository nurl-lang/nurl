### Added

- **nurllama runs a Mixture of Experts whose experts do not fit the
  device** (Agora #521): the routed experts stay in their file and a
  device cache of them (least recently used out first) loads the ones the
  router picks on demand, the host's page cache in between. Any MoE model
  (glm-dsa, llada2), any way its experts are stored — a GGUF's stacks, a
  checkpoint's tensors, EXL3 tensor groups whole or in tensor-parallel
  shares (fiore-lab's GLM-5.3 bank) — with logits byte-identical to the
  all-resident run. `NURLLAMA_EXPERT_CACHE` (MiB) / `NURLLAMA_EXPERT_SLOTS`
  size the cache; `--weights DIR` adds an expert bank kept in a directory
  of its own to a checkpoint directory.

### Performance

- **safetensor opens a file with many tensors in one pass, and finds a
  tensor by hashing its name** (Agora #521): the header parse looked every
  entry up by name (quadratic in the tensor count) and `st_find_tensor`
  scanned the table — an expert bank shard of 24,576 tensors took seconds
  to open, and a lookup across 76 such shards scanned 1.8 million names.
