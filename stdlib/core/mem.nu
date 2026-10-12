// stdlib/core/mem.nu — typed memory allocation wrappers
//
// Thin generic wrappers around the `nurl_alloc` / `nurl_zalloc` runtime
// calls. They compute `sizeof(T) * n` via `Z T` and bitcast the returned
// `i8*` to `*T`.
//
//   ( alloc  [T] n )   →  *T    uninitialised buffer for n items
//   ( zalloc [T] n )   →  *T    zero-initialised buffer for n items
//   ( mem_replace [T] place x ) → T   x into place, its old value out
//   ( raw_block n )    →  RawBlock   n bytes that release themselves
//
// Release with ( nurl_free #s p ). Typed `drop`/`resize` may follow.
//
// Sizes are checked (`alloc_size`, stdlib/core/vec.nu): a count whose byte
// size cannot be represented panics before anything is allocated.

$ `stdlib/core/vec.nu`

@ alloc [T] i n → *T {
    ^ # *T ( nurl_alloc ( alloc_size Z T n ) )
}

@ zalloc [T] i n → *T {
    ^ # *T ( nurl_zalloc ( alloc_size Z T n ) )
}

// `x` goes into `place` and what `place` held comes back, owned — nothing
// is dropped and nothing is copied (Rust's std::mem::replace). The place is
// passed as an inout argument: a mutable binding, a field of one, or a
// field through a pointer (`( mem_replace [String] . r out ( string_new ) )`
// takes the output a state record holds out of it, an empty one left in
// its place).
unsafe @ mem_replace [T] inout T place sink T x → T {
    : *T p ( mem_addr place )
    : T old . p 0
    ( mem_take old )  // the value leaves the place
    = . p 0 x
    ^ old
}

// ── RawBlock: raw memory that releases itself ──────────────────────
// `n` bytes from the C allocator (uninitialised, as malloc gives them),
// released when the block is dropped — for code that works through a typed
// pointer into the memory and must not release it by hand:
//
//   : RawBlock xb ( raw_block * n 8 )
//   : *f x # *f ( raw_block_ptr xb )
//
// The pointer is malloc's own result, which the optimiser knows is fresh
// memory nothing else points into: a loop over several blocks keeps the
// alias facts a Vec's data pointer — read back from its control block —
// does not carry (bench/nbody.nu's seven arrays run 1.8x faster this way).
// The hook is `unsafe`, so the type is sealed: only `unsafe` code builds a
// block or writes its fields.
: RawBlock { s ptr i size }

% Drop RawBlock { unsafe @ drop RawBlock b → v { ( free . b ptr ) } }

unsafe inline @ raw_block i n → RawBlock {
    ^ @ RawBlock { ( malloc ? > n 0 n 1 ) n }
}

unsafe inline @ raw_block_ptr RawBlock b → *u { ^ # *u . b ptr }
