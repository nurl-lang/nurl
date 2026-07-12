# nurllama

Run language models locally. Pull a GGUF model, chat with it, or serve
an **ollama-compatible API** your existing clients already speak — all
in pure NURL, from the GGUF parser to the GPU kernels.

```sh
nurlpkg install nurllama
```

## Sixty seconds

```sh
$ nurllama pull hf.co/QuantFactory/SmolLM-135M-GGUF/SmolLM-135M.Q4_K_M.gguf
SmolLM-135M.Q4_K_M [===================>     ] 82%  86.1 MB / 105.4 MB  24.3 MB/s
pulled SmolLM-135M.Q4_K_M (sha256:9b1c4e0a2f31…, 105.4 MB)

$ nurllama run SmolLM-135M.Q4_K_M "Once upon a time" -n 40
, there was a little girl named Lily. Lily loved to play with her friends…

$ nurllama chat SmolLM-135M.Q4_K_M
chat ready — /exit to quit
> what is a GGUF file?
It is a container format for model weights…

$ nurllama serve
nurllama serving on http://127.0.0.1:11434
```

```sh
$ curl localhost:11434/api/generate -d '{"model":"SmolLM-135M.Q4_K_M","prompt":"Once upon a time"}'
{"model":"SmolLM-135M.Q4_K_M","response":",","done":false}
{"model":"SmolLM-135M.Q4_K_M","response":" there","done":false}
…
{"model":"SmolLM-135M.Q4_K_M","done":true,"prompt_eval_count":5,"eval_count":40}
```

One object per token, the moment it decodes. `stream:false` returns a
single aggregated object instead.

## Commands

| | |
|---|---|
| `pull <src> [--name N]` | `hf.co/ORG/REPO/FILE.gguf` or any URL. Resumes an interrupted download. |
| `run <model> "<prompt>"` | `-n` tokens, `--temp` (0 = greedy), `--topk`, `--topp`, `--seed`, `--ctx` |
| `chat <model>` | interactive; uses the model's own chat template |
| `serve [--host] [--port]` | ollama-compatible API on 11434 |
| `list` · `rm <name>` · `verify <name>` | the local store |
| `tokenize` · `detok` · `vocab` · `logits` | inspection taps |

`<model>` is a name from `nurllama list` or a path to any `.gguf` file.

**HTTP API:** `POST /api/generate`, `POST /api/chat`, `GET /api/tags`,
`POST /api/show`.

## What it runs

Llama-family GGUF models — F32, F16, BF16, Q4_0, Q4_1, Q5_0, Q5_1,
Q8_0 and the K-quants **Q4_K / Q5_K / Q6_K** (the `Q4_K_M` files people
actually download).

Weights stay **quantised on the device**: the matvec kernels decode
GGUF blocks inside the matmul, so a Q4_K_M model needs about a third of
the memory its f32 expansion would — 189 MiB instead of 603 MiB for
SmolLM-135M — and the memory-bound matmul reads proportionally fewer
bytes. The embedding table is never expanded either: each step
dequantises just the token's row, straight out of the mmapped file.

**No GPU?** `NURL_GPU=cpu` runs the identical kernel sources on the
host through OpenMP and produces byte-identical output.

## Configuration

| | |
|---|---|
| `NURLLAMA_HOME` | store location (default `~/.nurllama`) |
| `NURL_GPU=cpu` | run on the CPU backend |
| `NURLLAMA_VERBOSE=1` | report device memory at load |
| `NURLLAMA_DEQUANT=host` | force the f32 reference path (debugging) |
| `NURL_GPU_CACHE=off` | disable the compiled-kernel cache |

The store is content-addressed — `blobs/sha256-<hex>` plus one manifest
per name — so two names can share a blob, and `verify` re-hashes it in
a stream and refuses drift.

## Chat templates

The template comes from the model's own metadata
(`tokenizer.chat_template` → ChatML, llama3 or llama2). A model with no
template is a **base** model, and nurllama will not invent turns for it
— it completes your text, which is what such a model was trained to do.

## How it is checked

Not by trusting itself:

- Token IDs match an independent Python SentencePiece implementation on
  a real model — unicode, emoji, whitespace runs, empty input included.
- Final-position logits match an independent **numpy** implementation of
  the whole forward pass, and a 40-token greedy continuation is
  text-identical to it.
- The quantised device kernels agree with the host dequant oracle —
  itself bit-identical to an independent decoder — and the CPU backend
  reproduces the same text exactly.
- A resumed download is proven to send `Range:` and transfer only the
  missing tail, with the final digest still exact.
- ASan/UBSan/LeakSanitizer-clean.

```sh
./tests/tokenizer_test.sh && ./tests/infer_test.sh   # NURL_NET_TESTS=1 adds real models
./tests/store_test.sh && ./tests/api_test.sh
```

## Built on

[`gguf`](../gguf) — the container and its dequantisation — and
[`gpu`](../gpu) — CUDA/NVRTC, or the same kernels on the CPU.

## License

MIT OR Apache-2.0
