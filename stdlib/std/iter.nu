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
//        cmd = 1 → release this iterator's state buffer (and recursively
//                  any upstream chain), return None
//
//      Constructors allocate their state via `nurl_zalloc` and bake the
//      release path into the same closure body, so consumers can free
//      the entire chain with one call.
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
//      State buffers are RELEASED by `cmd=1`. Closure ENV blocks
//      (~16 B for constructors, ~40 B per combinator) are not yet
//      auto-freed — the compiler's RC infrastructure is dormant. The
//      env leak is **constant per pipeline**, not per element, so it
//      does not grow with workload size and is acceptable for CLI- and
//      data-processing-scale code.
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
//   Consumers (Iter → result, consume + auto-release):
//     ( iter_each   [A] src f )         → v            f : (@ v A)
//     ( iter_fold   [A B] src init f )  → B            f : (@ B B A)
//     ( iter_collect [A] src )          → ( Vec A )    materialise
//     ( iter_count  [A] src )           → i
//     ( iter_sum_i  src )               → i            Iter[i] → sum
//     ( iter_any    [A] src pred )      → b            short-circuit
//     ( iter_all    [A] src pred )      → b            short-circuit
//     ( iter_find   [A] src pred )      → ? A          first match
//
//   Manual release (only when abandoning a chain without consuming):
//     ( iter_free [A] src )             → v            (calls cmd=1)
//
// Example pipeline — sum of squares of even numbers in [0..n):
//   : (@ b i) is_even \ i x → b { ^ == 0 % x 2 }
//   : (@ i i) sq      \ i x → i { ^ * x x }
//   : i s ( iter_sum_i ( iter_map [i i]
//                          ( iter_filter [i] ( iter_range 0 n ) is_even )
//                          sq ) )
//   // No state leak: iter_sum_i issues cmd=1 to the outer iter,
//   // which cascades down the chain freeing every state buffer.
//
// SOURCE-MUTATION CAVEAT: an iterator borrows its source. Mutating the
// source (e.g. vec_push during iteration) is undefined — same rule as
// Rust's `iter()`. The captured length / pointer may go stale.

$ `stdlib/core/vec.nu`
$ `stdlib/core/pair.nu`

// ─── Public manual-release wrapper ────────────────────────────────
// Use only when you abandon a chain mid-stream without running it
// through a consumer. Consumers all call cmd=1 internally.

@ iter_free [A] ( @ ?A i ) src → v {
    ( src 1 )
}

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

// Constructor — ascending integer iterator over [from..to).
// State layout: [cur, lim] (16 bytes).
@ iter_range i from i to → ( @ ?i i ) {
    : s st ( nurl_zalloc 16 )
    ( nurl_poke st 0 from )
    ( nurl_poke st 1 to )
    ^ \ i cmd → ?i {
        ? == cmd 1 { ( nurl_free st ) ^ @ ?i { F 0 } } {}
        : i cur ( nurl_peek st 0 )
        : i lim ( nurl_peek st 1 )
        ? >= cur lim { ^ @ ?i { F 0 } } {}
        ( nurl_poke st 0 + cur 1 )
        ^ @ ?i { T cur }
    }
}

// Constructor — strided integer iterator. Direction picked from sign
// of step. step == 0 produces an empty iterator (safe, no hang).
// State layout: [cur, lim, step] (24 bytes).
@ iter_range_step i from i to i step → ( @ ?i i ) {
    : s st ( nurl_zalloc 24 )
    ( nurl_poke st 0 from )
    ( nurl_poke st 1 to )
    ( nurl_poke st 2 step )
    ^ \ i cmd → ?i {
        ? == cmd 1 { ( nurl_free st ) ^ @ ?i { F 0 } } {}
        : i cur ( nurl_peek st 0 )
        : i lim ( nurl_peek st 1 )
        : i step ( nurl_peek st 2 )
        ? == step 0 { ^ @ ?i { F 0 } } {}
        : ~ b at_end F
        ? > step 0 {
            ? >= cur lim { = at_end T } {}
        } {
            ? <= cur lim { = at_end T } {}
        }
        ? at_end { ^ @ ?i { F 0 } } {}
        ( nurl_poke st 0 + cur step )
        ^ @ ?i { T cur }
    }
}

