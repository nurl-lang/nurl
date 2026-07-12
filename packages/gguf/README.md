# gguf

Read, verify, write and dequantise **GGUF** — the tensor container behind
llama.cpp, whisper.cpp and stable-diffusion.cpp. Pure NURL, no
dependencies beyond the stdlib.

```sh
nurlpkg install gguf
```

## Command line

```sh
$ gguf info model.gguf
GGUF v3 — 29 kv, 272 tensors, align 32, data 103668480 B, arch llama, name SmolLM

$ gguf tensors model.gguf | head -3
token_embd.weight             Q8_0 [576 49152] 30081024 B @ 0
blk.0.attn_norm.weight        F32  [576]           2304 B @ 30081024
blk.0.ffn_down.weight         Q6_K [1536 576]   725760 B @ 30083328

$ gguf kv model.gguf llama.context_length
llama.context_length = u32 2048

$ gguf verify model.gguf
OK — GGUF v3, 29 kv, 272 tensors, all offsets aligned, in-bounds and disjoint

$ gguf export model.gguf blk.0.attn_q.weight -o q.f32   # dequantised f32
wrote 331776 bytes of f32-LE
```

`gguf dump` prints the header, every metadata key and the tensor table.
`gguf gen sample.gguf` writes a reference file; `gguf selftest` proves
the round-trip.

## Library

```nurl
$ `deps/gguf/src/gguf.nu`
$ `deps/gguf/src/dequant.nu`

?? ( gguf_open `model.gguf` ) {
    T g → {
        : i layers ( gguf_kv_int_or g `llama.block_count` 0 )
        : s arch ( gguf_kv_str_or g `general.architecture` `?` )   // borrowed

        : i ti ( gguf_find_tensor g `token_embd.weight` )
        // one row of a huge table — no full expansion
        ?? ( gguf_dequant_range g ti * token 576 576 ) {
            T row → {
                // 576 little-endian f32s, ready to upload
                ( vec_free [u] row )
            }
            F e → { ( string_free e ) }
        }
        ( gguf_close g )
    }
    F e → {
        ( nurl_eprintln ( string_data e ) )
        ( string_free e )
    }
}
```

| | |
|---|---|
| `gguf_open path` → `!*Gguf String` | mmap + parse (metadata and the tensor table only) |
| `gguf_parse_bytes v` | the same, from a buffer you own |
| `gguf_kv_int_or` / `_f_or` / `_str_or` | metadata with a default |
| `gguf_find_tensor` / `gguf_tensor_ptr` | locate a tensor; borrow its bytes in place |
| `gguf_dequant g i` | whole tensor → little-endian f32 |
| `gguf_dequant_range g i first count` | a block-aligned slice — one row of a 4 GB table |
| `gw_new` / `gw_kv_*` / `gw_tensor` / `gw_write` | build and emit a spec-exact GGUF v3 file |

**Formats.** Metadata: all 13 value types, arrays included (tokenizer
vocabularies). Tensors: every current ggml id is named and sized, and
dequantisation covers F32, F64, F16, BF16, Q4_0, Q4_1, Q5_0, Q5_1,
Q8_0 and the K-quants **Q4_K / Q5_K / Q6_K** — every format a modern
model actually ships in (a `Q4_K_M` file mixes Q4_K and Q6_K). An
unknown type is still listed and verified; it simply cannot be
dequantised, and says so.

## Two things worth knowing

**It never trusts the file.** A model is a download. Every count,
length and offset is checked against the real file size *before*
anything is allocated or read, and allocations are proportional to
bytes actually consumed — not to what a header claims. A 24-byte file
declaring 2⁶³ tensors fails in microseconds. Truncations, NUL-smuggling
keys, nested arrays, duplicate names, unaligned or overlapping tensors:
each is a clean `gguf:` error, never a crash, a hang or a wrong answer.

**It is lazy.** `gguf_open` mmaps the file and parses only metadata and
the tensor table; tensor bytes are addressed in place. Inspecting — or
streaming one row at a time out of — a multi-gigabyte model costs no
RAM. (Platforms without mmap fall back to a whole-file buffer
transparently.)

## Correctness

Dequantisation is verified **bit-identical** against an independent
Python decoder reading the same bytes of real llama.cpp models
(`tests/kquant_ref.py`); the writer round-trips through the parser
bit-for-bit (`gguf selftest`, 37 checks); and the hostile-input claims
above are proven by a corruption battery plus attack files crafted
independently in Python. 55 checks, ASan/UBSan/LeakSanitizer-clean:

```sh
./tests/gguf_test.sh                    # offline
NURL_NET_TESTS=1 ./tests/gguf_test.sh   # + real models from HuggingFace
```

## License

MIT OR Apache-2.0
