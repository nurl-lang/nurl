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

& `c` @ calloc i count i size → s

// …zeroed, as calloc gives them.
unsafe inline @ raw_block_zero i n → RawBlock {
    ^ @ RawBlock { ( calloc 1 ? > n 0 n 1 ) n }
}

unsafe inline @ raw_block_ptr RawBlock b → *u { ^ # *u . b ptr }

// ── A release a panic can go on with ───────────────────────────────
// A container that releases its entries by hand (a HashMap's slots, a
// Deque's two runs, a BTree's nodes) drops each one through a destructor
// that may be the program's own — and may panic. The panic leaves the
// loop, and nothing would stand for the entries after it: no destructor
// for them, and what they owned leaked (agora #659).
//
// So such a release has two halves, and each container writes both:
//
//  1. Its release is RESTARTABLE: an entry leaves the container — the
//     count goes down, the slot is marked, the kid is unlinked — BEFORE
//     its destructor runs. Whenever a destructor runs, or panics, the
//     container holds exactly the entries still to go, and running the
//     release again releases those.
//  2. While it runs, a record of its own type (`MapRelease`, `DqRelease`,
//     …) is a binding of the releasing frame, so the journal holds it: a
//     panic's drain drops the record, and the record's drop is
//     `mem_release_rest` over the same release. When the release returns
//     the record is forgotten: there is nothing left it stands for.
//
// Only where dropping an entry runs code of the program's own
// (`( mem_drop_runs_code [T] )`, a constant): a container of anything else
// keeps the plain loop, and costs what it always did.
//
// `again` is run until it returns. A panic out of it — a later entry's
// destructor — is caught here and it is run again, on the same frame:
// however many destructors panic, the stack is no deeper than for one
// (the runtime's element release does the same, agora #608). Each round
// drops at least the entry that panicked, so it ends. The panic already
// on its way, the cause, keeps its own message.
unsafe @ mem_release_rest ( @ v ) again → v {
    : *u fnp # *u again 0
    : *u env # *u again 1
    ~ != 0 ( nurl_recover fnp env ) {}
}