// Constructor — borrowing iterator over a Vec[A]. Captures the Vec
// handle and length at construction time; do not mutate the Vec while
// iterating. The Vec itself is NOT freed by the iterator.
// State layout: [idx] (8 bytes).
@ iter_from_vec [A] ( Vec A ) v → ( @ ?A i ) {
    : s st ( nurl_zalloc 8 )
    ( nurl_poke st 0 0 )
    : i n ( vec_len [A] v )
    ^ \ i cmd → ?A {
        ? == cmd 1 { ( nurl_free st ) ^ @ ?A { F # A 0 } } {}
        : i idx ( nurl_peek st 0 )
        ? >= idx n { ^ @ ?A { F # A 0 } } {}
        ( nurl_poke st 0 + idx 1 )
        ^ ( vec_get [A] v idx )
    }
}

// Constructor — repeat a single value n times. Trivial element types
// only (i, f, b, raw s, slice) — owned types like String would alias.
// State layout: [k] (8 bytes).
@ iter_repeat [A] A x i n → ( @ ?A i ) {
    : s st ( nurl_zalloc 8 )
    ( nurl_poke st 0 0 )
    ^ \ i cmd → ?A {
        ? == cmd 1 { ( nurl_free st ) ^ @ ?A { F # A 0 } } {}
        : i k ( nurl_peek st 0 )
        ? >= k n { ^ @ ?A { F # A 0 } } {}
        ( nurl_poke st 0 + k 1 )
        ^ @ ?A { T x }
    }
}

// Combinator — apply f to every element. No own state; cmd=1 cascades
// to upstream.
@ iter_map [A B] ( @ ?A i ) src ( @ B A ) f → ( @ ?B i ) {
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
// upstream exhaustion is reached. cmd=1 cascades to upstream.
@ iter_filter [A] ( @ ?A i ) src ( @ b A ) pred → ( @ ?A i ) {
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
// State layout: [taken] (8 bytes).
@ iter_take [A] ( @ ?A i ) src i n → ( @ ?A i ) {
    : s st ( nurl_zalloc 8 )
    ( nurl_poke st 0 0 )
    ^ \ i cmd → ?A {
        ? == cmd 1 { ( src 1 ) ( nurl_free st ) ^ @ ?A { F # A 0 } } {}
        : i taken ( nurl_peek st 0 )
        ? >= taken n { ^ @ ?A { F # A 0 } } {}
        : ?A got ( src 0 )
        ?? got {
            T x → {
                ( nurl_poke st 0 + taken 1 )
                ^ @ ?A { T x }
            }
            F → { ^ @ ?A { F # A 0 } }
        }
    }
}

// Combinator — discard the first n elements, then yield the rest.
// State layout: [skipped] (8 bytes).
@ iter_skip [A] ( @ ?A i ) src i n → ( @ ?A i ) {
    : s st ( nurl_zalloc 8 )
    ( nurl_poke st 0 0 )
    ^ \ i cmd → ?A {
        ? == cmd 1 { ( src 1 ) ( nurl_free st ) ^ @ ?A { F # A 0 } } {}
        : ~ b done F
        : ~ ? A out @ ?A { F # A 0 }
        ~ ! done {
            : i sk ( nurl_peek st 0 )
            ? >= sk n {
                = out ( src 0 )
                = done T
            } {
                : ?A got ( src 0 )
                ?? got {
                    T x → { ( nurl_poke st 0 + sk 1 ) }
                    F → { = done T }
                }
            }
        }
        ^ out
    }
}

// Combinator — pair-wise zip. Yields ( Pair A B ) until either source
// exhausts. cmd=1 cascades to BOTH inputs.
// State layout: none.
//
// MEMORY: the resulting Pair fields are aliases of the upstream
// elements — do NOT iter_collect a Pair-of-owned-types pipeline and
// then drop both the upstream sources and the collected Vec.
@ iter_zip [A B] ( @ ?A i ) a ( @ ?B i ) b → ( @ ?( Pair A B ) i ) {
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

// Combinator — pair each element with its 0-based index. cmd=1 frees
// the index counter and cascades upstream.
// State layout: [idx] (8 bytes).
@ iter_enumerate [A] ( @ ?A i ) src → ( @ ?( Pair i A ) i ) {
    : s st ( nurl_zalloc 8 )
    ( nurl_poke st 0 0 )
    ^ \ i cmd → ?( Pair i A ) {
        ? == cmd 1 {
            ( src 1 )
            ( nurl_free st )
            ^ @ ?( Pair i A ) { F # ( Pair i A ) 0 }
        } {}
        : ?A got ( src 0 )
        ?? got {
            T x → {
                : i k ( nurl_peek st 0 )
                ( nurl_poke st 0 + k 1 )
                ^ @ ?( Pair i A ) { T ( pair_new [i A] k x ) }
            }
            F → { ^ @ ?( Pair i A ) { F # ( Pair i A ) 0 } }
        }
    }
}

// Combinator — concatenate two iterators. cmd=1 cascades to BOTH.
// State layout: [phase] (8 bytes; 0 = first, 1 = second).
@ iter_chain [A] ( @ ?A i ) a ( @ ?A i ) b → ( @ ?A i ) {
    : s st ( nurl_zalloc 8 )
    ( nurl_poke st 0 0 )
    ^ \ i cmd → ?A {
        ? == cmd 1 {
            ( a 1 )
            ( b 1 )
            ( nurl_free st )
            ^ @ ?A { F # A 0 }
        } {}
        : i phase ( nurl_peek st 0 )
        ? == phase 0 {
            : ?A got ( a 0 )
            ?? got {
                T x → { ^ @ ?A { T x } }
                F → { ( nurl_poke st 0 1 ) }
            }
        } {}
        ^ ( b 0 )
    }
}

// ─── Consumers (consume + auto-release) ───────────────────────────

@ iter_each [A] ( @ ?A i ) src ( @ v A ) f → v {
    : ~ b done F
    ~ ! done {
        : ?A got ( src 0 )
        ?? got {
            T x → { ( f x ) }
            F → { = done T }
        }
    }
    ( src 1 )
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
    ( src 1 )
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
    ( src 1 )
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
    ( src 1 )
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
    ( src 1 )
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
    ( src 1 )
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
    ( src 1 )
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
    ( src 1 )
    ^ out
}
