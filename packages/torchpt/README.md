# torchpt — read PyTorch `.pt` checkpoints in pure NURL

Most research models still ship as `torch.save` files. `torchpt` reads
them — names, dtypes, shapes, strides and values — **without executing
them**.

```
torchpt info    model.pt
torchpt tensors model.pt [name-prefix]
torchpt stats   model.pt aggregator.frame_blocks.0.attn.qkv.weight
torchpt head    model.pt aggregator.frame_blocks.0.attn.qkv.bias 8
torchpt dump    model.pt          # every tensor, every value
```

## Why this is not just "parse a file"

A `torch.save` file is a ZIP archive:

```
<name>/data.pkl        the object graph, pickled
<name>/data/<key>      one flat storage per tensor, raw little-endian
<name>/version         …
```

Tensors inside the pickle are `_rebuild_tensor_v2(storage, offset, size,
stride, …)` calls, and the storage is a *persistent id* naming one of the
`data/<key>` members.

Which means reading a checkpoint means reading a **pickle**, and
unpickling is famously arbitrary code execution: the `REDUCE` opcode
means "call this callable", and a malicious checkpoint is a well-known
attack. `torch.load` needs `weights_only=True` and an allowlist to be
safe.

This reader never calls anything. `GLOBAL` pushes the *name* of a
callable; `REDUCE` consults a fixed table of shapes it knows how to build
as data:

| name | becomes |
|---|---|
| `torch._utils._rebuild_tensor_v2` / `_v3` | a tensor descriptor |
| `torch._utils._rebuild_parameter` | its wrapped tensor |
| `collections.OrderedDict`, `builtins.dict` | an empty dict |
| *anything else* | an opaque node |

So the worst a hostile checkpoint can do is produce a confusing tree.
There is no code path that reaches an interpreter, an allocator sized by
an attacker's integer, or a read outside the mapping:

* every length read from the stream is checked against the bytes that
  remain, before it is used;
* memo ids and stack depths are checked before use;
* the opcode loop is step-bounded, and an opcode that fails to advance
  is an error, so a crafted stream cannot spin;
* each tensor's *reach* — `offset + Σ (dimᵢ−1)·strideᵢ`, which for a
  transpose is nothing like `nelems·esize` — is bounded against the zip
  member the storage actually resolves to;
* element counts accumulate with an overflow check rather than being
  multiplied and hoped for.

## mmap-backed and lazy

Only the pickle is read up front. Listing the tensors of a 4.6 GB
checkpoint costs megabytes, and tensor bytes are addressed straight out
of the mapping — the same contract as
[`safetensor`](../safetensor) and [`gguf`](../gguf).

Torch writes tensor storages ZIP-*stored* (never deflated), which is
what makes in-place addressing possible. A compressed storage is
reported rather than silently mis-read.

## Names

Tensors come out as the dotted path from the pickle root. A plain
state_dict gives `blocks.0.attn.qkv.weight`; a training checkpoint saved
as `{"model": sd, "epoch": n}` gives `model.blocks.0.…`. Nothing is
stripped — what the file says is what you get.

## Views

Non-contiguous tensors (a transpose, a column slice) are read correctly:
the element at logical index *n* is found through the strides, so the
values come out in **the tensor's** order, not the storage's.
`pt_is_contiguous` reports which is which, and the CLI marks them
`[view]`, because only a contiguous tensor's bytes can be handed to a
kernel as-is.

## API

```
( pt_open path )                       → !*Pt String
( pt_close p )                         → v
( pt_n_tensors p )                     → i
( pt_name p idx )                      → s      BORROWED
( pt_find p name )                     → i      -1 when absent
( pt_dtype p idx )                     → i      PKS_F32, PKS_BF16, …
( pt_ndim p idx ) ( pt_dim p idx j ) ( pt_stride p idx j )
( pt_nelems p idx ) ( pt_nbytes p idx )
( pt_is_contiguous p idx )             → b
( pt_tensor_ptr p idx )                → *u     into the mapping
( pt_dequant p idx )                   → !( Vec u ) String   f32 LE bytes
( pt_dequant_range p idx first count ) → !( Vec u ) String
( pt_read_f64 p idx first count dst )  → b      into an f64 buffer
```

Every dtype widens on demand: `f64`, `f32`, `f16`, `bf16`, `i64`, `i32`,
`i16`, `i8`, `u8`, `bool`.

The pickle reader is usable on its own — `src/pickle.nu` parses any
protocol 0–5 pickle into a value tree (`pk_kind` / `pk_item` / `pk_key` /
`pk_dict_get` …), which is handy for the non-tensor half of a checkpoint
(hyperparameters, epoch counters, config dicts).

## Tests

`tests/torchpt_test.sh` uses `torch.load` itself as the oracle:
`tests/make_fixtures.py` writes the `.pt` files *and* the values torch
reads back, and torchpt must reproduce every tensor exactly. The
fixtures deliberately cover every storage dtype, pickle protocols 2
through 5 (4+ switches to `FRAME` / `SHORT_BINUNICODE` / `MEMOIZE` /
`STACK_GLOBAL`), nested checkpoint dicts, tensors sharing one storage,
transposed and sliced views, and scalar and zero-element tensors — then
a battery of malformed files that must each be a clean error.

```
cd packages/torchpt && ./tests/torchpt_test.sh
```

Needs a python with torch (any CPU build) for the oracle; without one
those steps skip and the malformed-input battery still runs.
