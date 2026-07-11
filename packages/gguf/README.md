# gguf — bulletproof GGUF container toolkit in pure NURL

GGUF is the ggml-ecosystem tensor container: the file format of
llama.cpp, whisper.cpp and stable-diffusion.cpp models. This package
reads it, proves it, writes it and dequantises it — with no
dependency beyond the NURL stdlib.

```
gguf info  model.gguf                 # GGUF v3 — 20 kv, 57 tensors, align 32, arch llama
gguf dump  model.gguf                 # every metadata key/value + the tensor table
gguf kv    model.gguf llama.context_length
gguf tensors model.gguf
gguf verify model.gguf                # deep structural proof (bounds, alignment, overlap)
gguf export model.gguf blk.0.attn_q.weight -o q.f32   # dequantised f32-LE
gguf gen   sample.gguf                # write the reference sample file
gguf selftest                         # write → parse → compare, bit-exact
```

## The point: hostile-input parsing

A model file is a download — treat it as an attack. The parser
validates **every count, length and offset against the actual file
size before any allocation or read depends on it**, and allocations
are proportional to bytes actually consumed from the file, never to
what a header merely claims. A 24-byte file claiming 2⁶³ tensors
fails in microseconds; a truncated vocab array, a NUL-smuggling key,
a nested array, a duplicate key or tensor name, an unaligned or
out-of-bounds tensor, a dimension product that would overflow —
each is a clean `gguf:` error, never a crash, a hang or a wrong
answer. `tests/gguf_test.sh` proves this with a corruption battery
(truncations at every structural boundary, hostile counts, absurd
lengths) plus attack files crafted independently in python.

## Lazy by design

`gguf_open` mmaps the file and parses only metadata and the tensor
table; tensor bytes are addressed straight out of the mapping
(`gguf_tensor_ptr`) and uploaded/decoded tensor by tensor. Inspecting
a multi-gigabyte model costs no RAM. Platforms without mmap (wasm,
win32) fall back to a whole-file buffer transparently.

## Library API

```nurl
$ `gguf.nu`      // parser + accessors
$ `dequant.nu`   // host-side scalar dequantisation
$ `write.nu`     // GGUF v3 writer/builder

: !*Gguf String r ( gguf_open `model.gguf` )
?? r {
    T g → {
        : i n_layers ( gguf_kv_int_or g `llama.block_count` 0 )
        : s arch ( gguf_kv_str_or g `general.architecture` `?` )   // borrowed
        : i ti ( gguf_find_tensor g `token_embd.weight` )
        : !( Vec u ) String w ( gguf_dequant g ti )   // f32-LE, upload-ready
        ( gguf_close g )
    }
    F e → {
        ( nurl_eprintln ( string_data e ) )
        ( string_free e )
    }
}
```

- **Versions**: GGUF v2 and v3 (v1's legacy 32-bit layout is rejected
  with a clear message).
- **Metadata**: all 13 value types, including arrays of
  ints/floats/strings (tokeniser vocabularies).
- **Tensor types**: every current ggml id is named and sized
  (F32/F16/BF16/F64, Q4_0/Q4_1/Q5_0/Q5_1/Q8_0/Q8_1, all K-quants,
  IQ4_NL, I8–I64); unknown ids are still listed — the parser degrades
  loudly, not wrongly.
- **Dequantisation** (`gguf_dequant` → little-endian f32, one element
  per value in storage order): F32, F64, F16, BF16, Q4_0, Q4_1, Q8_0.
  F16 conversion is a pure bit transport (subnormals, ±inf, NaN and
  −0 preserved exactly). This is the CPU decode path *and* the golden
  oracle for GPU dequant kernels — verified bit-identical against
  independent python decodes of real llama.cpp models.
- **Writer** (`gw_new` / `gw_kv_*` / `gw_tensor` / `gw_finish`): emits
  spec-exact v3 images, validates shapes against payload sizes with
  the same rules the parser enforces, and round-trips bit-for-bit
  (`gguf selftest`, 37 checks).

## Testing

```
./tests/gguf_test.sh                  # 48 checks, no network needed
NURL_NET_TESTS=1 ./tests/gguf_test.sh # + parses a real llama.cpp model from HF
```

The suite was developed under ASan/UBSan + LeakSanitizer
(`NURL_SAN=1 nurl.sh …`): zero leaks, zero UB on every path including
the corruption battery.
