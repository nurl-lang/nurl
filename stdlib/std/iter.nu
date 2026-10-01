// stdlib/std/iter.nu — eager ranges + lazy iterator chain (auto-drop)
//
// Two complementary APIs live here:
//
//   1. Eager (Vec-producing or callback-driven):
//        ( range from to )           → ( Vec i )
//        ( range_step from to step ) → ( Vec i )
//        ( range_each from to f )    → v          allocation-free loop
//
//   2. Lazy (closure pipeline) — element-count-independent memory:
//        ( Iter A )  ≡  (@ ? A i)
//
//      A SINGLE closure that takes a command:
//        cmd = 0 → advance, return Some(next) / None when exhausted
//        cmd = 1 → end: this iterator, and every iterator it reads from,
//                  reports exhausted from then on; returns None. It
//                  releases nothing — releasing is the owner's drop.
//
//      Why one closure with a command rather than a {next,free} struct?
//      A struct `{ (@ ? A) nxt, (@ v) fr }` would make `( Iter A )` a
//      generic struct that text-substitutes `A` into its body — and the
//      text-level pre-pass `scan_generic_structs` then tries to
//      monomorphise `Iter[A]` / `Iter[B]` from generic *function*
//      signatures (where `A`/`B` are tparams, not concrete), producing
//      undefined LLVM types `%A`, `%B`. The single-closure form
//      sidesteps the issue entirely.
//
// Memory model — nothing to release by hand:
//
//   An iterator is an ordinary closure value that owns what it uses. Its
//   cursor (the one word that changes as it advances) sits in a `Cell`
//   the closure captures, and a combinator's closure captures the
//   iterators it reads from; an env keeps its own copy of a captured
//   closure, so the envs of a chain form a tree (docs/MEMORY.md §7.5).
//   Dropping the outermost closure — its binding leaving scope, a
//   temporary after the call it was passed to, the struct that holds it —
//   releases the whole chain, every env and every cursor, whether the
//   chain was drained, half consumed or never started.
//
//   Copies of an iterator (the copy a combinator's env or a struct field
//   keeps) share its cursor, as copies of a pointer did: advancing one
//   advances them all. The Cell counts its owners and the last copy
//   frees it.
//
//   Combinators TAKE their source and function (`sink`): a temporary —
//   `( iter_map ( iter_range 0 n ) f )` — moves into the new iterator's
//   env as is; a binding is copied, and stays its owner's. Consumers
//   BORROW the iterator: they drain it and leave it to its owner. `iter_free` is an optional early release (its `sink`
//   parameter is the drop); `cmd=1` stays accepted for callers that
//   ended a chain that way, as a plain "end".
//
// Lazy API:
//   Constructors:
//     ( iter_range from to )            → ( Iter i )
//     ( iter_range_step from to step )  → ( Iter i )   step ≠ 0
//     ( iter_from_vec [A] v )           → ( Iter A )   borrows v
//     ( iter_repeat [A] x n )           → ( Iter A )   trivial A only
//
//   Combinators (Iter → Iter, consume the input):
//     ( iter_map   [A B] src f )        → ( Iter B )   f : (@ B A)
//     ( iter_filter [A] src pred )      → ( Iter A )   pred : (@ b A)
//     ( iter_take  [A] src n )          → ( Iter A )
//     ( iter_skip  [A] src n )          → ( Iter A )
//     ( iter_chain [A] a b )            → ( Iter A )   concatenate
//     ( iter_zip   [A B] a b )          → ( Iter ( Pair A B ) )   pair-wise
//     ( iter_enumerate [A] src )        → ( Iter ( Pair i A ) )   index + value
//
//   Consumers (Iter → result, borrow and drain):
//     ( iter_each   [A] src f )         → v            f : (@ v A)
//     ( iter_fold   [A B] src init f )  → B            f : (@ B B A)
//     ( iter_collect [A] src )          → ( Vec A )    materialise
//     ( iter_count  [A] src )           → i
//     ( iter_sum_i  src )               → i            Iter[i] → sum
//     ( iter_any    [A] src pred )      → b            short-circuit
//     ( iter_all    [A] src pred )      → b            short-circuit
//     ( iter_find   [A] src pred )      → ? A          first match
//
//   Early release (optional — dropping the iterator releases it anyway):
//     ( iter_free [A] src )             → v
//
// Example pipeline — sum of squares of even numbers in [0..n):
//   : (@ b i) is_even \ i x → b { ^ == 0 % x 2 }
//   : (@ i i) sq      \ i x → i { ^ * x x }
//   : i s ( iter_sum_i ( iter_map [i i]
//                          ( iter_filter [i] ( iter_range 0 n ) is_even )
//                          sq ) )
//   // Nothing to free: the chain is a temporary of the iter_sum_i call
//   // and is dropped, envs and cursors alike, when that call returns.
//
// SOURCE-MUTATION CAVEAT: an iterator borrows its source. Mutating the
// source (e.g. vec_push during iteration) is undefined — same rule as
// Rust's `iter()`. The captured length / pointer may go stale.

