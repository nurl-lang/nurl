# tensor — n-dimensional arrays for NURL

The reusable ndarray the ML ecosystem was missing. Today tensor logic is
welded inside the `onnx` runtime (its `RTensor` is bound to the graph engine),
and [`gpukit`](../gpukit) is a marshalling floor nobody wants to program
against. `tensor` is the shared layer — shape, broadcasting, matmul and
reductions — that `onnx`, `anomaly` and a future training package can all sit
on, GPU-accelerated through gpukit.

## Use

```nurl
$ `deps/tensor/src/ops.nu`   // ops.nu re-exports the tensor core

// a 2×3 tensor from a flat buffer (shape vec is adopted)
: ( Vec i ) shp ( vec_new [i] ) ( vec_push [i] shp 2 ) ( vec_push [i] shp 3 )
: Tensor a ( tensor_from_data TE_F64 shp data )

: Tensor half ( tensor_muls a 0.5 )              // scalar op → Tensor
?? ( tensor_transpose a ) {
    T at → {
        ?? ( tensor_matmul a at ) {              // a · aᵀ → ?Tensor
            T c → { /* … use c … */ ( tensor_free c ) }
            F _ → {}
        }
        ( tensor_free at )
    }
    F _ → {}
}
: Tensor col_sum ( tensor_sum a 0 F )            // reduce over axis 0
( tensor_free half ) ( tensor_free col_sum ) ( tensor_free a )
```

## The type

```nurl
: Tensor { i dtype  ( Vec i ) shape  ( Vec f ) data }
```

Row-major contiguous, computed in **f64**. `dtype` is `TE_F64` (exact f64) or
`TE_F32` — an F32 tensor keeps its values on the float32 grid (results are
rounded to f32 after each op), so it behaves like float32 for interop while the
maths runs in f64.

## API

Creation — the `shape` vector is **adopted** (the tensor owns it):

| Call | |
| --- | --- |
| `( tensor_zeros dt shape )` · `_ones` · `( tensor_full dt shape v )` | filled |
| `( tensor_from_data dt shape data )` | from an f64 buffer (copied, rounded) |
| `( tensor_arange dt n )` | 1-D `[0 … n-1]` |
| `( tensor_of dt shape data )`, `( tensor_clone t )`, `( tensor_free t )` | |

Queries / access: `tensor_ndim`, `tensor_size`, `tensor_dtype`, `tensor_dim`,
`tensor_shape` (borrow), `tensor_data` (borrow), `tensor_flat` / `tensor_set_flat`.

Shape: `tensor_reshape` → `?Tensor`, `tensor_transpose` (2-D) → `?Tensor`,
`tensor_permute t perm` → `?Tensor`, `tensor_astype t dt`.

Elementwise (numpy broadcasting) → `?Tensor`: `tensor_add` / `sub` / `mul` /
`div` / `pow` / `maximum` / `minimum`. Scalar forms → `Tensor`: `tensor_adds` /
`subs` / `muls` / `divs`.

Unary → `Tensor`: `tensor_neg` / `abs` / `exp` / `log` / `sqrt` / `relu` /
`sigmoid` / `tanh`.

Matmul: `( tensor_matmul a b )` → `?Tensor` — 2-D `(M,K)·(K,N)`.
`( tensor_bmm a b )` → `?Tensor` — N-D batched matmul: the last two dims are the
matrix, leading batch dims broadcast (numpy rule).

Reductions → `Tensor` (axis `< 0` reduces everything; `keepdim` is a `b`):
`( tensor_sum t axis keepdim )` and `_mean` / `_max` / `_min` / `_prod`.

Slicing / joining / indexing:

| Call | |
| --- | --- |
| `( tensor_slice t starts stops )` → `?Tensor` | per-dim half-open `[start,stop)` |
| `( tensor_concat2 a b axis )` → `?Tensor` | concatenate along an axis |
| `( tensor_softmax t axis )` → `Tensor` | stable softmax over one axis |
| `( tensor_argmax t axis keepdim )` · `_argmin` → `Tensor` | arg index (as f64) along an axis |

## GPU

`tensor_matmul` runs on the GPU via gpukit's `gk_matmul_f` for large f64
problems (`M·N·K ≥ 100k`) and on a plain triple loop otherwise — **the results
are identical** (the kernel accumulates in the same order). A device is opened
lazily and shared; `tensor_gpu_close` releases it. With no GPU (or no C++
compiler for the gpukit CPU backend) everything stays on the loop.

## Numerics

Computation is f64; F32 tensors round their outputs to the f32 grid.
Elementwise ops and matmul are exact to f64 (and bit-identical across the GPU
and CPU paths); reductions accumulate sequentially, so they match a
pairwise-summing reference (numpy) to rounding. Verified against numpy:
creation, reshape, broadcasting, matmul (incl. a 128×128 GPU case), transpose,
a 3-D permute, all reductions, the unary maps, and the M2 ops — batched matmul
(with batch broadcasting), softmax, slicing, concat, and argmax/argmin —
**25 / 25**.

## Tests

`./tests/tensor_test.sh` builds `tests/tcheck.nu`, checks every op against
numpy, and re-runs under AddressSanitizer. **25/25, ASan-clean.** Skips cleanly
without numpy.

## Roadmap

Gather/scatter and fancy indexing, conv, native-f32 GPU kernels, and — the
payoff — porting `onnx`'s `RTensor` + ops onto this layer so tensors stop being
ONNX-only. (Done in 0.2.0: batched/N-D matmul, softmax, slicing, concat,
argmax/argmin.)
