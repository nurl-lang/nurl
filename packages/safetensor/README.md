# safetensor

Read the **safetensors** container — the format Hugging Face ships every
modern model in — from pure NURL. mmap-backed, lazy, and written for
files you did not make yourself.

```
nurlpkg install safetensor
```

```
$ safetensor info model.safetensors
safetensors — 236 tensors, data 536196352 B

$ safetensor tensors model.safetensors | head -3
model.embed_tokens.weight                      BF16 [262144 640] 335544320 B @ 26704
model.layers.0.input_layernorm.weight          BF16 [640] 1280 B @ 335571024
model.layers.0.mlp.down_proj.weight            BF16 [640 2048] 2621440 B @ 335572304

$ safetensor stats model.safetensors model.layers.0.mlp.down_proj.weight
n=1310720 min=-0.671875 max=0.664062 mean=0.000012

$ safetensor export model.safetensors model.embed_tokens.weight -o embd.f32
```

## The format, and why the parser is paranoid

```
u64 LE  header_len
        header_len bytes of JSON   { "name": {dtype, shape, data_offsets:[a,b]} }
        the tensor bytes           (a and b index THIS region)
```

That is the whole format — and it is also the whole attack surface: every
tensor's bytes are addressed by numbers the file itself supplies. So none
of them are believed.

* `header_len` is checked against the real file size **before the JSON is
  looked at** — and compared against the remaining bytes, never by
  forming `8 + header_len`, which a hostile value would wrap.
* every `[a, b)` must lie inside the data region computed from that size,
  and `b − a` must be **exactly** what the tensor's dtype and shape need.
  A file cannot point a tensor at the header, at another tensor's bytes,
  or past the end.
* element counts are accumulated with an **overflow check at each step**:
  a shape of `[2^62, 4]` is an error, not a small wrapped-around number
  that later sizes an allocation.
* nothing is allocated on the strength of a number the file supplied.

`safetensor selftest` runs the crafted-file battery: every lie a header
can tell (extent past the end, extent that disagrees with the shape,
reversed range, negative offset, overflowing shape, unknown dtype,
missing shape, missing offsets, header that is not JSON, header that is
not an object, header longer than the file, file shorter than its own
length prefix) must come back as a clean error.

This is not theoretical. The first whisper-tiny download used to write
this package was cut short at 93 MB of 151 MB — and the parser said so,
before anything else noticed.

## What you get

| | |
|---|---|
| `st_open` / `st_close` | mmap-backed; a whole-file read where mmap does not exist (wasm, win32) |
| `st_find_tensor` | by name, `-1` when absent |
| `st_tensor_ptr` | the bytes, straight out of the mapping — no copy |
| `st_dequant` | the tensor as **f32**, whatever it was stored as |
| `st_dequant_range` | elements `[first, first+count)` — **exact**, because safetensors has no block quantisation, so a single row of a 262 144-row embedding table can be read without touching the rest |

Every dtype widens to f32 on demand: **F64, F32, F16, BF16**, the signed
and unsigned integers, and BOOL.

## Proven, not asserted

A reader that is quietly wrong about a dtype or a row order does not
crash — it produces plausible numbers, and whatever depends on it fails
somewhere else entirely. So this package is checked against things that
already work:

* **167 tensors of a real model** (whisper-tiny): every dtype, shape and
  byte extent agrees with an independent python reader, and the f32 bytes
  of sampled tensors are compared **bit for bit** with the file — not
  through printed decimals, which would only prove that the printer
  rounds.
* **A whole forward pass.**
  [`nurllama`](https://reg.nurl-lang.org/nurllama) can take its weights
  from a safetensors file instead of a GGUF (`--weights model.safetensors`).
  Running gemma-3-270m that way reproduces Hugging Face's own logits to
  **max |Δ| = 1.1e-4 with r = 1.00000000** and an identical top-5 — where
  the quantised GGUF path, on the same model, differs by 1.19. The
  weights we read are the weights the checkpoint holds, to the last bit
  that f32 accumulation order allows.

## License

MIT OR Apache-2.0