$ `stdlib/core/vec.nu`
$ `stdlib/core/pair.nu`
$ `stdlib/core/cell.nu`

// ─── Early release (optional) ─────────────────────────────────────
// Let go of a chain now rather than when its owner goes out of scope.

@ iter_free [A] sink ( @ ?A i ) src → v {}

// ─── Eager ranges (return Vec[i]) ─────────────────────────────────

@ range i from i to → ( Vec i ) {
    : i n ? > to from - to from 0
    : ( Vec i ) out ( vec_with_cap [i] n )
    : ~ i k from
    ~ < k to {
        ( vec_push [i] out k )
        = k + k 1
    }
    ^ out
}

@ range_step i from i to i step → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    ? == step 0 { ^ out } {}
    ? > step 0 {
        : ~ i k from
        ~ < k to {
            ( vec_push [i] out k )
            = k + k step
        }
    } {
        : ~ i k from
        ~ > k to {
            ( vec_push [i] out k )
            = k + k step
        }
    }
    ^ out
}

@ range_each i from i to ( @ v i ) f → v {
    : ~ i k from
    ~ < k to {
        ( f k )
        = k + k 1
    }
}

// ─── Lazy iterator chain ──────────────────────────────────────────
//
// A cursor is one word in a Cell: `cell_ptr_as` once per call, then a
// plain load and store. Bounds, steps and counts are captured by value.
// cmd=1 moves a constructor's cursor to its end, and every combinator
// passes it on, so the whole chain ends.

// Constructor — ascending integer iterator over [from..to).
// Cursor: the next value.
@ iter_range i from i to → ( @ ?i i ) {
    : Cell st ( cell_zero 8 )
    : *i c0 ( cell_ptr_as [i] st )
    = . c0 0 from
    ^ \ i cmd → ?i {
        : *i c ( cell_ptr_as [i] st )
        ? == cmd 1 { = . c 0 to ^ @ ?i { F 0 } } {}
        : i cur . c 0
        ? >= cur to { ^ @ ?i { F 0 } } {}
        = . c 0 + cur 1
        ^ @ ?i { T cur }
    }
}

// Constructor — strided integer iterator. Direction picked from sign
// of step. step == 0 produces an empty iterator (safe, no hang).
// Cursor: the next value.
@ iter_range_step i from i to i step → ( @ ?i i ) {
    : Cell st ( cell_zero 8 )
    : *i c0 ( cell_ptr_as [i] st )
    = . c0 0 from
    ^ \ i cmd → ?i {
        : *i c ( cell_ptr_as [i] st )
        ? == cmd 1 { = . c 0 to ^ @ ?i { F 0 } } {}
        ? == step 0 { ^ @ ?i { F 0 } } {}
        : i cur . c 0
        : b at_end ? > step 0 >= cur to <= cur to
        ? at_end { ^ @ ?i { F 0 } } {}
        = . c 0 + cur step
        ^ @ ?i { T cur }
    }
}

// Constructor — borrowing iterator over a Vec[A]. Lends the Vec handle
// and captures its length at construction time; do not mutate the Vec
// while iterating. The Vec itself is NOT freed by the iterator.
// Cursor: the next index.
@ iter_from_vec [A] ( Vec A ) v → ( @ ?A i ) {
    : Cell st ( cell_zero 8 )
    : i n ( vec_len [A] v )
    ^ \ i cmd → ?A {
        : *i c ( cell_ptr_as [i] st )
        ? == cmd 1 { = . c 0 n ^ @ ?A { F # A 0 } } {}
        : i idx . c 0
        ? >= idx n { ^ @ ?A { F # A 0 } } {}
        = . c 0 + idx 1
        ^ ( vec_get [A] v idx )
    }
}

// Constructor — repeat a single value n times. Trivial element types
// only (i, f, b, raw s, slice) — owned types like String would alias.
// Cursor: how many have been yielded.
@ iter_repeat [A] A x i n → ( @ ?A i ) {
    : Cell st ( cell_zero 8 )
    ^ \ i cmd → ?A {
        : *i c ( cell_ptr_as [i] st )
        ? == cmd 1 { = . c 0 n ^ @ ?A { F # A 0 } } {}
        : i k . c 0
        ? >= k n { ^ @ ?A { F # A 0 } } {}
        = . c 0 + k 1
        ^ @ ?A { T x }
    }
}

// Combinator — apply f to every element. No state of its own.
@ iter_map [A B] sink ( @ ?A i ) src sink ( @ B A ) f → ( @ ?B i ) {
    ^ \ i cmd → ?B {
        ? == cmd 1 { ( src 1 ) ^ @ ?B { F # B 0 } } {}
        : ?A got ( src 0 )
        ?? got {
            T x → { ^ @ ?B { T ( f x ) } }
            F → { ^ @ ?B { F # B 0 } }
        }
    }
}

// Combinator — keep elements where pred returns T. Drains upstream
// inside a single cmd=0 call until either a matching element or
// upstream exhaustion is reached. No state of its own.
@ iter_filter [A] sink ( @ ?A i ) src sink ( @ b A ) pred → ( @ ?A i ) {
    ^ \ i cmd → ?A {
        ? == cmd 1 { ( src 1 ) ^ @ ?A { F # A 0 } } {}
        : ~ b done F
        : ~ ? A out @ ?A { F # A 0 }
        ~ ! done {
            : ?A got ( src 0 )
            ?? got {
                T x → {
                    ? ( pred x ) {
                        = out @ ?A { T x }
                        = done T
                    } {}
                }
                F → { = done T }
            }
        }
        ^ out
    }
}

// Combinator — yield at most n elements then act exhausted.
// Cursor: how many have been taken.
@ iter_take [A] sink ( @ ?A i ) src i n → ( @ ?A i ) {
    : Cell st ( cell_zero 8 )
    ^ \ i cmd → ?A {
        ? == cmd 1 { ( src 1 ) ^ @ ?A { F # A 0 } } {}
        : *i c ( cell_ptr_as [i] st )
        : i taken . c 0
        ? >= taken n { ^ @ ?A { F # A 0 } } {}
        : ?A got ( src 0 )
        ?? got {
            T x → {
                = . c 0 + taken 1
                ^ @ ?A { T x }
            }
            F → { ^ @ ?A { F # A 0 } }
        }
    }
}

// Combinator — discard the first n elements, then yield the rest.
// Cursor: how many have been skipped.
@ iter_skip [A] sink ( @ ?A i ) src i n → ( @ ?A i ) {
    : Cell st ( cell_zero 8 )
    ^ \ i cmd → ?A {
        ? == cmd 1 { ( src 1 ) ^ @ ?A { F # A 0 } } {}
        : *i c ( cell_ptr_as [i] st )
        : ~ b done F
        : ~ ? A out @ ?A { F # A 0 }
        ~ ! done {
            : i sk . c 0
            ? >= sk n {
                = out ( src 0 )
                = done T
            } {
                : ?A got ( src 0 )
                ?? got {
                    T x → { = . c 0 + sk 1 }
                    F → { = done T }
                }
            }
        }
        ^ out
    }
}

// Combinator — pair-wise zip. Yields ( Pair A B ) until either source
// exhausts. No state of its own; cmd=1 ends BOTH inputs.
//
// MEMORY: the resulting Pair fields are aliases of the upstream
// elements — do NOT iter_collect a Pair-of-owned-types pipeline and
// then drop both the upstream sources and the collected Vec.
@ iter_zip [A B] sink ( @ ?A i ) a sink ( @ ?B i ) b → ( @ ?( Pair A B ) i ) {
    ^ \ i cmd → ?( Pair A B ) {
        ? == cmd 1 {
            ( a 1 )
            ( b 1 )
            ^ @ ?( Pair A B ) { F # ( Pair A B ) 0 }
        } {}
        : ?A ga ( a 0 )
        ?? ga {
            T xa → {
                : ?B gb ( b 0 )
                ?? gb {
                    T xb → { ^ @ ?( Pair A B ) { T ( pair_new [A B] xa xb ) } }
                    F → { ^ @ ?( Pair A B ) { F # ( Pair A B ) 0 } }
                }
            }
            F → { ^ @ ?( Pair A B ) { F # ( Pair A B ) 0 } }
        }
    }
}

// Combinator — pair each element with its 0-based index.
// Cursor: the next index.
@ iter_enumerate [A] sink ( @ ?A i ) src → ( @ ?( Pair i A ) i ) {
    : Cell st ( cell_zero 8 )
    ^ \ i cmd → ?( Pair i A ) {
        ? == cmd 1 {
            ( src 1 )
            ^ @ ?( Pair i A ) { F # ( Pair i A ) 0 }
        } {}
        : ?A got ( src 0 )
        ?? got {
            T x → {
                : *i c ( cell_ptr_as [i] st )
                : i k . c 0
                = . c 0 + k 1
                ^ @ ?( Pair i A ) { T ( pair_new [i A] k x ) }
            }
            F → { ^ @ ?( Pair i A ) { F # ( Pair i A ) 0 } }
        }
    }
}

// Combinator — concatenate two iterators. cmd=1 ends BOTH.
// Cursor: the phase (0 = first, 1 = second).
@ iter_chain [A] sink ( @ ?A i ) a sink ( @ ?A i ) b → ( @ ?A i ) {
    : Cell st ( cell_zero 8 )
    ^ \ i cmd → ?A {
        ? == cmd 1 {
            ( a 1 )
            ( b 1 )
            ^ @ ?A { F # A 0 }
        } {}
        : *i c ( cell_ptr_as [i] st )
        ? == . c 0 0 {
            : ?A got ( a 0 )
            ?? got {
                T x → { ^ @ ?A { T x } }
                F → { = . c 0 1 }
            }
        } {}
        ^ ( b 0 )
    }
}

// ─── Consumers (borrow the iterator and drain it) ─────────────────

@ iter_each [A] ( @ ?A i ) src ( @ v A ) f → v {
    : ~ b done F
    ~ ! done {
        : ?A got ( src 0 )
        ?? got {
            T x → { ( f x ) }
            F → { = done T }
        }
    }
}

@ iter_fold [A B] ( @ ?A i ) src B init ( @ B B A ) f → B {
    : ~ B acc init
    : ~ b done F
    ~ ! done {
        : ?A got ( src 0 )
        ?? got {
            T x → { = acc ( f acc x ) }
            F → { = done T }
        }
    }
    ^ acc
}

@ iter_collect [A] ( @ ?A i ) src → ( Vec A ) {
    : ( Vec A ) out ( vec_new [A] )
    : ~ b done F
    ~ ! done {
        : ?A got ( src 0 )
        ?? got {
            T x → { ( vec_push [A] out x ) }
            F → { = done T }
        }
    }
    ^ out
}

@ iter_count [A] ( @ ?A i ) src → i {
    : ~ i n 0
    : ~ b done F
    ~ ! done {
        : ?A got ( src 0 )
        ?? got {
            T x → { = n + n 1 }
            F → { = done T }
        }
    }
    ^ n
}

@ iter_sum_i ( @ ?i i ) src → i {
    : ~ i sum 0
    : ~ b done F
    ~ ! done {
        : ?i got ( src 0 )
        ?? got {
            T x → { = sum + sum x }
            F → { = done T }
        }
    }
    ^ sum
}

@ iter_any [A] ( @ ?A i ) src ( @ b A ) pred → b {
    : ~ b found F
    : ~ b done F
    ~ ! done {
        : ?A got ( src 0 )
        ?? got {
            T x → {
                ? ( pred x ) {
                    = found T
                    = done T
                } {}
            }
            F → { = done T }
        }
    }
    ^ found
}

@ iter_all [A] ( @ ?A i ) src ( @ b A ) pred → b {
    : ~ b ok T
    : ~ b done F
    ~ ! done {
        : ?A got ( src 0 )
        ?? got {
            T x → {
                ? ! ( pred x ) {
                    = ok F
                    = done T
                } {}
            }
            F → { = done T }
        }
    }
    ^ ok
}

@ iter_find [A] ( @ ?A i ) src ( @ b A ) pred → ?A {
    : ~ ? A out @ ?A { F # A 0 }
    : ~ b done F
    ~ ! done {
        : ?A got ( src 0 )
        ?? got {
            T x → {
                ? ( pred x ) {
                    = out @ ?A { T x }
                    = done T
                } {}
            }
            F → { = done T }
        }
    }
    ^ out
}
