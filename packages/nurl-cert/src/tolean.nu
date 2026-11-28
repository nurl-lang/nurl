// tolean.nu — nurlc's core IR as a program of formal/A2's calculus, for
// the verified checker of formal/C to decide (AGORA-1020; the translation
// AGORA-975 wrote in Python, tools/ncore/tolean.py, which stays the
// reference: this file prints exactly what it prints, byte for byte, and
// refuses exactly what it refuses, with the same message, as
// tools/ncore/tolean_parity.sh checks over every certify program and
// every hole probe).
//
//   ( tolean_translate core_text ) → !String String
//
// T: the Lean file (`import C.A2Prog` … the `#eval` of the checker's
// verdict), as tolean.py prints it on stdout. F: why the program is not
// translated, as tolean.py prints it after `unsupported: `; or, starting
// `internal: `, a core IR this reader cannot read, where tolean.py stops
// with an exception (the translation panics there, and tolean_translate
// recovers).
//
// What is translated, and how, is tolean.py's; each function here is the
// one of that file it is named after, and its comments say why the
// translation is what it is. In short: a function's body is a block
// whose statements are A2's, each binding scoped over the rest of its
// list; numbers are A2's integers, a String or a Vec of numbers a buffer,
// a raw string bound from a literal or a fresh string owned text and one
// that holds a view a slice; a struct is its fields in pairs, an option a
// sum, a `% Drop` type A2's destructor type, a closure a package of its
// type's interface; the standard library's calls are A2's constructs
// (`intrinsic`). Anything else is unsupported, and the program is not
// emitted.
//
// Beyond tolean.py (A3, AGORA-1020): a program that spawns
// (`thread_spawn_owned` in a function of its own) is translated for A3's
// checker (`C.certOK3B P spawns entry 1`, formal/C/Cert3.lean): a thread
// handle and its error enum are integers, a result `{ i1, T, E }` is
// `sum E T` (the error the first variant, as an option's None), a channel
// share (`Channel_share`) is A2's `lockClone` (a binding bound from
// another one moves it, as nurlc says: one owner), and a spawned closure is of class `send`: its captures held by value (numbers,
// Vecs of numbers, channel shares), none by name. Each closure code spawned
// gets a spawn wrapper, a function that takes the closure over (`sink`) and
// calls it; the spawn is a call of the wrapper (A3 runs it as a thread,
// `def spawns` lists the wrappers), and its result the ok variant around a
// handle; `thread_join` reads the handle and answers a number. A program
// that does not spawn is translated exactly as tolean.py translates it.
//
// Intentional deviations from tolean.py (fail closed on malformed IR):
// where tolean.py reads a core IR nurlc never prints as if it were well
// formed, this translator refuses it (`internal: malformed …`, exit 1 of
// `nurl-cert translate`), before translating the function:
// - a statement whose operand count is below 0 or exceeds the operand
//   words it has, or is short of them (all but `agg`, whose type follows)
//   (`call`, `closure`, `callind`, `scalar`, `agg`), or whose count is not
//   a number: tolean.py takes the words there are (`eval call f 1` became
//   a call of no argument), or stops where it first reads the count;
// - a block opener (`scope`, `if`, `loop`, `match`, `foreach`, `defer`)
//   with no `end` before the function's end, and a closer out of place
//   (an `end` with no block open, an `else` not in an `if`, an `arm` not
//   in a `match`, a `loopcond` not in a `loop`): tolean.py ran an unclosed
//   block to the function's end. An empty `scope` … `end` stays valid.
// - a variable id below 0 in a statement (`malformed: …`), and in the
//   core IR's records (coreir.nu: a count below 0, a function left open, a
//   variable's id below 0 or kind outside 0–3, a type's counts past its
//   line).
// (A limit, not a choice: a variable id past core_id_max, or a count or
// parameter number past 64 bits, which tolean.py reads as an unbounded
// integer, is refused here too.)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/panic.nu`
$ `coreir.nu`

// ── Text ─────────────────────────────────────────────────────────────

@ __eq s a s b → b { ^ != 0 ( nurl_str_eq a b ) }

@ __sw s a s p → b { ^ != 0 ( nurl_str_starts a p ) }

@ __ew s a s p → b { ^ != 0 ( nurl_str_ends a p ) }

@ __has s a s needle → b { ^ >= ( nurl_str_find a needle ) 0 }

@ __ns i x → String {
    : String o ( string_new )
    ( string_push_int o x )
    ^ o
}

// a[from:to], with Python's rules: a negative end counts from the end,
// an end past either side is clamped.
@ __sl s a i from i to → String {
    : i n ( nurl_str_len a )
    : ~ i x from
    ? < x 0 { = x + n x } {}
    ? < x 0 { = x 0 } {}
    ? > x n { = x n } {}
    : ~ i y to
    ? < y 0 { = y + n y } {}
    ? < y 0 { = y 0 } {}
    ? > y n { = y n } {}
    : String o ( string_new )
    ? < x y { ( string_push_window o ( slice_of_str a ) x - y x ) } {}
    ^ o
}

@ __from s a i from → String { ^ ( __sl a from ( nurl_str_len a ) ) }

// `t.lstrip("%")`
@ __lstrip_pct s a → String {
    : ( Slice u ) t ( slice_of_str a )
    : i n ( slice_len [u] t )
    : ~ i k 0
    ~ & < k n == ( slice_byte t k ) 37 { = k + k 1 }
    ^ ( __from a k )
}

// `a[k:].isdigit()`: not empty, and every byte a digit.
@ __isdig_from s a i k → b {
    : ( Slice u ) t ( slice_of_str a )
    : i n ( slice_len [u] t )
    ? >= k n { ^ F } {}
    : ~ i j k
    ~ < j n {
        : i c ( slice_byte t j )
        ? | < c 48 > c 57 { ^ F } {}
        = j + j 1
    }
    ^ T
}

@ __isdig s a → b { ^ ( __isdig_from a 0 ) }

// `op.startswith("v") and op[1:].isdigit()`: a whole variable.
@ __vref s op → b { ^ & ( __sw op `v` ) ( __isdig_from op 1 ) }

// `int(a[k:])` of an id, where tolean.py's `int` would stop the run on
// anything but a number. (Python's integers have no bound: an id past
// core_id_max, which nurlc never prints, stops this run too: A2's
// numbering of it is printed, and would not fit.)
@ __pint_from s a i k → i {
    : String x ( __from a k )
    ?? ( core_parse_int ( string_data x ) ) {
        T v → {
            ? > v ( core_id_max ) { ( panic `internal: a variable id past the bound the core IR keeps to (2^62)` ) } {}
            ? < v 0 { ( panic `internal: malformed: a variable id below 0` ) } {}
            ^ v
        }
        F → {}
    }
    ( panic `internal: a number expected in the core IR` )
    ^ 0
}

// Python's `int()` syntax (core_parse_int's), whatever the size.
@ __int_syntax s a → b {
    : ( Slice u ) t ( slice_of_str a )
    : ~ i n ( slice_len [u] t )
    : ~ i k 0
    ~ & < k n ( core_is_ws ( slice_byte t k ) ) { = k + k 1 }
    ~ & > n k ( core_is_ws ( slice_byte t - n 1 ) ) { = n - n 1 }
    ? & < k n | == ( slice_byte t k ) 45 == ( slice_byte t k ) 43 { = k + k 1 } {}
    ? >= k n { ^ F } {}
    : ~ b prev F
    ~ < k n {
        : i c ( slice_byte t k )
        ? == c 95 {
            ? | ! prev >= + k 1 n { ^ F } {}
            = prev F
        } {
            ? | < c 48 > c 57 { ^ F } {}
            = prev T
        }
        = k + k 1
    }
    ^ prev
}

// A count (`call f n`, `agg - n`, …): `int()`, where one past 64 bits is
// read as the largest (or smallest) count, which compares as Python's
// unbounded one does with every count the IR can hold.
@ __pcount s a → i {
    ?? ( core_parse_int a ) {
        T v → { ^ v }
        F → {}
    }
    ? ! ( __int_syntax a ) { ( panic `internal: a number expected in the core IR` ) } {}
    ? ( __has a `-` ) { ^ - -9223372036854775807 1 } {}
    ^ 9223372036854775807
}

// A number of digits (`isdigit` checked) as an index, or -1 past 64 bits:
// then it is no parameter's (tolean.py compares it with the count).
@ __pidx s a → i {
    ^ ?? ( core_parse_int a ) {
        T v → v
        F → -1
    }
}

@ __pint s a → i { ^ ( __pint_from a 0 ) }

// Is `a` the text `v<k>`?
@ __is_v s a i k → b {
    : String w ( __ns k )
    ^ & ( __sw a `v` ) ( __eq ( string_data ( __from a 1 ) ) ( string_data w ) )
}

// `tpl` with each `%` replaced by the next argument.
@ __fmt s tpl s a s b s c s d s e s f → String {
    : ( Slice u ) t ( slice_of_str tpl )
    : i n ( slice_len [u] t )
    : String o ( string_with_cap + + + + + + n ( nurl_str_len a ) ( nurl_str_len b ) ( nurl_str_len c ) ( nurl_str_len d )
    ( nurl_str_len e ) ( nurl_str_len f ) )
    : ~ i k 0
    : ~ i st 0
    : ~ i q 0
    ~ < k n {
        ? == ( slice_byte t k ) 37 {
            ( string_push_window o t st - k st )
            ? == q 0 { ( string_push_str o a ) } {
                ? == q 1 { ( string_push_str o b ) } {
                    ? == q 2 { ( string_push_str o c ) } {
                        ? == q 3 { ( string_push_str o d ) } {
                            ? == q 4 { ( string_push_str o e ) } { ( string_push_str o f ) }
                        }
                    }
                }
            }
            = q + q 1
            = st + k 1
        } {}
        = k + k 1
    }
    ( string_push_window o t st - n st )
    ^ o
}

@ __f1 s tpl s a → String { ^ ( __fmt tpl a `` `` `` `` `` ) }

@ __f2 s tpl s a s b → String { ^ ( __fmt tpl a b `` `` `` `` ) }

@ __f3 s tpl s a s b s c → String { ^ ( __fmt tpl a b c `` `` `` ) }

@ __f4 s tpl s a s b s c s d → String { ^ ( __fmt tpl a b c d `` `` ) }

@ __f5 s tpl s a s b s c s d s e → String { ^ ( __fmt tpl a b c d e `` ) }

@ __f6 s tpl s a s b s c s d s e s f → String { ^ ( __fmt tpl a b c d e f ) }

// "%" + t
@ __pct s t → String {
    : String o ( string_from `%` )
    ( string_push_str o t )
    ^ o
}

@ __int_ty s t → b {
    ? | | | ( __eq t `i64` ) ( __eq t `i1` ) ( __eq t `i32` ) ( __eq t `i16` ) { ^ T } {}
    ? | | | ( __eq t `i8` ) ( __eq t `void` ) ( __eq t `u64` ) ( __eq t `u32` ) { ^ T } {}
    ? | | | ( __eq t `u16` ) ( __eq t `u8` ) ( __eq t `f64` ) ( __eq t `f32` ) { ^ T } {}
    ^ | ( __eq t `double` ) ( __eq t `float` )
}

@ __sc s t → b { ^ | | ( __eq t `i` ) ( __eq t `u` ) ( __eq t `b` ) }

@ __opener s w → b {
    ^ | | | | | ( __eq w `scope` ) ( __eq w `if` ) ( __eq w `loop` ) ( __eq w `match` ) ( __eq w `foreach` ) ( __eq w `defer` )
}

@ __in ( Vec i ) v i x → b {
    : i n ( vec_len [i] v )
    : ~ i k 0
    ~ < k n {
        ? == ( vec_at [i] v k ) x { ^ T } {}
        = k + k 1
    }
    ^ F
}

@ __sin ( Vec String ) v s x → b {
    : i n ( vec_len [String] v )
    : ~ i k 0
    ~ < k n {
        ? ( __eq ( string_data ( vec_at [String] v k ) ) x ) { ^ T } {}
        = k + k 1
    }
    ^ F
}

@ __hs String x → i { ^ ( hash_string ( string_data x ) ) }

@ __es String a String b → b { ^ ( eq_string ( string_data a ) ( string_data b ) ) }

@ __mget ( HashMap String i ) mp s key → i {
    ^ ?? ( map_get_with [String i s] mp key \ s x → i { ^ ( hash_string x ) } \ String a s b → b { ^ ( eq_string ( string_data a ) b ) } ) {
        T v → v
        F → -1
    }
}

@ __mset ( HashMap String i ) mp s key i v → v {
    : ?i _o ( map_set [String i] mp ( string_from key ) v \ String x → i { ^ ( __hs x ) } \ String a String b → b { ^ ( __es a b ) } )
}

// ── The module ───────────────────────────────────────────────────────

// What every function's translation reads, set up before the first one.
: TlMod {
    CoreIR ir
    // the program's functions (no file of the standard library's), as
    // records of ir.fns: tolean.py's FNS
    ( Vec i ) prog
    // a program function's name → its index (A2's `Prog`): NAMES
    ( HashMap String i ) names
    // the types with a destructor A2 runs: DTOR_TYS
    ( HashMap String i ) dtor
    // per program function: each variable's flags (in the order of its
    // CoreFn's `vids`), and the parameters the walk inferred consumed or
    // kept, which are marked `sink` (4) unless `inout`
    ( Vec ( Vec i ) ) flg
    ( Vec ( Vec i ) ) sinkp
    // per program function (closure code): MOVED_CAPS, the captures every
    // literal of it moves into the environment
    ( Vec ( Vec i ) ) moved
    // A3 (beyond tolean.py): does the program spawn (`thread_spawn_owned`
    // in a function of its own)? Only then are threads, results, channel
    // shares and spawned closures translated: a program that does not
    // spawn is translated exactly as tolean.py translates it.
    b threaded
    // per program function: the closure values (core ids) a spawn takes,
    // through their `use` copies back to their literal, and each one's code
    ( Vec ( Vec i ) ) sendv
    ( Vec ( Vec i ) ) sendc
    // the closure codes spawned (program indices), in the order first seen:
    // spawn wrapper j is the one of spawned[j]
    ( Vec i ) spawned
    // per program function: why its spawns are not translated ("" none)
    ( Vec String ) serr
}

// What the translation changes as it goes: the closure interfaces and the
// types being expanded (the module's), and the function being translated
// (tolean.py's `Fn`).
: TlSt {
    ( Vec String ) clo_list
    i clo_base
    ( Vec String ) expanding
    i p
    i np
    i next
    b has_vmap
    // a closure's numbering: vmap[k] for the variable vmap_ids[k]
    ( Vec i ) vmap_ids
    ( Vec i ) vmap
    i rslot
    ( Vec i ) caps
    b closure
    ( Vec i ) named
    ( Vec i ) prms
    ( Vec i ) lits
    ( Vec i ) elems
    i depth
    String res_ty
    b res_own
    ( Vec i ) views
    ( Vec String ) lends
    // spawn wrapper j's interface (the spawned closure's σ), -1 not yet seen
    ( Vec i ) wsig
}

// (temporaries bound before a statement: A2 variable, right-hand side)
: Pre {
    ( Vec i ) t
    ( Vec String ) r
}

@ __pre_new → Pre { ^ @ Pre { ( vec_new [i] ) ( vec_new [String] ) } }

@ __pre_add Pre pre i t s r → v {
    ( vec_push [i] . pre t t )
    ( vec_push [String] . pre r ( string_from r ) )
}

@ __cf TlMod m i p → i { ^ ( vec_at [i] . m prog p ) }

@ __name TlMod m i p → s { ^ ( string_data . ( vec_at [CoreFn] . . m ir fns ( __cf m p ) ) name ) }

@ __ret TlMod m i p → s { ^ ( string_data . ( vec_at [CoreFn] . . m ir fns ( __cf m p ) ) ret ) }

@ __np TlMod m i p → i { ^ . ( vec_at [CoreFn] . . m ir fns ( __cf m p ) ) np }

@ __nl TlMod m i p → i { ^ - ( vec_len [i] . ( vec_at [CoreFn] . . m ir fns ( __cf m p ) ) wstart ) 1 }

@ __nw TlMod m i p i k → i { ^ ( core_nwords ( vec_at [CoreFn] . . m ir fns ( __cf m p ) ) k ) }

@ __wd TlMod m i p i k i j → s { ^ ( core_word ( vec_at [CoreFn] . . m ir fns ( __cf m p ) ) k j ) }

@ __vix TlMod m i p i id → i { ^ ( core_var ( vec_at [CoreFn] . . m ir fns ( __cf m p ) ) id ) }

@ __vhas TlMod m i p i id → b { ^ >= ( __vix m p id ) 0 }

// fn["vars"].get(id, d)
@ __vtyd TlMod m i p i id s d → s {
    : i k ( __vix m p id )
    ? < k 0 { ^ d } {}
    ^ ( string_data . ( vec_at [CoreVar] . ( vec_at [CoreFn] . . m ir fns ( __cf m p ) ) vars k ) ty )
}

// fn["vars"][id]: tolean.py stops on a variable the function does not have.
@ __vty TlMod m i p i id → s {
    ? ! ( __vhas m p id ) { ( panic `internal: a variable the function does not declare` ) } {}
    ^ ( __vtyd m p id `` )
}

// fn["kind"].get(id): -1 for none
@ __vkind TlMod m i p i id → i {
    : i k ( __vix m p id )
    ? < k 0 { ^ -1 } {}
    ^ . ( vec_at [CoreVar] . ( vec_at [CoreFn] . . m ir fns ( __cf m p ) ) vars k ) kind
}

// fn["flags"].get(id, 0)
@ __vflags TlMod m i p i id → i {
    : i k ( core_var_pos ( vec_at [CoreFn] . . m ir fns ( __cf m p ) ) id )
    : i base ? < k 0 0 ( vec_at [i] ( vec_at [( Vec i )] . m flg p ) k )
    ? & ( __in ( vec_at [( Vec i )] . m sinkp p ) id ) == 0 & base 2 { ^ | base 4 } {}
    ^ base
}

// The ids of fn["vars"], in increasing order.
@ __ids_sorted TlMod m i p → ( Vec i ) { ^ ( vec_clone [i] . ( vec_at [CoreFn] . . m ir fns ( __cf m p ) ) vids ) }

// The ids of fn["vars"], in the order of their first `v` line.
@ __ids_order TlMod m i p → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : CoreFn fn ( vec_at [CoreFn] . . m ir fns ( __cf m p ) )
    : i n ( vec_len [CoreVar] . fn vars )
    // (seen, by the id's place in `vids`)
    : ( Vec b ) seen ( vec_new [b] )
    : ~ i k 0
    ~ < k ( vec_len [i] . fn vids ) { ( vec_push [b] seen F ) = k + k 1 }
    = k 0
    ~ < k n {
        : i id . ( vec_at [CoreVar] . fn vars k ) id
        : i q ( core_var_pos fn id )
        ? ! ( vec_at [b] seen q ) {
            ( vec_put [b] seen q T )
            ( vec_push [i] out id )
        } {}
        = k + k 1
    }
    ^ out
}

// A statement of the function being translated, by reference: k ≥ 0 its
// body's line k, k < 0 that line (-k - 1), a `ret`, turned `retnx`.
// Word j of it: a word the statement does not have stops the run, as
// tolean.py's list index does (`__lws`: "" for it).
@ __lw TlMod m i p i r i j → s {
    ? >= j ( __lnw m p r ) { ( panic `internal: a word the core IR's statement does not have` ) } {}
    ^ ( __lws m p r j )
}

// (`head[k - 1]` is read: the statement has k words, or the run stops)
@ __need TlMod m i p i r i k → v {
    ? < ( __lnw m p r ) k { ( panic `internal: a word the core IR's statement does not have` ) } {}
}

@ __lws TlMod m i p i r i j → s {
    ? < r 0 {
        ? == j 0 { ^ `retnx` } {}
        ^ ( __wd m p - -1 r j )
    } {}
    ^ ( __wd m p r j )
}

@ __lnw TlMod m i p i r → i { ^ ( __nw m p ? < r 0 - -1 r r ) }

// SUMS.get(f, {}).get(key, d)
@ __sval TlMod m s f s key s d → s {
    : i si ( core_sum_index . m ir f )
    ? < si 0 { ^ d } {}
    : CoreSum sm ( vec_at [CoreSum] . . m ir sums si )
    : i k ( core_sum_key sm key )
    ? < k 0 { ^ d } {}
    ^ ( string_data ( vec_at [String] . sm vals k ) )
}

@ __shas TlMod m s f s key → b {
    : i si ( core_sum_index . m ir f )
    ? < si 0 { ^ F } {}
    ^ >= ( core_sum_key ( vec_at [CoreSum] . . m ir sums si ) key ) 0
}

@ __u TlMod m i p s msg → String { ^ ( __f2 `%: %` ( __name m p ) msg ) }

// ── Types ────────────────────────────────────────────────────────────

// borrowed: does function `f` hand back a value that views what it was
// handed (its summary: `ret_unowned=1`, or `rviews` naming a parameter)?
// (A `ret_owned` marker: it hands over a fresh result.)
@ __borrowed TlMod m s f → b {
    ? ( __shas m f `ret_owned` ) { ^ F } {}
    ? ( __eq ( __sval m f `ret_unowned` `` ) `1` ) { ^ T } {}
    : s rv ( __sval m f `rviews` `:` )
    ^ ! | ( __eq rv `:` ) ( __eq rv `` )
}

// view_deps: what `f`'s result may view, as A2 dependencies: `^k` the
// elements' insides (`inner`), `k` its own buffer or handle (`view`,
// `self`); `%k` (a copy of argument k's views) is not translated.
@ __view_deps TlMod m s f ( Vec i ) ks ( Vec String ) kinds → !v String {
    : String rv ( string_from ( __sval m f `rviews` `:` ) )
    : ( Slice u ) t ( slice_of_str ( string_data rv ) )
    : i n ( slice_len [u] t )
    : ~ i a 0
    ~ & < a n == ( slice_byte t a ) 58 { = a + a 1 }
    : ~ b more T
    ~ more {
        : ~ i z a
        ~ & < z n != ( slice_byte t z ) 44 { = z + z 1 }
        : ~ i x a
        ~ & < x z ( core_is_ws ( slice_byte t x ) ) { = x + x 1 }
        : ~ i y z
        ~ & > y x ( core_is_ws ( slice_byte t - y 1 ) ) { = y - y 1 }
        ? < x y {
            : String tok ( string_new )
            ( string_push_window tok t x - y x )
            : s tk ( string_data tok )
            ? ( __sw tk `%` ) {
                ^ @ !v String { F ( __f2 `%: a result holding a copy of argument %'s views` f ( string_data ( __from tk 1 ) ) ) }
            } {}
            ? & ( __sw tk `^` ) ( __isdig_from tk 1 ) {
                : i k ( __pidx ( string_data ( __from tk 1 ) ) )
                ? >= k 0 {
                    ( vec_push [i] ks k )
                    ( vec_push [String] kinds ( string_from `.inner` ) )
                } {}
            } {
                ? ( __isdig tk ) {
                    : i k ( __pidx tk )
                    ? >= k 0 {
                        ( vec_push [i] ks k )
                        ( vec_push [String] kinds ( string_from `.view` ) )
                        ( vec_push [i] ks k )
                        ( vec_push [String] kinds ( string_from `.self` ) )
                    } {}
                } {
                    ^ @ !v String { F ( __f2 `%: rviews %` f tk ) }
                }
            }
        } {}
        ? < z n { = a + z 1 } { = more F }
    }
    ^ @ !v String { T }
}

// clo_sig: a closure type's interface (`{ R (i8*, A…)*, i8* }`): its
// result, then its arguments, pushed onto `out` (each an IR type with no
// nested aggregate); F where `ty` is not a closure type.
@ __clo_sig s ty ( Vec String ) out → !b String {
    ? ! & & ( __sw ty `{ ` ) ( __ew ty `, i8* }` ) ( __has ty ` (i8*` ) { ^ @ !b String { T F } } {}
    : String head ( __sl ty 2 -7 )
    : s hd ( string_data head )
    : i at ( nurl_str_find hd ` (i8*` )
    : String r ? < at 0 ( string_from hd ) ( __sl hd 0 at )
    : String rest ? < at 0 ( string_new ) ( __from hd + at 5 )
    ? ! ( __ew ( string_data rest ) `)*` ) { ^ @ !b String { F ( __f1 `closure type %` ty ) } } {}
    : String ins ( __sl ( string_data rest ) 0 -2 )
    : ( Vec String ) all ( vec_new [String] )
    ( vec_push [String] all r )
    : ( Slice u ) t ( slice_of_str ( string_data ins ) )
    : i n ( slice_len [u] t )
    : ~ i a 0
    : ~ b more T
    ~ more {
        : ~ i z a
        ~ & < z n != ( slice_byte t z ) 44 { = z + z 1 }
        : ~ i x a
        ~ & < x z ( core_is_ws ( slice_byte t x ) ) { = x + x 1 }
        : ~ i y z
        ~ & > y x ( core_is_ws ( slice_byte t - y 1 ) ) { = y - y 1 }
        ? < x y {
            : String w ( string_new )
            ( string_push_window w t x - y x )
            ( vec_push [String] all w )
        } {}
        ? < z n { = a + z 1 } { = more F }
    }
    // a raw string a closure takes or hands back is a view or owned text
    // by its use, which a closure type does not say
    ? ( __sin all `i8*` ) { ^ @ !b String { F ( __f1 `closure type %: a raw string argument or result` ty ) } } {}
    : i na ( vec_len [String] all )
    : ~ i k 0
    ~ < k na {
        : s x ( string_data ( vec_at [String] all k ) )
        ? | | ( __has x `{` ) ( __has x `(` ) & ( __has x `*` ) ! ( __eq x `i8*` ) {
            ^ @ !b String { F ( __f1 `closure type %: a nested or pointer type` ty ) }
        } {}
        = k + k 1
    }
    = k 0
    ~ < k na {
        ( vec_push [String] out ( string_clone ( vec_at [String] all k ) ) )
        = k + k 1
    }
    ^ @ !b String { T T }
}

@ __is_clo s ty → !b String {
    : ( Vec String ) sig ( vec_new [String] )
    ^ ( __clo_sig ty sig )
}

// clo_index: the interface Fn index of closure type `ty` (one per type,
// after the program's own functions, in the order first seen).
@ __clo_index inout TlSt t s ty → i {
    : i n ( vec_len [String] . t clo_list )
    : ~ i k 0
    ~ < k n {
        ? ( __eq ( string_data ( vec_at [String] . t clo_list k ) ) ty ) { ^ + . t clo_base k } {}
        = k + k 1
    }
    ( vec_push [String] . t clo_list ( string_from ty ) )
    ^ + . t clo_base n
}

// The interface index of closure type `ty` taken at class `send` (A3: a
// spawned closure's): an interface of its own, apart from the type's `any`
// one (clo_list holds it as `send:` + ty).
@ __clo_index_send inout TlSt t s ty → i {
    : String k ( __f1 `send:%` ty )
    ^ ( __clo_index t ( string_data k ) )
}

// no_clo: a type inside another (an element, a payload, a field, a
// channel's element) is no closure: nurlc copies a closure stored in a
// value (`nurl_closure_own_copy`), which the core IR does not show.
@ __no_clo s ty → !v String {
    : b c \ ( __is_clo ty )
    ? c { ^ @ !v String { F ( __f1 `a closure inside a value (%)` ty ) } } {}
    ^ @ !v String { T }
}

// struct_fields: the `ty` record of struct `ty` (the name with its `%`), or -1.
@ __sfields TlMod m s ty → i {
    ? ( __sw ty `%` ) { ^ ( core_ty_index . m ir ty ) } {}
    : String k ( __pct ty )
    ^ ( core_ty_index . m ir ( string_data k ) )
}

@ __nf TlMod m i fs → i { ^ ( vec_len [String] . ( vec_at [CoreTy] . . m ir tys fs ) ftys ) }

@ __fty TlMod m i fs i k → s { ^ ( string_data ( vec_at [String] . ( vec_at [CoreTy] . . m ir tys fs ) ftys k ) ) }

@ __fnm TlMod m i fs i k → s { ^ ( string_data ( vec_at [String] . ( vec_at [CoreTy] . . m ir tys fs ) fnames k ) ) }

// dict(fs)[f]: the type of field `f` (the last of that name), or -1.
@ __field_ix TlMod m i fs s f → i {
    : ~ i k - ( __nf m fs ) 1
    ~ >= k 0 {
        ? ( __eq ( __fnm m fs k ) f ) { ^ k } {}
        = k - k 1
    }
    ^ -1
}

@ __dtor_has TlMod m s ty → b { ^ >= ( __mget . m dtor ty ) 0 }

// is_dtor: a type with a destructor (named with or without its `%`).
@ __is_dtor TlMod m s ty → b {
    ? ( __dtor_has m ty ) { ^ T } {}
    : String k ( __pct ty )
    ^ ( __dtor_has m ( string_data k ) )
}

@ __expanding TlSt t s ty → b { ^ ( __sin . t expanding ty ) }

@ __exp_pop inout TlSt t → v { : ?String _o ( vec_pop [String] . t expanding ) }

// dtor_field_ty: a destructor struct's field type: a raw string held in a
// value is a view of the text it was made from (MEMORY.md §2.13), a slice.
@ __dtor_field_ty TlMod m inout TlSt t s ft → !String String {
    ? ( __eq ft `i8*` ) { ^ @ !String String { T ( string_from `(.slice .int)` ) } } {}
    ^ ( __lean_ty m t ft )
}

// _struct_ty: a struct, its fields nested in pairs to the right; `dt`:
// a destructor struct's fields (dtor_field_ty), else lean_ty's.
@ __struct_ty TlMod m inout TlSt t i fs b dt → !String String {
    : i nf ( __nf m fs )
    ? ! dt {
        : ~ i k 0
        ~ < k nf {
            ? ( __eq ( __fty m fs k ) `i8*` ) { ^ @ !String String { F ( string_from `a raw string held in a struct field` ) } } {}
            = k + k 1
        }
    } {}
    : s last ( __fty m fs - nf 1 )
    \ ( __no_clo last )
    : ~ String acc ? dt \ ( __dtor_field_ty m t last ) \ ( __lean_ty m t last )
    : ~ i k - nf 2
    ~ >= k 0 {
        : s ft ( __fty m fs k )
        \ ( __no_clo ft )
        : String x ? dt \ ( __dtor_field_ty m t ft ) \ ( __lean_ty m t ft )
        = acc ( __f2 `(.prod % %)` ( string_data x ) ( string_data acc ) )
        = k - k 1
    }
    ^ @ !String String { T acc }
}

// dtor_of's `f`: the index of the destructor of type `ty` (`drop__T`), -1 none.
@ __dtor_f TlMod m s ty → i {
    : String st ( __lstrip_pct ty )
    : String k ( __f1 `drop__%` ( string_data st ) )
    ^ ( __mget . m names ( string_data k ) )
}

// dtor_of's `u`: a type with a `% Drop` of the program's own, its struct
// as A2's `Ty.dtor f u`; a struct of one field padded with an integer
// (`prod u int`): A2's destructor types are of a struct.
@ __dtor_of TlMod m inout TlSt t s ty → !String String {
    : i f ( __dtor_f m ty )
    : i fs ( __sfields m ty )
    ? | | < f 0 < fs 0 == 0 ( __nf m fs ) {
        ^ @ !String String { F ( __f1 `type %, with a destructor A2's translation does not see` ty ) }
    } {}
    : i nf ( __nf m fs )
    : ~ i k 0
    ~ < k nf {
        : s ft ( __fty m fs k )
        : String key ? ( __sw ft `%` ) ( string_from ft ) ( __pct ft )
        ? ( __dtor_has m ( string_data key ) ) {
            ^ @ !String String { F ( __f2 `type %, holding a value of a destructor type (%)` ty ft ) }
        } {}
        = k + k 1
    }
    ( vec_push [String] . t expanding ( string_from ty ) )
    : ~ String u ( string_new )
    ? == nf 1 {
        : String x \ ( __dtor_field_ty m t ( __fty m fs 0 ) )
        = u ( __f1 `(.prod % .int)` ( string_data x ) )
    } {
        = u \ ( __struct_ty m t fs T )
    }
    ( __exp_pop t )
    ^ @ !String String { T u }
}

// chan_elem: a channel's element type, where it holds no destructor
// value: an integer, a String, or a Vec of integers.
@ __chan_elem TlMod m inout TlSt t s ty → !String String {
    ? | | ( __int_ty ty ) ( __sc ty ) | ( __eq ty `String` ) ( __eq ty `%String` ) { ^ ( __lean_ty m t ty ) } {}
    : String st ( __lstrip_pct ty )
    ? & ( __sw ( string_data st ) `Vec__` ) ( __int_ty ( string_data ( __from ( string_data st ) 5 ) ) ) { ^ ( __lean_ty m t ty ) } {}
    ^ @ !String String { F ( __f1 `a channel of %` ty ) }
}

// A result's members (`T, E` of `{ i1, T, E }`): the index of the comma
// between them at the top level, or -1 (an option's one member).
@ __result_split s inner → i {
    : ( Slice u ) t ( slice_of_str inner )
    : i n ( slice_len [u] t )
    : ~ i d 0
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte t k )
        ? | == c 123 == c 40 { = d + d 1 } {}
        ? | == c 125 == c 41 { = d - d 1 } {}
        ? & & == d 0 == c 44 < + k 1 n { ? == ( slice_byte t + k 1 ) 32 { ^ k } {} } {}
        = k + k 1
    }
    ^ -1
}

// Is `ty` a result type (`{ i1, T, E }`)?
@ __is_result s ty → b {
    ? ! & ( __sw ty `{ i1, ` ) ( __ew ty ` }` ) { ^ F } {}
    : String inner ( __sl ty 6 -2 )
    ^ >= ( __result_split ( string_data inner ) ) 0
}

// %ThreadErr (A3): an enum whose variants carry only numbers, an integer.
@ __scalar_enum TlMod m s ty → b {
    : i k ( core_ty_index . m ir ty )
    ? < k 0 { ^ F } {}
    : CoreTy ct ( vec_at [CoreTy] . . m ir tys k )
    ? > ( vec_len [String] . ct ftys ) 0 { ^ F } {}
    : i n ( vec_len [String] . ct vtys )
    : ~ i j 0
    ~ < j n {
        : s x ( string_data ( vec_at [String] . ct vtys j ) )
        ? ! | ( __int_ty x ) ( __sc x ) { ^ F } {}
        = j + j 1
    }
    ^ T
}

// lean_ty: an IR type as an A2 type.
@ __lean_ty TlMod m inout TlSt t s ty → !String String {
    : String ls ( __lstrip_pct ty )
    ? | ( __int_ty ( string_data ls ) ) ( __sc ty ) {
        // (a scalar: A2's int, its value no part of the memory model)
        ^ @ !String String { T ( string_from `.int` ) }
    } {}
    ? ( __eq ty `i8*` ) {
        // a raw string bound from a literal or a fresh string: owned text,
        // A2's buffer of bytes (MEMORY.md §1)
        ^ @ !String String { T ( string_from `(.vec .int)` ) }
    } {}
    : ( Vec String ) sig ( vec_new [String] )
    : b isclo \ ( __clo_sig ty sig )
    ? isclo {
        // a closure: code and an environment it owns, of the program's
        // interface for its type; class `any`
        : i ns ( vec_len [String] sig )
        : ~ i k 0
        ~ < k ns {
            : String _x \ ( __lean_ty m t ( string_data ( vec_at [String] sig k ) ) )
            = k + k 1
        }
        : i ci ( __clo_index t ty )
        ^ @ !String String { T ( __f1 `(.fn [%] .any)` ( string_data ( __ns ci ) ) ) }
    } {}
    ? & ( __sw ty `{ i1, ` ) ( __ew ty ` }` ) {
        // A3: a result `{ i1, T, E }` is `sum E T`: the error (F) the first
        // variant, as an option's None, the value (T) the second
        : String inner ( __sl ty 6 -2 )
        : i cm ( __result_split ( string_data inner ) )
        ? >= cm 0 {
            : String a ( __sl ( string_data inner ) 0 cm )
            : String e ( __from ( string_data inner ) + cm 2 )
            \ ( __no_clo ( string_data a ) )
            \ ( __no_clo ( string_data e ) )
            // (a raw string held in a value is a view, MEMORY.md §2.13, not
            // translated yet, as a struct field's: also one nested in a
            // member, an option of raw text inside a result)
            ? | ( __has ( string_data a ) `i8*` ) ( __has ( string_data e ) `i8*` ) {
                ^ @ !String String { F ( __f1 `type %: a raw string held in a result` ty ) }
            } {}
            : String le \ ( __lean_ty m t ( string_data e ) )
            : String la \ ( __lean_ty m t ( string_data a ) )
            ^ @ !String String { T ( __f2 `(.sum % %)` ( string_data le ) ( string_data la ) ) }
        } {}
    } {}
    ? & ( __sw ty `{ i1, ` ) ( __ew ty ` }` ) {
        // an option: `sum int t`, None the first variant
        : String inner ( __sl ty 6 -2 )
        \ ( __no_clo ( string_data inner ) )
        // (a raw string held in a value is a view, MEMORY.md §2.13, not
        // translated yet, as a struct field's; AGORA-1045)
        ? ( __eq ( string_data inner ) `i8*` ) {
            ^ @ !String String { F ( __f1 `type %: a raw string held in an option` ty ) }
        } {}
        : String x \ ( __lean_ty m t ( string_data inner ) )
        ^ @ !String String { T ( __f1 `(.sum .int %)` ( string_data x ) ) }
    } {}
    // (a type argument's name, inside another: `%Vec__String`)
    : String tt ? ( __sw ty `%` ) ( string_from ty ) ( __pct ty )
    : s t2 ( string_data tt )
    ? . m threaded {
        // A3: a thread's handle is an integer (A3 has none: modelling no
        // join only adds interleavings)
        ? ( __eq t2 `%Thread` ) { ^ @ !String String { T ( string_from `.int` ) } } {}
        ? ( __eq t2 `%ThreadErr` ) {
            ? ! ( __scalar_enum m t2 ) { ^ @ !String String { F ( string_from `type %ThreadErr: an enum holding more than numbers` ) } } {}
        } {}
    } {}
    // an enum whose variants carry only numbers (%ThreadErr, %IoErr,
    // %NetErr): an integer, its tag; not one with a destructor, which is
    // A2's `Ty.dtor` (below)
    ? & ( __scalar_enum m t2 ) ! ( __dtor_has m t2 ) { ^ @ !String String { T ( string_from `.int` ) } } {}
    ? ( __sw t2 `%Vec__` ) {
        : String inner ( __from t2 6 )
        \ ( __no_clo ( string_data inner ) )
        : String x \ ( __lean_ty m t ( string_data inner ) )
        ^ @ !String String { T ( __f1 `(.vec %)` ( string_data x ) ) }
    } {}
    ? ( __sw t2 `%Channel__` ) {
        // A3.4: a `Channel A` is a lock share whose payload is its queue
        // and its closed flag, `lk (prod (vec A) int)`
        : String el \ ( __chan_elem m t ( string_data ( __from t2 10 ) ) )
        ^ @ !String String { T ( __f1 `(.lk (.prod (.vec %) .int))` ( string_data el ) ) }
    } {}
    ? | ( __eq t2 `%str` ) ( __eq t2 `str` ) {
        // a raw string held in a value is a view of a buffer someone else owns
        ^ @ !String String { T ( string_from `(.slice .int)` ) }
    } {}
    ? ( __eq t2 `%String` ) { ^ @ !String String { T ( string_from `(.vec .int)` ) } } {}
    ? ( __sw t2 `%Slice__` ) {
        : String x \ ( __lean_ty m t ( string_data ( __from t2 8 ) ) )
        ^ @ !String String { T ( __f1 `(.slice %)` ( string_data x ) ) }
    } {}
    ? ( __dtor_has m t2 ) {
        // A2's destructor type (`Ty.dtor f u`): its values are bound by
        // `letd`, whose scope's end runs `f` on them
        ? ( __expanding t t2 ) { ^ @ !String String { F ( __f1 `type %, recursive` t2 ) } } {}
        : i f ( __dtor_f m t2 )
        : String u \ ( __dtor_of m t t2 )
        ^ @ !String String { T ( __f2 `(.dtor % %)` ( string_data ( __ns f ) ) ( string_data u ) ) }
    } {}
    : i fs ( __sfields m t2 )
    ? & >= fs 0 ( __expanding t t2 ) { ^ @ !String String { F ( __f1 `type %, recursive` t2 ) } } {}
    ? >= fs 0 {
        : i nf ( __nf m fs )
        ? & == nf 1 ( __eq ( __fty m fs 0 ) `i8*` ) {
            ^ @ !String String { F ( __f1 `type %: a raw string held in a struct field` t2 ) }
        } {}
        ? == nf 1 {
            // a struct of one field: A2 has no one-element tuple, so it is its field
            ( vec_push [String] . t expanding ( string_from t2 ) )
            \ ( __no_clo ( __fty m fs 0 ) )
            : String x \ ( __lean_ty m t ( __fty m fs 0 ) )
            ( __exp_pop t )
            ^ @ !String String { T x }
        } {}
        ? >= nf 2 {
            ( vec_push [String] . t expanding ( string_from t2 ) )
            : String x \ ( __struct_ty m t fs F )
            ( __exp_pop t )
            ^ @ !String String { T x }
        } {}
    } {}
    ^ @ !String String { F ( __f1 `type %` t2 ) }
}

// vec_elem: `vec_push__i64` → the element type of the instance.
@ __vec_elem TlMod m inout TlSt t s f s prefix → !String String {
    ^ ( __lean_ty m t ( string_data ( __from f ( nurl_str_len prefix ) ) ) )
}

// cap_ty: a capture by value's A2 type, where the translation follows it:
// a number, or a buffer of numbers (a String, a `Vec` of numbers).
// A3: a spawned closure's capture may also be a channel's share
// (`lk …`), held by value (the spawned code `q`).
@ __cap_ty TlMod m inout TlSt t i q s ty → !String String {
    : String lt \ ( __lean_ty m t ty )
    ? | ( __eq ( string_data lt ) `.int` ) ( __eq ( string_data lt ) `(.vec .int)` ) { ^ @ !String String { T lt } } {}
    ? & & . m threaded ( __in . m spawned q ) ( __sw ( string_data lt ) `(.lk ` ) { ^ @ !String String { T lt } } {}
    ^ @ !String String { F ( __f1 `a capture of type %` ty ) }
}

@ __by_name TlMod m inout TlSt t i q s ty → !b String {
    : String c \ ( __cap_ty m t q ty )
    ^ @ !b String { T ! ( __eq ( string_data c ) `.int` ) }
}

// named_cap: is capture `k` of closure code `q` one by name? A buffer is,
// unless its env owns it (CORE_VF_ENVOWN, 2048: AGORA-978).
@ __named_cap TlMod m inout TlSt t i q i k → !b String {
    : b bn \ ( __by_name m t q ( __vty m q k ) )
    ^ @ !b String { T & bn == 0 & ( __vflags m q k ) 2048 }
}

// changes: does closure code `q` change capture `k` in place (a call of
// a buffer changer handed it)?
@ __changes TlMod m i q i k → b {
    : i nl ( __nl m q )
    : ~ i l 0
    ~ < l nl {
        : i nw ( __nw m q l )
        : ~ i i 0
        ~ & < i nw ! ( __eq ( __wd m q l i ) `call` ) { = i + i 1 }
        ? & < i nw > nw + i 3 {
            : s f ( __wd m q l + i 1 )
            ? | | | ( __sw f `vec_push__` ) ( __sw f `vec_clear__` ) ( __sw f `vec_truncate__` ) ( __sw f `vec_reserve__` ) {
                ? ( __is_v ( __wd m q l + i 3 ) k ) { ^ T } {}
            } {
                ? | ( __sw f `vec_shrink_to_fit__` ) ( __sw f `string_push_str` ) {
                    ? ( __is_v ( __wd m q l + i 3 ) k ) { ^ T } {}
                } {}
            }
        } {}
        = l + l 1
    }
    ^ F
}

// cap_mode: a capture by name's A2 mode in closure code `q`: read only
// (`inp`), or, taken by pointer or changed in place, `inout` at `drop`.
@ __cap_mode TlMod m inout TlSt t i q i k → !String String {
    ? & == 0 & ( __vflags m q k ) 8 ! ( __changes m q k ) { ^ @ !String String { T ( string_from `.inp` ) } } {}
    : String c \ ( __cap_ty m t q ( __vty m q k ) )
    ? ! ( __eq ( string_data c ) `(.vec .int)` ) { ^ @ !String String { F ( __u m q `a number capture taken by pointer` ) } } {}
    ^ @ !String String { T ( string_from `(.inout .drop)` ) }
}

// env_ty: a closure environment of captures of A2 types `tys`.
@ __env_ty ( Vec String ) tys → String {
    : i n ( vec_len [String] tys )
    ? == n 0 { ^ ( string_from `.int` ) } {}
    : ~ String acc ( string_clone ( vec_at [String] tys - n 1 ) )
    : ~ i k - n 2
    ~ >= k 0 {
        = acc ( __f2 `(.prod % %)` ( string_data ( vec_at [String] tys k ) ) ( string_data acc ) )
        = k - k 1
    }
    ^ acc
}

// fn_sigma: `(.fn [σ] .any)` → σ.
@ __fn_sigma s ty → !i String {
    : ( Slice u ) t ( slice_of_str ty )
    : i n ( slice_len [u] t )
    : b tail_ok | ( __ew ty `] .any)` ) ( __ew ty `] .send)` )
    : i tl ? ( __ew ty `] .any)` ) 7 8
    ? & ( __sw ty `(.fn [` ) tail_ok {
        : ~ i k 6
        : ~ i v 0
        ~ & < k n & >= ( slice_byte t k ) 48 <= ( slice_byte t k ) 57 {
            = v + * v 10 - ( slice_byte t k ) 48
            = k + k 1
        }
        ? & > k 6 == + k tl n { ^ @ !i String { T v } } {}
    } {}
    ^ @ !i String { F ( __f1 `a call through a value of type %` ty ) }
}

// is_moved: is capture `j` (in the code's order) of closure code `q`
// moved into the environment by every literal of it?
@ __is_moved TlMod m i q i j → b { ^ ( __in ( vec_at [( Vec i )] . m moved q ) j ) }

// summary_change: the A2 bound of what function `p` does to parameter `i`
// through the handle, from the walk's summary, or "" for nothing.
@ __sum_has_word TlMod m s f s key i i → b {
    : String v ( string_from ( __sval m f key `` ) )
    : ( Vec String ) ws ( vec_new [String] )
    : ( Slice u ) t ( slice_of_str ( string_data v ) )
    ( core_split_words t 0 ( slice_len [u] t ) ws )
    : String w ( __ns i )
    ^ ( __sin ws ( string_data w ) )
}

@ __summary_change TlMod m s f i i → String {
    : b d ( __sum_has_word m f `drops` i )
    : b r ( __sum_has_word m f `reallocs` i )
    : b ir ( __sum_has_word m f `ireallocs` i )
    : b mu ( __sum_has_word m f `mutates` i )
    ? | | d mu & r ir { ^ ( string_from `.drop` ) } {}
    ? r { ^ ( string_from `.realloc` ) } {}
    ? ir { ^ ( string_from `.dropIn` ) } {}
    ^ ( string_new )
}

// ── A function (tolean.py's `Fn`) ────────────────────────────────────

@ __var TlSt t i k → i {
    ? . t has_vmap {
        : i q ( core_bsearch . t vmap_ids k )
        ? < q 0 { ( panic `internal: a closure's variable the function does not declare` ) } {}
        : i v ( vec_at [i] . t vmap q )
        ? < v 0 { ( panic `internal: a closure's variable the function does not declare` ) } {}
        ^ v
    } {}
    ^ ? < k . t np k + k 1
}

@ __pvar TlMod m TlSt t s op → !i String {
    ? ! ( __vref op ) { ^ @ !i String { F ( __u m . t p ( string_data ( __f1 `the place % where a variable is needed` op ) ) ) } } {}
    ^ @ !i String { T ( __var t ( __pint_from op 1 ) ) }
}

@ __fresh inout TlSt t → i {
    = . t next + . t next 1
    ^ - . t next 1
}

// lit_temp: an integer temporary holding a number the IR does not track,
// bound (`.expr .any`) around the statement that consumes it (__stmts).
@ __lit_temp inout TlSt t → i {
    : i x ( __fresh t )
    ( vec_push [i] . t lits x )
    ^ x
}

// view_vars: the raw-string variables that hold a view, not their own
// text: bound from `string_data` or from a call whose result is
// borrowed, or handed one (`use`).
@ __view_vars TlMod m inout TlSt t → v {
    : i p . t p
    : i nl ( __nl m p )
    : ~ b changed T
    ~ changed {
        = changed F
        : ~ i l 0
        ~ < l nl {
            : i nw ( __nw m p l )
            : ~ i v 0
            : ~ b hit F
            ? & >= nw 4 & ( __eq ( __wd m p l 0 ) `let` ) ( __eq ( __wd m p l 2 ) `call` ) {
                : s f ( __wd m p l 3 )
                ? | | ( __eq f `string_data` ) ( __eq f `vec_at__str` ) ( __borrowed m f ) {
                    = v ( __pint ( __wd m p l 1 ) )
                    = hit T
                } {}
            } {
                ? & >= nw 4 & ( __eq ( __wd m p l 0 ) `let` ) ( __eq ( __wd m p l 2 ) `use` ) {
                    : s op ( __wd m p l 3 )
                    ? ( __vref op ) {
                        ? ( __in . t views ( __pint_from op 1 ) ) {
                            = v ( __pint ( __wd m p l 1 ) )
                            = hit T
                        } {}
                    } {}
                } {}
            }
            ? & hit ! ( __in . t views v ) {
                ( vec_push [i] . t views v )
                = changed T
            } {}
            = l + l 1
        }
    }
}

// views_of: `k` and the variables that may view it.
@ __views_of TlMod m TlSt t i k → ( Vec i ) {
    : i p . t p
    : ( Vec i ) out ( vec_new [i] )
    ( vec_push [i] out k )
    : i nl ( __nl m p )
    : ~ b changed T
    ~ changed {
        = changed F
        : ~ i l 0
        ~ < l nl {
            : i nw ( __nw m p l )
            ? & >= nw 3 ( __eq ( __wd m p l 0 ) `let` ) {
                : i j ( __pint ( __wd m p l 1 ) )
                ? ! ( __in out j ) {
                    // args = {a.split("/")[0] for a in w[3:]}: does one name a variable of `out`?
                    : ~ b hit F
                    : i no ( vec_len [i] out )
                    : ~ i a 3
                    ~ & < a nw ! hit {
                        : s arg ( __wd m p l a )
                        : i sl ( nurl_str_find arg `/` )
                        : String base ? < sl 0 ( string_from arg ) ( __sl arg 0 sl )
                        : ~ i q 0
                        ~ & < q no ! hit {
                            ? ( __is_v ( string_data base ) ( vec_at [i] out q ) ) { = hit T } {}
                            = q + q 1
                        }
                        = a + a 1
                    }
                    ? hit {
                        : s w2 ( __wd m p l 2 )
                        ? ( __eq w2 `call` ) {
                            : s f ( __wd m p l 3 )
                            ? | | | ( __sw f `string_data` ) ( __sw f `slice_from_vec__` ) | ( __sw f `vec_at__` ) ( __sw f `slice_at__` ) ( __borrowed m f ) {
                                ( vec_push [i] out j )
                                = changed T
                            } {}
                        } {
                            ? & & ( __eq w2 `use` ) == ( __vkind m p j ) 2 ( __in . t views j ) {
                                ( vec_push [i] out j )
                                = changed T
                            } {}
                        }
                    } {}
                } {}
            } {}
            = l + l 1
        }
    }
    ^ out
}

// vlean: variable `k`'s A2 type: a raw string that holds a view is a slice.
@ __vlean TlMod m inout TlSt t i k → !String String {
    : s ty ( __vty m . t p k )
    ? & ( __eq ty `i8*` ) ( __in . t views k ) { ^ @ !String String { T ( string_from `(.slice .int)` ) } } {}
    ? & . m threaded ( __in ( vec_at [( Vec i )] . m sendv . t p ) k ) {
        // A3: a closure value a spawn takes is of class `send` (its
        // environment holds no view and nothing by name: `.fn ms .send`)
        : ( Vec String ) sig ( vec_new [String] )
        : b isclo \ ( __clo_sig ty sig )
        ? isclo {
            : i ns ( vec_len [String] sig )
            : ~ i j 0
            ~ < j ns {
                : String _x \ ( __lean_ty m t ( string_data ( vec_at [String] sig j ) ) )
                = j + j 1
            }
            : i ci ( __clo_index_send t ty )
            ^ @ !String String { T ( __f1 `(.fn [%] .send)` ( string_data ( __ns ci ) ) ) }
        } {}
    } {}
    ^ ( __lean_ty m t ty )
}

// edit_through: a change of `y`'s elements: through `y` itself when it
// is a loop's borrowed element, else through a borrow of `y`.
@ __edit_through inout TlSt t i y s op → String {
    ? ( __in . t elems y ) { ^ ( __f2 `(.edit true % %)` ( string_data ( __ns y ) ) op ) } {}
    : i b ( __fresh t )
    : String bs ( __ns b )
    ^ ( __f4 `(.letv % (.borrow %) (.edit true % %))` ( string_data bs ) ( string_data ( __ns y ) ) ( string_data bs ) op )
}

// field_temp: `v/f`, the field read into a temporary through the pairs;
// the bindings it needs are added to `pre`.
@ __field_temp TlMod m inout TlSt t s op Pre pre → !i String {
    : i p . t p
    : i sl ( nurl_str_find op `/` )
    : String base ( __sl op 0 sl )
    : String field ( __from op + sl 1 )
    ? ( __has ( string_data field ) `/` ) { ^ @ !i String { F ( __u m p ( string_data ( __f1 `nested field %` op ) ) ) } } {}
    : i b ( __pint_from ( string_data base ) 1 )
    : s bt ( __vty m p b )
    : i fs ( __sfields m bt )
    : i nf ? >= fs 0 ( __nf m fs ) 0
    // (a destructor struct of one field is padded, `prod u int`: dtor_of)
    : b padded & & >= fs 0 == nf 1 ( __is_dtor m bt )
    ? & & >= fs 0 == nf 1 ! padded { ^ @ !i String { T ( __var t b ) } } {}
    ? | < fs 0 & < nf 2 ! padded { ^ @ !i String { F ( __u m p ( string_data ( __f1 `field of %` bt ) ) ) } } {}
    : i n ? padded + nf 1 nf
    : ~ i i -1
    : ~ i k 0
    ~ & < k nf == i -1 {
        ? ( __eq ( __fnm m fs k ) ( string_data field ) ) { = i k } {}
        = k + k 1
    }
    ? & == i -1 & padded ( __eq ( string_data field ) `(padding)` ) { = i nf } {}
    ? == i -1 { ( panic `internal: a field its struct does not have` ) } {}
    : ~ i cur ( __var t b )
    : ~ i q 0
    ~ < q i {
        : i x ( __fresh t )
        ( __pre_add pre x ( string_data ( __f1 `.snd %` ( string_data ( __ns cur ) ) ) ) )
        = cur x
        = q + q 1
    }
    ? < i - n 1 {
        : i x ( __fresh t )
        ( __pre_add pre x ( string_data ( __f1 `.fst %` ( string_data ( __ns cur ) ) ) ) )
        = cur x
    } {}
    ^ @ !i String { T cur }
}

// operand: an operand as an A2 expression (`c`, a number the IR does not
// track, read as a literal). `has_pre`: a field may be read into `pre`.
@ __operand TlMod m inout TlSt t s op b has_pre Pre pre → !String String {
    // AGORA-1030: a number the IR does not track is any number (`.any`), so
    // the model's runs include the program's whatever its numbers (a
    // `.lit 0` would make the model take every if's else arm)
    ? ( __eq op `c` ) { ^ @ !String String { T ( string_from `.any` ) } } {}
    ? & ( __has op `/` ) has_pre {
        : i x \ ( __field_temp m t op pre )
        ^ @ !String String { T ( __f1 `(.var %)` ( string_data ( __ns x ) ) ) }
    } {}
    ? ( __vref op ) {
        : i x \ ( __pvar m t op )
        ^ @ !String String { T ( __f1 `(.var %)` ( string_data ( __ns x ) ) ) }
    } {}
    ^ @ !String String { F ( __u m . t p ( string_data ( __f1 `operand %` op ) ) ) }
}

@ __operand0 TlMod m inout TlSt t s op → !String String {
    : Pre pre ( __pre_new )
    ^ ( __operand m t op F pre )
}

// vty: the IR type of a place: a variable's, or a field's through its struct.
@ __vty_place TlMod m TlSt t s op → !String String {
    : i p . t p
    : i sl ( nurl_str_find op `/` )
    : String base ? < sl 0 ( string_from op ) ( __sl op 0 sl )
    ? ! ( __vref ( string_data base ) ) { ^ @ !String String { F ( __u m p ( string_data ( __f1 `the place %` op ) ) ) } } {}
    : ~ String ty ( string_from ( __vtyd m p ( __pint_from ( string_data base ) 1 ) `i64` ) )
    ? >= sl 0 {
        : String path ( __from op + sl 1 )
        : ( Slice u ) pt ( slice_of_str ( string_data path ) )
        : i n ( slice_len [u] pt )
        : ~ i a 0
        : ~ b more T
        ~ more {
            : ~ i z a
            ~ & < z n != ( slice_byte pt z ) 47 { = z + z 1 }
            ? < a z {
                : String f ( string_new )
                ( string_push_window f pt a - z a )
                : i fs ( __sfields m ( string_data ty ) )
                : i fx ? >= fs 0 ( __field_ix m fs ( string_data f ) ) -1
                ? < fx 0 { ^ @ !String String { F ( __u m p ( string_data ( __f1 `the field path %` op ) ) ) } } {}
                = ty ( string_from ( __fty m fs fx ) )
            } {}
            ? < z n { = a + z 1 } { = more F }
        }
    } {}
    ^ @ !String String { T ty }
}

// flean: a field's A2 type: a destructor struct's raw string field is a view.
@ __flean TlMod m inout TlSt t s op → !String String {
    : i sl ( nurl_str_find op `/` )
    : String base ? < sl 0 ( string_from op ) ( __sl op 0 sl )
    : s bt ( __vtyd m . t p ( __pint_from ( string_data base ) 1 ) `` )
    : String vt \ ( __vty_place m t op )
    ? ( __is_dtor m bt ) { ^ ( __dtor_field_ty m t ( string_data vt ) ) } {}
    ^ ( __lean_ty m t ( string_data vt ) )
}

@ __is_int TlMod m TlSt t s op → !b String {
    ? ( __eq op `c` ) { ^ @ !b String { T T } } {}
    : String vt \ ( __vty_place m t op )
    ^ @ !b String { T ( __int_ty ( string_data vt ) ) }
}

// wrap: the bindings `pre` scoped over `st`.
@ __wrap Pre pre s st → String {
    : i n ( vec_len [i] . pre t )
    ? == n 0 { ^ ( string_from st ) } {}
    : String o ( string_new )
    : ~ i k 0
    ~ < k n {
        ( string_push_str o `(.letv ` )
        ( string_push_int o ( vec_at [i] . pre t k ) )
        ( string_push_str o ` (` )
        ( string_push_str o ( string_data ( vec_at [String] . pre r k ) ) )
        ( string_push_str o `) ` )
        = k + k 1
    }
    ( string_push_str o st )
    = k 0
    ~ < k n { ( string_push_char o 41 ) = k + k 1 }
    ^ o
}

@ __seq s a s b → String {
    ? ( __eq b `.skip` ) { ^ ( string_from a ) } {}
    ^ ( __f2 `(.seq % %)` a b )
}

// rw: word j of an rvalue that starts at word `off` of statement `r`.
@ __rw TlMod m TlSt t i r i off i j → s { ^ ( __lw m . t p r + off j ) }

// `words[base:base + n][k]` of the rvalue at `off`: the operand list's k-th.
@ __opw TlMod m TlSt t i r i off i base i n i k → s {
    ? | >= k n >= + + off base k ( __lnw m . t p r ) { ( panic `internal: an operand the core IR's call does not have` ) } {}
    ^ ( __rw m t r off + base k )
}

@ __isc s op → b { ^ ( __eq op `c` ) }

// rhs: an rvalue (the words of statement `r` from `off`) as an A2
// right-hand side, bound to core variable `dest` (`__nil`: none).
@ __rhs TlMod m inout TlSt t i r i off i dest b has_pre Pre pre b assign → !String String {
    : i p . t p
    : s k ( __rw m t r off 0 )
    : s w1 ? | | | ( __eq k `agg` ) ( __eq k `use` ) ( __eq k `payload` ) ( __eq k `scalar` ) ( __rw m t r off 1 ) ``
    ? & & ( __eq k `agg` ) | ( __eq w1 `T` ) ( __eq w1 `F` ) != dest ( __nil ) {
        // (a result's literal: not translated; its type `sum E T` with an
        // integer E reads like an option's, whose None has no payload)
        ? ( __is_result ( __vty m p dest ) ) { ^ @ !String String { F ( __u m p `a result literal` ) } } {}
        : String ty \ ( __lean_ty m t ( __vty m p dest ) )
        ? ! ( __sw ( string_data ty ) `(.sum .int ` ) { ^ @ !String String { F ( __u m p ( string_data ( __f1 `aggregate of type %` ( string_data ty ) ) ) ) } } {}
        : String pay ( __sl ( string_data ty ) 11 -1 )
        ? ( __eq w1 `F` ) {
            : i lt ( __lit_temp t )
            ^ @ !String String { T ( __f2 `.inl % %` ( string_data ( __ns lt ) ) ( string_data pay ) ) }
        } {}
        : s op ( __rw m t r off 3 )
        ? ( __eq op `c` ) {
            : i lt ( __lit_temp t )
            ^ @ !String String { T ( __f1 `.inr .int %` ( string_data ( __ns lt ) ) ) }
        } {}
        : i x \ ( __pvar m t op )
        ^ @ !String String { T ( __f1 `.inr .int %` ( string_data ( __ns x ) ) ) }
    } {}
    ? & ( __eq k `payload` ) & ( __eq ( __rw m t r off 2 ) `T` ) ( __eq ( __rw m t r off 3 ) `0` ) {
        : i x \ ( __pvar m t w1 )
        ^ @ !String String { T ( __f1 `.getr %` ( string_data ( __ns x ) ) ) }
    } {}
    ? & ( __eq k `payload` ) & ( __eq ( __rw m t r off 2 ) `F` ) ( __eq ( __rw m t r off 3 ) `0` ) {
        // a result's error, its first variant's payload, lent
        ? & ( __vref w1 ) ( __is_result ( __vtyd m p ( __pint_from w1 1 ) `` ) ) {
            : i x \ ( __pvar m t w1 )
            ^ @ !String String { T ( __f1 `.getl %` ( string_data ( __ns x ) ) ) }
        } {}
    } {}
    ? ( __eq k `none` ) {
        // a slot not yet given a value: only a scalar's is translated
        ? != dest ( __nil ) {
            : String lt \ ( __lean_ty m t ( __vtyd m p dest `i64` ) )
            ? ! ( __eq ( string_data lt ) `.int` ) { ^ @ !String String { F ( __u m p `an owner bound before its value` ) } } {}
        } {}
        ^ @ !String String { T ( string_from `.expr .any` ) }
    } {}
    ? & & ( __eq k `use` ) ( __eq w1 `c` ) & != dest ( __nil ) & ( __vhas m p dest ) ( __eq ( __vtyd m p dest `` ) `i8*` ) {
        // a literal: its own copy of the text
        ^ @ !String String { T ( string_from `.new .int` ) }
    } {}
    ? & ( __eq k `use` ) ( __has w1 `/` ) {
        // a field's value: an integer is read through the pairs; an owning
        // one would move out of its struct, which A2 does only by `unpair`
        : i sl ( nurl_str_find w1 `/` )
        : String base ( __sl w1 0 sl )
        : String field ( __from w1 + sl 1 )
        : i fs ( __sfields m ( __vtyd m p ( __pint_from ( string_data base ) 1 ) `` ) )
        : i fx ? >= fs 0 ( __field_ix m fs ( string_data field ) ) -1
        : b isint & >= fx 0 ( __int_ty ? >= fx 0 ( __fty m fs fx ) `` )
        ? | ! isint ! has_pre { ^ @ !String String { F ( __u m p ( string_data ( __f1 `the field % moved or copied` w1 ) ) ) } } {}
        : i x \ ( __field_temp m t w1 pre )
        ^ @ !String String { T ( __f1 `.expr (.var %)` ( string_data ( __ns x ) ) ) }
    } {}
    ? ( __eq k `use` ) {
        : s op w1
        : ~ b scalar ( __eq op `c` )
        ? ! scalar {
            : String vt \ ( __vty_place m t op )
            = scalar ( __int_ty ( string_data vt ) )
        } {}
        ? ! scalar {
            : i y ( __pint_from op 1 )
            : i ky ( __vkind m p y )
            : i fy ( __vflags m p y )
            : i kd ( __vkind m p dest )
            : i fd ( __vflags m p dest )
            : b y_s ( __eq ( __vtyd m p y `` ) `i8*` )
            : b y_has ( __vhas m p y )
            // (A `: ~` binding of another binding or of a parameter is a
            // cursor, a borrow of it, MEMORY.md §2.3; a temporary's value
            // moves into its holder.)
            ? & & ! assign != dest ( __nil ) & & == kd 1 != 0 & fd 1 | == ky 0 == ky 1 {
                ^ @ !String String { T ( __f1 `.borrow %` ( string_data ( __ns ( __var t y ) ) ) ) }
            } {}
            ? & & assign == ky 0 & & == 0 & fy 6 ! & y_has y_s != kd 0 {
                // a borrowed parameter assigned to a local: an owner turned
                // into a lend, which A2's bindings are not
                ^ @ !String String { F ( __u m p `an owner given a borrowed parameter's value` ) }
            } {}
            // vt.get(y) == vt.get(dest)
            : b d_has ( __vhas m p dest )
            : b same_ty | & ! y_has ! d_has & & y_has d_has ( __eq ( __vtyd m p y `` ) ( __vtyd m p dest `` ) )
            ? & & & assign has_pre == ky 0 & & == 0 & fy 6 == kd 0 & & != 0 & fd 2 same_ty ! & y_has y_s {
                // a borrowed parameter assigned to an `inout` one: codegen
                // copies it, a read of the parameter and a fresh owner
                : String ty \ ( __lean_ty m t ( __vty m p y ) )
                ? ! ( __sw ( string_data ty ) `(.vec ` ) { ^ @ !String String { F ( __u m p ( string_data ( __f1 `a copy of a % parameter` ( __vty m p y ) ) ) ) } } {}
                : i x ( __fresh t )
                ( __pre_add pre x ( string_data ( __f1 `.expr (.len %)` ( string_data ( __ns ( __var t y ) ) ) ) ) )
                ^ @ !String String { T ( __f1 `.new %` ( string_data ( __sl ( string_data ty ) 6 -1 ) ) ) }
            } {}
            ? & assign & y_has y_s {
                // `= dst src` of raw text copies it, which a move would not be
                ^ @ !String String { F ( __u m p `raw text assigned from another binding` ) }
            } {}
            ^ @ !String String { T ( __f1 `.var %` ( string_data ( __ns ( __var t y ) ) ) ) }
        } {}
        : String o \ ( __operand0 m t op )
        ^ @ !String String { T ( __f1 `.expr %` ( string_data o ) ) }
    } {}
    : b agg_ & & ( __eq k `agg` ) ( __eq w1 `-` ) != dest ( __nil )
    ? agg_ {
        : i n ( __pcount ( __rw m t r off 2 ) )
        ? & == n 1 ( __is_dtor m ( __vty m p dest ) ) {
            // a destructor struct of one field: its field and the padding
            : s op ( __rw m t r off 3 )
            : ~ i v 0
            ? ( __eq op `c` ) { = v ( __lit_temp t ) } { = v \ ( __pvar m t op ) }
            : i lt ( __lit_temp t )
            ^ @ !String String { T ( __f2 `.pair % %` ( string_data ( __ns v ) ) ( string_data ( __ns lt ) ) ) }
        } {}
        ? == n 1 {
            // a struct of one field is its field's value
            : s op ( __rw m t r off 3 )
            : ~ b sc ( __eq op `c` )
            ? ! sc { = sc \ ( __is_int m t op ) } {}
            ? sc {
                : String o \ ( __operand0 m t op )
                ^ @ !String String { T ( __f1 `.expr %` ( string_data o ) ) }
            } {}
            : i x \ ( __pvar m t op )
            ^ @ !String String { T ( __f1 `.var %` ( string_data ( __ns x ) ) ) }
        } {}
        // a struct literal: its fields nested in pairs to the right
        : ( Vec i ) vs ( vec_new [i] )
        : i nw ( __lnw m p r )
        : ~ i j 0
        ~ & < j n < + + off 3 j nw {
            : s o ( __rw m t r off + 3 j )
            ? ( __eq o `c` ) { ( vec_push [i] vs ( __lit_temp t ) ) } {
                : i x \ ( __pvar m t o )
                ( vec_push [i] vs x )
            }
            = j + j 1
        }
        ? < n 2 { ^ @ !String String { F ( __u m p ( string_data ( __f1 `struct of % field(s)` ( string_data ( __ns n ) ) ) ) ) } } {}
        : i nv ( vec_len [i] vs )
        : ~ i acc ( vec_at [i] vs - nv 1 )
        : ~ i q - nv 2
        ~ >= q 1 {
            : i x ( __fresh t )
            ( __pre_add pre x ( string_data ( __f2 `.pair % %` ( string_data ( __ns ( vec_at [i] vs q ) ) ) ( string_data ( __ns acc ) ) ) ) )
            = acc x
            = q - q 1
        }
        ^ @ !String String { T ( __f2 `.pair % %` ( string_data ( __ns ( vec_at [i] vs 0 ) ) ) ( string_data ( __ns acc ) ) ) }
    } {}
    ? ( __eq k `scalar` ) {
        : i n ( __pcount w1 )
        : i nw ( __lnw m p r )
        : ( Vec String ) ops ( vec_new [String] )
        : ~ i j 0
        ~ & < j n < + + off 2 j nw {
            : String o \ ( __operand m t ( __rw m t r off + 2 j ) has_pre pre )
            ( vec_push [String] ops o )
            = j + j 1
        }
        : ~ String e ( string_from `(.lit 0)` )
        : i no ( vec_len [String] ops )
        = j 0
        ~ < j no {
            = e ( __f2 `(.add % %)` ( string_data e ) ( string_data ( vec_at [String] ops j ) ) )
            = j + j 1
        }
        // AGORA-1030: the IR says which numbers a computation reads, not what
        // it computes: any number, its operands still read (`lt e 0` is 0)
        ? == no 0 { ^ @ !String String { T ( string_from `.expr .any` ) } } {}
        ^ @ !String String { T ( __f1 `.expr (.add .any (.lt % (.lit 0)))` ( string_data e ) ) }
    } {}
    ^ @ !String String { F ( __u m p ( string_data ( __f1 `rvalue %` k ) ) ) }
}

@ __argvar TlMod m inout TlSt t s op → !i String {
    ? ( __eq op `c` ) { ^ @ !i String { T ( __lit_temp t ) } } {}
    ^ ( __pvar m t op )
}

// rd: an argument the call only reads: a field (`v3/name`) read through
// the pairs into a temporary of `fpre`, or a whole variable.
@ __rd TlMod m inout TlSt t s op Pre fpre → !i String {
    ? ( __has op `/` ) { ^ ( __field_temp m t op fpre ) } {}
    ^ ( __pvar m t op )
}

// An operand's A2 type where it is read: a field's projected type, or the
// variable's.
@ __rd_ty TlMod m inout TlSt t s op → !String String {
    ? ( __has op `/` ) { ^ ( __flean m t op ) } {}
    ^ ( __vlean m t ( __pint_from op 1 ) )
}

// read: a read of raw text, checked live: a view's length or an owner's.
@ __read TlMod m inout TlSt t s f s op Pre fpre → !String String {
    : i y \ ( __rd m t op fpre )
    : String ty \ ( __rd_ty m t op )
    ? ( __sw ( string_data ty ) `(.slice` ) { ^ @ !String String { T ( __f1 `(.slen %)` ( string_data ( __ns y ) ) ) } } {}
    ? ( __sw ( string_data ty ) `(.vec` ) { ^ @ !String String { T ( __f1 `(.len %)` ( string_data ( __ns y ) ) ) } } {}
    ^ @ !String String { F ( __u m . t p ( string_data ( __f2 `% of a %` f ( string_data ty ) ) ) ) }
}

// (no variable: `x`, `dest` given none; no id can be it, the reader
// bounds them)
@ __nil → i { ^ - -9223372036854775807 1 }

@ __xf inout TlSt t i x → i { ^ ? == x ( __nil ) ( __fresh t ) x }

@ __ok String x → !String String { ^ @ !String String { T x } }

// intrinsic: a standard-library call A2 has a construct for (the call's
// words: statement `r` from `off`), into `x` (`__nil`: none), then `rest`; ""
// when it is none.
@ __intrinsic TlMod m inout TlSt t i r i off s rest i x → !String String {
    : Pre fpre ( __pre_new )
    : String got \ ( __intrinsic_ m t r off rest x fpre )
    ? == 0 ( string_len got ) { ^ @ !String String { T got } } {}
    ^ @ !String String { T ( __wrap fpre ( string_data got ) ) }
}

@ __intrinsic_ TlMod m inout TlSt t i r i off s rest i x0 Pre fpre → !String String {
    : i p . t p
    : s f ( __rw m t r off 1 )
    : i n ( __pcount ( __rw m t r off 2 ) )
    : ~ i x x0
    ? & . m threaded ( __eq f `thread_spawn_owned` ) {
        // A3: a spawn is a call of the closure code's spawn wrapper (A3
        // runs a call of a spawned function as a new thread, the call's
        // temporary set to 0); the closure moves to it (its `sink`
        // parameter), and the result is the ok variant around a handle
        ? != n 1 { ^ @ !String String { F ( __u m p `thread_spawn_owned of other than one closure` ) } } {}
        : s op ( __opw m t r off 3 n 0 )
        ? ! ( __vref op ) { ^ @ !String String { F ( __u m p ( string_data ( __f1 `a spawn of %` op ) ) ) } } {}
        : i id ( __pint_from op 1 )
        : ( Vec i ) sv ( vec_at [( Vec i )] . m sendv p )
        : ~ i q 0
        ~ & < q ( vec_len [i] sv ) != ( vec_at [i] sv q ) id { = q + q 1 }
        ? >= q ( vec_len [i] sv ) { ^ @ !String String { F ( __u m p `a spawned closure whose literal is not in the function` ) } } {}
        : i code ( vec_at [i] ( vec_at [( Vec i )] . m sendc p ) q )
        : ~ i wj 0
        ~ != ( vec_at [i] . m spawned wj ) code { = wj + wj 1 }
        : String vl \ ( __vlean m t id )
        : i sigma \ ( __fn_sigma ( string_data vl ) )
        : i old ( vec_at [i] . t wsig wj )
        ? & >= old 0 != old sigma { ^ @ !String String { F ( __u m p `a closure code spawned at two closure types` ) } } {}
        ( vec_put [i] . t wsig wj sigma )
        : i tt ( __fresh t )
        : i c \ ( __pvar m t op )
        : String w ( __f1 `@W%@` ( string_data ( __ns wj ) ) )
        ? == x ( __nil ) {
            ^ ( __ok ( __f4 `(.letcall % % [%] %)` ( string_data ( __ns tt ) ) ( string_data w ) ( string_data ( __ns c ) ) rest ) )
        } {}
        : i u ( __fresh t )
        : String e \ ( __lean_ty m t `%ThreadErr` )
        : String us ( __ns u )
        : String k2 ( __f4 `(.letv % (.expr (.lit 0)) (.letv % (.inr % %) ` ( string_data us ) ( string_data ( __ns x ) ) ( string_data e ) ( string_data us ) )
        ^ ( __ok ( __f5 `(.letcall % % [%] %%)))` ( string_data ( __ns tt ) ) ( string_data w ) ( string_data ( __ns c ) ) ( string_data k2 ) rest ) )
    } {}
    ? & . m threaded ( __eq f `thread_join` ) {
        // A3: a join reads the handle (an integer) and answers a number
        ? != n 1 { ^ @ !String String { F ( __u m p `thread_join of other than one handle` ) } } {}
        : s op ( __opw m t r off 3 n 0 )
        ? ! ( __vref op ) { ^ @ !String String { F ( __u m p ( string_data ( __f1 `a join of %` op ) ) ) } } {}
        : i y \ ( __pvar m t op )
        : i u ( __fresh t )
        ? == x ( __nil ) {
            ^ ( __ok ( __f3 `(.letv % (.expr (.var %)) %)` ( string_data ( __ns u ) ) ( string_data ( __ns y ) ) rest ) )
        } {}
        ^ ( __ok ( __f4 `(.letv % (.expr (.var %)) (.letv % (.expr .any) %))` ( string_data ( __ns u ) ) ( string_data ( __ns y ) ) ( string_data ( __ns x ) ) rest ) )
    } {}
    ? & & ( __eq f `nurl_println_int` ) == n 1 == x ( __nil ) {
        // it reads a scalar: nothing of memory to check past the read
        ? ( __isc ( __opw m t r off 3 n 0 ) ) { ^ @ !String String { T ( string_from rest ) } } {}
        : i y ( __fresh t )
        : String o \ ( __operand0 m t ( __opw m t r off 3 n 0 ) )
        ^ ( __ok ( __f3 `(.letv % (.expr %) %)` ( string_data ( __ns y ) ) ( string_data o ) rest ) )
    } {}
    ? & & ( __eq f `nurl_println` ) == n 1 == x ( __nil ) {
        // it reads its argument: the read checked live
        ? ( __isc ( __opw m t r off 3 n 0 ) ) { ^ @ !String String { T ( string_from rest ) } } {}
        : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        : String ty \ ( __rd_ty m t ( __opw m t r off 3 n 0 ) )
        : String ys ( __ns y )
        : ~ String e ( __f1 `(.var %)` ( string_data ys ) )
        ? ( __sw ( string_data ty ) `(.slice` ) { = e ( __f1 `(.slen %)` ( string_data ys ) ) } {
            ? ( __sw ( string_data ty ) `(.vec` ) { = e ( __f1 `(.len %)` ( string_data ys ) ) } {}
        }
        : i tt ( __fresh t )
        ^ ( __ok ( __f3 `(.letv % (.expr %) %)` ( string_data ( __ns tt ) ) ( string_data e ) rest ) )
    } {}
    ? & ( __eq f `nurl_str_cat` ) == n 2 {
        // a fresh string from two it reads: each read checked live
        = x ( __xf t x )
        : ~ String st ( __f2 `(.letv % (.new .int) %)` ( string_data ( __ns x ) ) rest )
        : ~ i j 0
        ~ < j 2 {
            : s op ( __rw m t r off + 3 j )
            ? ! ( __eq op `c` ) {
                : i tt ( __fresh t )
                : String e \ ( __read m t f op fpre )
                = st ( __f3 `(.letv % (.expr %) %)` ( string_data ( __ns tt ) ) ( string_data e ) ( string_data st ) )
            } {}
            = j + j 1
        }
        ^ ( __ok st )
    } {}
    ? & & ( __eq f `nurl_str_len` ) == n 1 ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        = x ( __xf t x )
        : String e \ ( __read m t f ( __opw m t r off 3 n 0 ) fpre )
        ^ ( __ok ( __f3 `(.letv % (.expr %) %)` ( string_data ( __ns x ) ) ( string_data e ) rest ) )
    } {}
    ? & ( __eq f `string_from` ) == n 1 {
        // a fresh owned String copied from the text it reads
        = x ( __xf t x )
        : ~ String st ( __f2 `(.letv % (.new .int) %)` ( string_data ( __ns x ) ) rest )
        ? ! ( __isc ( __opw m t r off 3 n 0 ) ) {
            : i tt ( __fresh t )
            : String e \ ( __read m t f ( __opw m t r off 3 n 0 ) fpre )
            = st ( __f3 `(.letv % (.expr %) %)` ( string_data ( __ns tt ) ) ( string_data e ) ( string_data st ) )
        } {}
        ^ ( __ok st )
    } {}
    ? & & ( __eq f `string_data` ) == n 1 ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        = x ( __xf t x )
        : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        ^ ( __ok ( __f3 `(.letv % (.view %) %)` ( string_data ( __ns x ) ) ( string_data ( __ns y ) ) rest ) )
    } {}
    ? & & ( __eq f `string_len` ) == n 1 ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        = x ( __xf t x )
        : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        ^ ( __ok ( __f3 `(.letv % (.expr (.len %)) %)` ( string_data ( __ns x ) ) ( string_data ( __ns y ) ) rest ) )
    } {}
    ? & ( __sw f `vec_new__` ) == n 0 {
        = x ( __xf t x )
        : String el \ ( __vec_elem m t f `vec_new__` )
        ^ ( __ok ( __f3 `(.letv % (.new %) %)` ( string_data ( __ns x ) ) ( string_data el ) rest ) )
    } {}
    ? & & ( __sw f `vec_push__` ) == n 2 == x ( __nil ) {
        : i v \ ( __argvar m t ( __opw m t r off 3 n 0 ) )
        : i y \ ( __argvar m t ( __opw m t r off 3 n 1 ) )
        : String vs ( __ns v )
        : ~ String st ( __seq ( string_data ( __f2 `(.push % %)` ( string_data vs ) ( string_data ( __ns y ) ) ) ) rest )
        : String el \ ( __vec_elem m t f `vec_push__` )
        ? ( __eq ( string_data el ) `(.slice .int)` ) {
            // a raw string pushed where it is held in a value: the Vec keeps
            // a view of it (MEMORY.md §2.13)
            ? ( __eq ( __opw m t r off 3 n 1 ) `c` ) { ^ @ !String String { F ( __u m p `a literal string held in a Vec (no static strings in A2)` ) } } {}
            : String vl \ ( __vlean m t ( __pint_from ( __opw m t r off 3 n 1 ) 1 ) )
            ? ( __eq ( string_data vl ) `(.vec .int)` ) {
                : i tt ( __fresh t )
                : String ts ( __ns tt )
                : String inner ( __seq ( string_data ( __f2 `(.push % %)` ( string_data vs ) ( string_data ts ) ) ) rest )
                = st ( __f3 `(.letv % (.view %) %)` ( string_data ts ) ( string_data ( __ns y ) ) ( string_data inner ) )
            } {}
        } {}
        ^ ( __ok st )
    } {}
    ? & ( __sw f `chan_new__` ) == n 0 {
        // `lockNew` of a fresh queue and a 0 flag (A3.4)
        = x ( __xf t x )
        : i q ( __fresh t )
        : i k ( __fresh t )
        : i pp ( __fresh t )
        : String el \ ( __chan_elem m t ( string_data ( __from f 10 ) ) )
        : String qs ( __ns q )
        : String ks ( __ns k )
        : String ps ( __ns pp )
        : String a ( __f6 `(.letv % (.new %) (.letv % (.expr (.lit 0)) (.letv % (.pair % %) ` ( string_data qs ) ( string_data el ) ( string_data ks ) ( string_data ps ) ( string_data qs ) ( string_data ks ) )
        ^ ( __ok ( __f5 `%(.letv % (.lockNew (.prod (.vec %) .int) %) %))))` ( string_data a ) ( string_data ( __ns x ) ) ( string_data el ) ( string_data ps ) rest ) )
    } {}
    ? & & ( __sw f `Channel_share__` ) == n 1 ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        = x ( __xf t x )
        : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        ^ ( __ok ( __f3 `(.letv % (.lockClone %) %)` ( string_data ( __ns x ) ) ( string_data ( __ns y ) ) rest ) )
    } {}
    ? & & ( __sw f `chan_send__` ) == n 2 ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        // the value moves to the back of the queue, as `vec_push` takes it
        : String _el \ ( __chan_elem m t ( string_data ( __from f 11 ) ) )
        : i y \ ( __argvar m t ( __opw m t r off 3 n 1 ) )
        = x ( __xf t x )
        : i ch \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        ^ ( __ok ( __f4 `(.letv % (.chanSend % %) %)` ( string_data ( __ns x ) ) ( string_data ( __ns ch ) ) ( string_data ( __ns y ) ) rest ) )
    } {}
    ? & & | ( __sw f `chan_recv__` ) ( __sw f `chan_try_recv__` ) == n 1 ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        // the head moves out as `some`, or `none`: an owned `sum int A`
        : s w ? ( __sw f `chan_recv__` ) `true` `false`
        = x ( __xf t x )
        : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        ^ ( __ok ( __f4 `(.letv % (.chanRecv % %) %)` ( string_data ( __ns x ) ) w ( string_data ( __ns y ) ) rest ) )
    } {}
    ? & & ( __sw f `chan_close__` ) == n 1 ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        = x ( __xf t x )
        : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        ^ ( __ok ( __f3 `(.letv % (.chanClose %) %)` ( string_data ( __ns x ) ) ( string_data ( __ns y ) ) rest ) )
    } {}
    ? & & ( __sw f `vec_len__` ) == n 1 ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        = x ( __xf t x )
        : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        ^ ( __ok ( __f3 `(.letv % (.expr (.len %)) %)` ( string_data ( __ns x ) ) ( string_data ( __ns y ) ) rest ) )
    } {}
    ? ( __sw f `slice_from_vec__` ) {
        : String el \ ( __vec_elem m t f `slice_from_vec__` )
        ? ( __has ( string_data el ) `(.slice` ) { ^ @ !String String { F ( __u m p `a slice of a Vec of views` ) } } {}
        ? & == n 1 ! ( __isc ( __opw m t r off 3 n 0 ) ) {
            = x ( __xf t x )
            : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
            ^ ( __ok ( __f3 `(.letv % (.view %) %)` ( string_data ( __ns x ) ) ( string_data ( __ns y ) ) rest ) )
        } {}
    } {}
    ? & | & ( __sw f `vec_clear__` ) == n 1 & ( __sw f `vec_truncate__` ) == n 2 ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        // the callee changes the Vec through the borrow it is handed: its
        // elements past the new length dropped (A2's `edit`, `trunc`)
        : Pre pre ( __pre_new )
        : ~ String i ( string_from `(.lit 0)` )
        ? != n 1 { = i \ ( __operand m t ( __opw m t r off 3 n 1 ) T pre ) } {}
        : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        : String st ( __edit_through t y ( string_data ( __f1 `(.trunc %)` ( string_data i ) ) ) )
        : ~ String rs ( string_from rest )
        ? != x ( __nil ) { = rs ( __f2 `(.letv % (.expr .any) %)` ( string_data ( __ns x ) ) rest ) } {}
        ^ ( __ok ( __wrap pre ( string_data ( __seq ( string_data st ) ( string_data rs ) ) ) ) )
    } {}
    ? & & | & ( __sw f `vec_reserve__` ) == n 2 & ( __sw f `vec_shrink_to_fit__` ) == n 1 == x ( __nil ) ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        // the buffer may move, its length unchanged: a push (which may
        // move it) and a cut back to the length it had, through the borrow
        : s pfx ? ( __sw f `vec_reserve__` ) `vec_reserve__` `vec_shrink_to_fit__`
        : String el \ ( __vec_elem m t f pfx )
        ? ! ( __eq ( string_data el ) `.int` ) {
            ^ @ !String String { F ( __u m p ( string_data ( __f1 `% of a non-scalar element` ( string_data ( __sl pfx 0 -2 ) ) ) ) ) }
        } {}
        : Pre pre ( __pre_new )
        ? == n 2 { : String _o \ ( __operand m t ( __opw m t r off 3 n 1 ) T pre ) } {}
        : i b ( __fresh t )
        : i c ( __lit_temp t )
        : i k ( __fresh t )
        : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        : String bs ( __ns b )
        : String ks ( __ns k )
        : String a ( __f5 `(.letv % (.borrow %) (.letv % (.expr (.len %)) (.seq (.edit true % ` ( string_data bs ) ( string_data ( __ns y ) ) ( string_data ks ) ( string_data bs ) ( string_data bs ) )
        : String st ( __f4 `%(.push %)) (.edit true % (.trunc (.var %))))))` ( string_data a ) ( string_data ( __ns c ) ) ( string_data bs ) ( string_data ks ) )
        ^ ( __ok ( __wrap pre ( string_data ( __seq ( string_data st ) rest ) ) ) )
    } {}
    ? & & & ( __eq f `string_push_str` ) == n 2 == x ( __nil ) ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        // the String it is handed grows through the borrow, and only then
        // are the bytes of the text copied in
        : i c ( __lit_temp t )
        : i y0 \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        : ~ String st ( __edit_through t y0 ( string_data ( __f1 `(.push %)` ( string_data ( __ns c ) ) ) ) )
        ? ! ( __eq ( __opw m t r off 3 n 1 ) `c` ) {
            : i y \ ( __rd m t ( __opw m t r off 3 n 1 ) fpre )
            : String ty \ ( __rd_ty m t ( __opw m t r off 3 n 1 ) )
            : String ys ( __ns y )
            : ~ String e ( string_new )
            ? ( __sw ( string_data ty ) `(.slice` ) { = e ( __f1 `(.slen %)` ( string_data ys ) ) } {
                ? ( __sw ( string_data ty ) `(.vec` ) { = e ( __f1 `(.len %)` ( string_data ys ) ) } {}
            }
            ? == 0 ( string_len e ) { ^ @ !String String { F ( __u m p ( string_data ( __f1 `string_push_str of a %` ( string_data ty ) ) ) ) } } {}
            : i tt ( __fresh t )
            = st ( __f3 `(.seq % (.letv % (.expr %) .skip))` ( string_data st ) ( string_data ( __ns tt ) ) ( string_data e ) )
        } {}
        ^ ( __ok ( __seq ( string_data st ) rest ) )
    } {}
    ? & & & | ( __sw f `vec_free__` ) ( __eq f `string_free` ) == n 1 == x ( __nil ) ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        // a sink that releases what it is handed (A2's `free`)
        : i y \ ( __pvar m t ( __opw m t r off 3 n 0 ) )
        ^ ( __ok ( __seq ( string_data ( __f1 `(.free %)` ( string_data ( __ns y ) ) ) ) rest ) )
    } {}
    ? & & ( __sw f `vec_at__` ) == n 2 ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        // a bounds-checked element read; only a scalar element is translated
        : String el \ ( __vec_elem m t f `vec_at__` )
        ? ! | ( __eq ( string_data el ) `.int` ) ( __eq ( string_data el ) `(.slice .int)` ) {
            ^ @ !String String { F ( __u m p `vec_at of a non-scalar element` ) }
        } {}
        : Pre pre ( __pre_new )
        : String i \ ( __operand m t ( __opw m t r off 3 n 1 ) T pre )
        ? == x ( __nil ) {
            : i tt ( __fresh t )
            : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
            : String a ( __f3 `(.letv % (.at % %) .skip)` ( string_data ( __ns tt ) ) ( string_data ( __ns y ) ) ( string_data i ) )
            ^ ( __ok ( __wrap pre ( string_data ( __seq ( string_data a ) rest ) ) ) )
        } {}
        : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        ^ ( __ok ( __wrap pre ( string_data ( __f4 `(.letv % (.at % %) %)` ( string_data ( __ns x ) ) ( string_data ( __ns y ) ) ( string_data i ) rest ) ) ) )
    } {}
    ? & & ( __sw f `slice_len__` ) == n 1 ! ( __isc ( __opw m t r off 3 n 0 ) ) {
        = x ( __xf t x )
        : i y \ ( __rd m t ( __opw m t r off 3 n 0 ) fpre )
        ^ ( __ok ( __f3 `(.letv % (.expr (.slen %)) %)` ( string_data ( __ns x ) ) ( string_data ( __ns y ) ) rest ) )
    } {}
    ^ @ !String String { T ( string_new ) }
}

// call: `call f n op…` into `x` (a fresh temporary if `__nil`), then `rest`.
@ __call TlMod m inout TlSt t i r i off s rest i x0 → !String String {
    : i p . t p
    : s f ( __rw m t r off 1 )
    : i n ( __pcount ( __rw m t r off 2 ) )
    : String got \ ( __intrinsic m t r off rest ( __nil ) )
    ? > ( string_len got ) 0 { ^ @ !String String { T got } } {}
    : i fi ( __mget . m names f )
    ? < fi 0 { ^ @ !String String { F ( __u m p ( string_data ( __f1 `call of %, not in the program` f ) ) ) } } {}
    : String args ( string_new )
    : ( Vec i ) texts ( vec_new [i] )
    : i nw ( __lnw m p r )
    : ~ i j 0
    ~ & < j n < + + off 3 j nw {
        : s op ( __rw m t r off + 3 j )
        ? ( __vref op ) {
            : b clo \ ( __is_clo ( __vtyd m p ( __pint_from op 1 ) `` ) )
            ? & clo != 0 & ( __vflags m fi j ) 6 {
                // nurlc copies a closure it hands to a `sink` / `inout`
                // parameter (`nurl_closure_clone`), which the IR does not show
                ^ @ !String String { F ( __u m p ( string_data ( __f1 `a closure handed to a sink or inout parameter of %` f ) ) ) }
            } {}
        } {}
        : ~ i a -1
        ? & ( __eq op `c` ) ( __eq ( __vtyd m fi j `` ) `i8*` ) {
            // AGORA-994: a literal handed to a raw-string parameter is text,
            // a buffer of its own, here the call's
            = a ( __fresh t )
            ( vec_push [i] texts a )
        } {
            ? ( __eq op `c` ) { = a ( __lit_temp t ) } {
                ? ( __has op `/` ) { ^ @ !String String { F ( __u m p ( string_data ( __f1 `a field as an argument (%)` op ) ) ) } } {}
                = a \ ( __pvar m t op )
            }
        }
        ? > j 0 { ( string_push_str args `, ` ) } {}
        ( string_push_int args a )
        = j + j 1
    }
    : i x ( __xf t x0 )
    : ~ String st ( __f4 `(.letcall % % [%] %)` ( string_data ( __ns x ) ) ( string_data ( __ns fi ) ) ( string_data args ) rest )
    : ~ i q - ( vec_len [i] texts ) 1
    ~ >= q 0 {
        = st ( __f2 `(.letv % (.new .int) %)` ( string_data ( __ns ( vec_at [i] texts q ) ) ) ( string_data st ) )
        = q - q 1
    }
    ^ @ !String String { T st }
}

// callind: `callind n c args…`: method 0 of the package `c`, of its
// type's interface (A2's `callc`).
@ __callind TlMod m inout TlSt t i r i off s rest i x0 → !String String {
    : i p . t p
    : i n ( __pcount ( __rw m t r off 1 ) )
    : s c0 ( __opw m t r off 2 n 0 )
    ? | ( __eq c0 `c` ) ( __has c0 `/` ) { ^ @ !String String { F ( __u m p ( string_data ( __f1 `a call through %` c0 ) ) ) } } {}
    : i c \ ( __pvar m t c0 )
    : String vl \ ( __vlean m t ( __pint_from c0 1 ) )
    : i sigma \ ( __fn_sigma ( string_data vl ) )
    : String zs ( string_new )
    : i nw ( __lnw m p r )
    : ~ i j 1
    ~ & < j n < + + off 2 j nw {
        : s op ( __rw m t r off + 2 j )
        : ~ i a -1
        ? ( __eq op `c` ) { = a ( __lit_temp t ) } {
            ? ( __has op `/` ) { ^ @ !String String { F ( __u m p ( string_data ( __f1 `a field as an argument (%)` op ) ) ) } } {}
            = a \ ( __pvar m t op )
        }
        ? > j 1 { ( string_push_str zs `, ` ) } {}
        ( string_push_int zs a )
        = j + j 1
    }
    : i x ( __xf t x0 )
    ^ @ !String String { T ( __f5 `(.callc % % 0 % [%] %)` ( string_data ( __ns x ) ) ( string_data ( __ns c ) ) ( string_data ( __ns sigma ) ) ( string_data zs ) rest ) }
}

// closure_lit: `closure __closure_N n caps…`: its environment, the
// captured numbers (and the buffers it owns) copied into one value
// (`env_ty`), packed with the code and its type's interface (A2's
// `pack`), the other captures by name. The bindings it needs go to `pre`.
@ __closure_lit TlMod m inout TlSt t i r i off i xv Pre pre → !String String {
    : i p . t p
    : s f ( __rw m t r off 1 )
    : i n ( __pcount ( __rw m t r off 2 ) )
    : i q ( __mget . m names f )
    ? < q 0 { ^ @ !String String { F ( __u m p ( string_data ( __f1 `closure %, not in the program` f ) ) ) } } {}
    : ( Vec String ) caps0 ( vec_new [String] )
    : i nw ( __lnw m p r )
    : ~ i j 0
    ~ & < j n < + + off 3 j nw {
        ( vec_push [String] caps0 ( string_from ( __rw m t r off + 3 j ) ) )
        = j + j 1
    }
    : i nc0 ( vec_len [String] caps0 )
    = j 0
    ~ < j nc0 {
        : s c ( string_data ( vec_at [String] caps0 j ) )
        ? | | ( __eq c `c` ) ( __has c `/` ) ! ( __vref c ) { ^ @ !String String { F ( __u m p `a capture that is not a variable` ) } } {}
        = j + j 1
    }
    // (the literal's captures in the code's order: numbers, and buffers
    // the environment owns (AGORA-978) or every literal moves in by value
    // (AGORA-994), by value into the environment, the other buffers by name)
    : ( Vec i ) ids ( __ids_sorted m q )
    : ( Vec i ) ck_all ( vec_new [i] )
    : i ni ( vec_len [i] ids )
    = j 0
    ~ < j ni {
        ? == ( __vkind m q ( vec_at [i] ids j ) ) 3 { ( vec_push [i] ck_all ( vec_at [i] ids j ) ) } {}
        = j + j 1
    }
    : i nck ( vec_len [i] ck_all )
    ? != nck nc0 { ^ @ !String String { F ( __u m p ( string_data ( __f1 `closure %'s captures` f ) ) ) } } {}
    : ( Vec String ) named ( vec_new [String] )
    : ( Vec i ) ck ( vec_new [i] )
    : ( Vec String ) caps ( vec_new [String] )
    = j 0
    ~ < j nck {
        : i k ( vec_at [i] ck_all j )
        : ~ b keep \ ( __named_cap m t q k )
        ? keep { = keep ! ( __is_moved m q j ) } {}
        ? keep {
            ( vec_push [String] named ( string_clone ( vec_at [String] caps0 j ) ) )
            ( vec_push [i] ck k )
        } {
            ( vec_push [String] caps ( string_clone ( vec_at [String] caps0 j ) ) )
        }
        = j + j 1
    }
    ? & & . m threaded ( __in . m spawned q ) > ( vec_len [String] named ) 0 {
        ^ @ !String String { F ( __u m p ( string_data ( __f1 `a spawned closure capturing % by name` ( string_data ( vec_at [String] named 0 ) ) ) ) ) }
    } {}
    : i nc ( vec_len [String] caps )
    : ( Vec String ) tys ( vec_new [String] )
    = j 0
    ~ < j nc {
        : String ct \ ( __cap_ty m t q ( __vty m p ( __pint_from ( string_data ( vec_at [String] caps j ) ) 1 ) ) )
        ( vec_push [String] tys ct )
        = j + j 1
    }
    : String cs ( string_new )
    : i nn ( vec_len [String] named )
    = j 0
    ~ < j nn {
        : s c ( string_data ( vec_at [String] named j ) )
        : i v \ ( __pvar m t c )
        : String md \ ( __cap_mode m t q ( vec_at [i] ck j ) )
        : String vl \ ( __vlean m t ( __pint_from c 1 ) )
        ? > j 0 { ( string_push_str cs `, ` ) } {}
        ( string_push_str cs ( string_data ( __f3 `(%, %, %)` ( string_data ( __ns v ) ) ( string_data md ) ( string_data vl ) ) ) )
        = j + j 1
    }
    : String xl \ ( __vlean m t xv )
    : i sigma \ ( __fn_sigma ( string_data xl ) )
    : ( Vec i ) vals ( vec_new [i] )
    = j 0
    ~ < j nc {
        : i v \ ( __pvar m t ( string_data ( vec_at [String] caps j ) ) )
        ( vec_push [i] vals v )
        = j + j 1
    }
    : ~ i y 0
    ? == nc 0 {
        = y ( __fresh t )
        ( __pre_add pre y `.expr (.lit 0)` )
    } {
        ? == nc 1 { = y ( vec_at [i] vals 0 ) } {
            : ~ i acc ( vec_at [i] vals - nc 1 )
            : ~ i k - nc 2
            ~ >= k 0 {
                : i tt ( __fresh t )
                ( __pre_add pre tt ( string_data ( __f2 `.pair % %` ( string_data ( __ns ( vec_at [i] vals k ) ) ) ( string_data ( __ns acc ) ) ) ) )
                = acc tt
                = k - k 1
            }
            = y acc
        }
    }
    : String env ( __env_ty tys )
    ^ @ !String String { T ( __f5 `.pack [%] % [%] % [%]` ( string_data ( __ns q ) ) ( string_data env ) ( string_data ( __ns sigma ) )
        ( string_data ( __ns y ) ) ( string_data cs ) ) }
}

// block_of: the statements from ls[i0] to the matching `end` / `else` /
// `arm` at depth 0: the index of that closing statement (or b).
@ __block_of TlMod m i p ( Vec i ) ls i i0 i b → i {
    : ~ i depth 0
    : ~ i i i0
    ~ < i b {
        : s w ( __lw m p ( vec_at [i] ls i ) 0 )
        ? & == depth 0 | | ( __eq w `end` ) ( __eq w `else` ) ( __eq w `arm` ) { ^ i } {}
        ? ( __opener w ) { = depth + depth 1 } { ? ( __eq w `end` ) { = depth - depth 1 } {} }
        = i + i 1
    }
    ^ i
}

@ __ls_word TlMod m i p ( Vec i ) ls i k i lim i j → s {
    ? >= k lim { ( panic `internal: a block the core IR does not close` ) } {}
    ^ ( __lw m p ( vec_at [i] ls k ) j )
}

// stmts: the statements ls[a, b) as one A2 statement, ending in `tail`:
// each binding scoped over what follows it. AGORA-1030: the temporaries
// that hold the untracked numbers the statement at `a` consumes
// (`__lit_temp`: a call's `c` argument, a literal's `c` field, …) are
// bound around that statement's term, `(.letv q (.expr .any) …)`, so each
// time the statement runs (each round of a loop around it) they are any
// number again. (The term of `a` holds the rest of the list, whose own
// temporaries its own call binds, inside: the temporaries left at the end
// of t.lits past where it stood on entry are exactly those of `a`.)
@ __stmts TlMod m inout TlSt t ( Vec i ) ls i a i b s tail → !String String {
    : i n0 ( vec_len [i] . t lits )
    : ~ String st \ ( __stmts_ m t ls a b tail )
    : ~ i q - ( vec_len [i] . t lits ) 1
    ~ >= q n0 {
        = st ( __f2 `(.letv % (.expr .any) %)` ( string_data ( __ns ( vec_at [i] . t lits q ) ) ) ( string_data st ) )
        : ?i _o ( vec_pop [i] . t lits )
        = q - q 1
    }
    ^ @ !String String { T st }
}

@ __stmts_ TlMod m inout TlSt t ( Vec i ) ls i a i b s tail → !String String {
    ? >= a b { ^ @ !String String { T ( string_from tail ) } } {}
    : i p . t p
    // the last statement that is not a `line` or a `drop`
    : ~ i e - b 1
    ~ >= e a {
        : s w0 ( __ls_word m p ls e b 0 )
        ? & ! ( __eq w0 `line` ) ! ( __eq w0 `drop` ) { break } {}
        = e - e 1
    }
    ? & >= e a ( __eq ( __ls_word m p ls e b 0 ) `ret` ) {
        // A list ending in `ret` leaves the function from inside every
        // binding made before it. The exit is put after them: ending their
        // scopes and then leaving is what leaving from inside them does,
        // and an exit at the end of a sequence is one a branch around it
        // may end elsewhere (`checkX`'s tail).
        : ( Vec i ) body ( vec_new [i] )
        : ~ i k a
        ~ < k e { ( vec_push [i] body ( vec_at [i] ls k ) ) = k + k 1 }
        ( vec_push [i] body - -1 ( vec_at [i] ls e ) )
        : String inner \ ( __stmts m t body 0 ( vec_len [i] body ) `.skip` )
        : String ex ( __f1 `(.exit %)` ( string_data ( __ns . t depth ) ) )
        ^ ( __ok ( __seq ( string_data inner ) ( string_data ex ) ) )
    } {}
    : i r0 ( vec_at [i] ls a )
    : s w ( __lw m p r0 0 )
    : s h1 ( __lws m p r0 1 )
    : s h2 ( __lws m p r0 2 )
    ? ( __eq w `drop` ) {
        // a temporary's statement ended: it is released here, which the
        // translation leaves to the end of its scope. That is the same only
        // if nothing reads it, or a view of it, afterwards (everything
        // after the drop in the function, not only the rest of its own
        // list: github#2242's review)
        ( __need m p r0 2 )
        : i k ( __pint h1 )
        : String lt \ ( __lean_ty m t ( __vtyd m p k `i64` ) )
        ? | ! ( __eq ( string_data lt ) `.int` ) & ( __vhas m p k ) ( __eq ( __vtyd m p k `` ) `i8*` ) {
            : ( Vec i ) dead ( __views_of m t k )
            ? < r0 0 { ^ @ !String String { F ( __u m p `a drop whose place in the body is unknown` ) } } {}
            : i nl ( __nl m p )
            : i nd ( vec_len [i] dead )
            : ~ i l + r0 1
            ~ < l nl {
                // the line's tokens, split at whitespace and `/`
                : i nw ( __nw m p l )
                : ~ i q 0
                ~ < q nw {
                    : String wq ( string_from ( __wd m p l q ) )
                    : ( Slice u ) tq ( slice_of_str ( string_data wq ) )
                    : i nq ( slice_len [u] tq )
                    : ~ i x 0
                    ~ < x nq {
                        : ~ i z x
                        ~ & < z nq != ( slice_byte tq z ) 47 { = z + z 1 }
                        ? < x z {
                            : String tok ( string_new )
                            ( string_push_window tok tq x - z x )
                            : ~ i d 0
                            ~ < d nd {
                                ? ( __is_v ( string_data tok ) ( vec_at [i] dead d ) ) {
                                    ^ @ !String String { F ( __u m p `a temporary, or a view of it, read after its drop` ) }
                                } {}
                                = d + d 1
                            }
                        } {}
                        = x + z 1
                    }
                    = q + q 1
                }
                = l + l 1
            }
        } {}
        ^ ( __stmts m t ls + a 1 b tail )
    } {}
    ? ( __eq w `line` ) { ^ ( __stmts m t ls + a 1 b tail ) } {}
    ? ( __eq w `scope` ) {
        : i j ( __block_of m p ls + a 1 b )
        : String x \ ( __stmts m t ls + a 1 j `.skip` )
        : String y \ ( __stmts m t ls + j 1 b tail )
        ^ ( __ok ( __seq ( string_data x ) ( string_data y ) ) )
    } {}
    ? ( __eq w `loop` ) {
        // `loop <condition> loopcond op <body> end`: a block around A2's
        // `loop`, whose body runs the condition and leaves the block
        // (`exit 0`) when it is false; `break` leaves it too, and a `ret`
        // leaves it and every block around it.
        : ~ i depth 0
        : ~ i j + a 1
        ~ < j b {
            : s ww ( __ls_word m p ls j b 0 )
            ? & == depth 0 ( __eq ww `loopcond` ) { break } {}
            ? ( __opener ww ) { = depth + depth 1 } { ? ( __eq ww `end` ) { = depth - depth 1 } {} }
            = j + j 1
        }
        : s c ( __ls_word m p ls j b 1 )
        : i k ( __block_of m p ls + j 1 b )
        // (the body is a block of its own: `continue` leaves it, `exit 0`,
        // and `break` leaves it and the loop's, `exit 1`)
        = . t depth + . t depth 2
        : String inner_body \ ( __stmts m t ls + j 1 k `.skip` )
        = . t depth - . t depth 1
        : ~ String inner ( string_new )
        ? | ( __eq c `T` ) ( __eq c `1` ) {
            // `~ T { … }`: no condition, the body block alone
            = inner ( __f1 `(.block %)` ( string_data inner_body ) )
        } {
            : String o \ ( __operand0 m t c )
            = inner ( __f2 `(.ite % (.block %) (.exit 0))` ( string_data o ) ( string_data inner_body ) )
        }
        : String loop_body \ ( __stmts m t ls + a 1 j ( string_data inner ) )
        = . t depth - . t depth 1
        : String rest \ ( __stmts m t ls + k 1 b tail )
        ^ ( __ok ( __seq ( string_data ( __f1 `(.block (.loop %))` ( string_data loop_body ) ) ) ( string_data rest ) ) )
    } {}
    ? ( __eq w `foreach` ) {
        // `foreach x v … end` over a Vec: the loop holds a borrow of the
        // container for its whole run (a view of it), and lends each
        // element through it (`sat`); an index counts up, stepped before
        // the body so `continue` keeps it; the blocks as `loop`'s
        : i k ( __block_of m p ls + a 1 b )
        ( __need m p r0 3 )
        : s xs h2
        : i xid ? ( __isdig_from xs 1 ) ( __pint_from xs 1 ) -1
        ? ! ( __sw ( __vtyd m p xid `` ) `%Vec__` ) { ^ @ !String String { F ( __u m p ( string_data ( __f1 `foreach over %` xs ) ) ) } } {}
        : String lt \ ( __lean_ty m t ( __vty m p xid ) )
        ? ( __has ( string_data lt ) `(.slice` ) { ^ @ !String String { F ( __u m p `foreach over a Vec of views` ) } } {}
        : i v \ ( __pvar m t xs )
        : i x ( __var t ( __pint h1 ) )
        : i i ( __fresh t )
        : i wv ( __fresh t )
        ( vec_push [i] . t elems x )
        = . t depth + . t depth 2
        : String inner \ ( __stmts m t ls + a 1 k `.skip` )
        = . t depth - . t depth 2
        : String is ( __ns i )
        : String ws ( __ns wv )
        : String step ( __f2 `(.assign % (.expr (.add (.var %) (.lit 1))))` ( string_data is ) ( string_data is ) )
        : String each ( __f5 `(.letv % (.sat % (.var %)) (.seq % %))` ( string_data ( __ns x ) ) ( string_data ws ) ( string_data is ) ( string_data step ) ( string_data inner ) )
        : String lp ( __f4 `(.loop (.ite (.lt (.var %) (.slen %)) (.block %) (.exit 0)))` ( string_data is ) ( string_data ws ) ( string_data each ) `` )
        : String blk ( __f5 `(.block (.letv % (.expr (.lit 0)) (.letv % (.view %) %)))` ( string_data is ) ( string_data ws ) ( string_data ( __ns v ) ) ( string_data lp ) `` )
        : String rest \ ( __stmts m t ls + k 1 b tail )
        ^ ( __ok ( __seq ( string_data blk ) ( string_data rest ) ) )
    } {}
    ? ( __eq w `break` ) {
        : String rest \ ( __stmts m t ls + a 1 b tail )
        ^ ( __ok ( __seq `(.exit 1)` ( string_data rest ) ) )
    } {}
    ? ( __eq w `continue` ) {
        : String rest \ ( __stmts m t ls + a 1 b tail )
        ^ ( __ok ( __seq `(.exit 0)` ( string_data rest ) ) )
    } {}
    ? ( __eq w `match` ) {
        // an option's match: `isl` is 1 for its first variant, None (`F`)
        : ( Vec String ) arms ( vec_new [String] )
        : ( Vec i ) arm_a ( vec_new [i] )
        : ( Vec i ) arm_b ( vec_new [i] )
        : ~ i j + a 1
        ~ & < j b ( __eq ( __ls_word m p ls j b 0 ) `arm` ) {
            : i k ( __block_of m p ls + j 1 b )
            : s an ( __ls_word m p ls j b 1 )
            : ~ i q 0
            : i na ( vec_len [String] arms )
            ~ & < q na ! ( __eq ( string_data ( vec_at [String] arms q ) ) an ) { = q + q 1 }
            ? < q na {
                ( vec_put [i] arm_a q + j 1 )
                ( vec_put [i] arm_b q k )
            } {
                ( vec_push [String] arms ( string_from an ) )
                ( vec_push [i] arm_a + j 1 )
                ( vec_push [i] arm_b k )
            }
            = j k
        }
        : i na ( vec_len [String] arms )
        ? | != na 2 | ! ( __sin arms `T` ) ! ( __sin arms `F` ) {
            // `sorted(arms)`, as Python prints a list of strings
            : ( Vec String ) srt ( vec_new [String] )
            : ~ i q 0
            ~ < q na {
                : s an ( string_data ( vec_at [String] arms q ) )
                : ~ i z ( vec_len [String] srt )
                ( vec_push [String] srt ( string_from an ) )
                ~ & > z 0 > ( nurl_str_cmp ( string_data ( vec_at [String] srt - z 1 ) ) an ) 0 {
                    ( vec_put [String] srt z ( string_clone ( vec_at [String] srt - z 1 ) ) )
                    = z - z 1
                }
                ( vec_put [String] srt z ( string_from an ) )
                = q + q 1
            }
            : String lst ( string_from `[` )
            = q 0
            ~ < q na {
                ? > q 0 { ( string_push_str lst `, ` ) } {}
                ( string_push_str lst `'` )
                ( string_push_str lst ( string_data ( vec_at [String] srt q ) ) )
                ( string_push_str lst `'` )
                = q + q 1
            }
            ( string_push_str lst `]` )
            ^ @ !String String { F ( __u m p ( string_data ( __f1 `match arms %` ( string_data lst ) ) ) ) }
        } {}
        : ~ i iT 0
        ? ! ( __eq ( string_data ( vec_at [String] arms 0 ) ) `T` ) { = iT 1 } {}
        : i iF - 1 iT
        ( __need m p r0 2 )
        : i mv \ ( __pvar m t h1 )
        : String sf \ ( __stmts m t ls ( vec_at [i] arm_a iF ) ( vec_at [i] arm_b iF ) `.skip` )
        : String st \ ( __stmts m t ls ( vec_at [i] arm_a iT ) ( vec_at [i] arm_b iT ) `.skip` )
        : String ite ( __f3 `(.ite (.isl %) % %)` ( string_data ( __ns mv ) ) ( string_data sf ) ( string_data st ) )
        : String rest \ ( __stmts m t ls + j 1 b tail )
        ^ ( __ok ( __seq ( string_data ite ) ( string_data rest ) ) )
    } {}
    ? ( __eq w `if` ) {
        : i j ( __block_of m p ls + a 1 b )
        : ~ i k j
        : ~ i bb j
        : ~ i ba j
        ? ( __eq ( __ls_word m p ls j b 0 ) `else` ) {
            = ba + j 1
            = k ( __block_of m p ls + j 1 b )
            = bb k
        } {}
        ( __need m p r0 2 )
        : String c \ ( __operand0 m t h1 )
        : String sa \ ( __stmts m t ls + a 1 j `.skip` )
        : String sb \ ( __stmts m t ls ba bb `.skip` )
        : String ite ( __f3 `(.ite % % %)` ( string_data c ) ( string_data sa ) ( string_data sb ) )
        : String rest \ ( __stmts m t ls + k 1 b tail )
        ^ ( __ok ( __seq ( string_data ite ) ( string_data rest ) ) )
    } {}
    ? | ( __eq w `ret` ) ( __eq w `retnx` ) {
        // (`retnx`: the result set, its exit placed after the list, above)
        ( __need m p r0 2 )
        : String rs ( __ns . t rslot )
        : ~ String asg ( string_new )
        : ~ b int_ F
        ? & ! ( __eq h1 `c` ) ! ( __eq h1 `-` ) { = int_ \ ( __is_int m t h1 ) } {}
        ? & ( __eq h1 `c` ) ( __eq ( string_data . t res_ty ) `(.slice .int)` ) {
            // AGORA-980: a literal handed back as a view is a static
            // block's text (`Rhs.slit`)
            = asg ( __f1 `(.assign % (.slit 0))` ( string_data rs ) )
        } {
            ? & & ! ( __eq h1 `-` ) ! ( __eq h1 `c` ) ! int_ {
                : i v \ ( __pvar m t h1 )
                = asg ( __f2 `(.assign % (.var %))` ( string_data rs ) ( string_data ( __ns v ) ) )
            } {
                : ~ String v ( string_from `(.lit 0)` )
                ? ! ( __eq h1 `-` ) { = v \ ( __operand0 m t h1 ) } {}
                = asg ( __f2 `(.assign % (.expr %))` ( string_data rs ) ( string_data v ) )
            }
        }
        : ~ String ex ( string_new )
        ? ( __eq w `retnx` ) { = ex asg } {
            = ex ( __f2 `(.seq % (.exit %))` ( string_data asg ) ( string_data ( __ns . t depth ) ) )
        }
        : String rest \ ( __stmts m t ls + a 1 b tail )
        ^ ( __ok ( __seq ( string_data ex ) ( string_data rest ) ) )
    } {}
    ? ( __eq w `let` ) { ( __need m p r0 3 ) } {}
    ? & ( __eq w `let` ) ! | | ( __eq h2 `call` ) ( __eq h2 `closure` ) ( __eq h2 `callind` ) {
        // `let x r` whose value is returned at once: the result takes `r`
        : ~ i q + a 1
        ~ & < q b | ( __eq ( __ls_word m p ls q b 0 ) `line` ) ( __eq ( __ls_word m p ls q b 0 ) `drop` ) { = q + q 1 }
        ? < q b {
            : i rq ( vec_at [i] ls q )
            : String want ( __f1 `v%` h1 )
            ? & & == ( __lnw m p rq ) 2 ( __eq ( __lw m p rq 0 ) `ret` ) & ( __eq ( __lw m p rq 1 ) ( string_data want ) ) ! ( __is_dtor m ( __vtyd m p ( __pint h1 ) `` ) ) {
                : Pre pre ( __pre_new )
                : String rv \ ( __rhs m t r0 2 ( __pint h1 ) T pre F )
                : String inner ( __f3 `(.seq (.assign % (%)) (.exit %))` ( string_data ( __ns . t rslot ) ) ( string_data rv ) ( string_data ( __ns . t depth ) ) )
                : String ex ( __wrap pre ( string_data inner ) )
                : String rest \ ( __stmts m t ls + q 1 b tail )
                ^ ( __ok ( __seq ( string_data ex ) ( string_data rest ) ) )
            } {}
        } {}
    } {}
    ? & ( __eq w `let` ) ( __eq h2 `closure` ) {
        : i x ( __var t ( __pint h1 ) )
        : String rest \ ( __stmts m t ls + a 1 b tail )
        : Pre pre ( __pre_new )
        : String rv \ ( __closure_lit m t r0 2 ( __pint h1 ) pre )
        ^ ( __ok ( __wrap pre ( string_data ( __f3 `(.letv % (%) %)` ( string_data ( __ns x ) ) ( string_data rv ) ( string_data rest ) ) ) ) )
    } {}
    ? & & | ( __eq w `let` ) ( __eq w `assign` ) > ( __lnw m p r0 ) 3 & ( __eq h2 `use` ) ( __vref ( __lw m p r0 3 ) ) {
        : i y ( __pint_from ( __lw m p r0 3 ) 1 )
        : b clo \ ( __is_clo ( __vtyd m p y `` ) )
        ? & clo | ( __eq w `assign` ) != ( __vkind m p y ) 2 {
            // a closure moves only from the temporary its literal made into
            // its binding; given another binding, nurlc copies it, unseen here
            ^ @ !String String { F ( __u m p `a closure bound from another binding` ) }
        } {}
    } {}
    ? & ( __eq w `let` ) ( __eq h2 `callind` ) {
        : i x ( __var t ( __pint h1 ) )
        : String rest \ ( __stmts m t ls + a 1 b tail )
        ^ ( __callind m t r0 2 ( string_data rest ) x )
    } {}
    ? ( __eq w `let` ) {
        : i x ( __var t ( __pint h1 ) )
        : String rest \ ( __stmts m t ls + a 1 b tail )
        : b d ( __is_dtor m ( __vtyd m p ( __pint h1 ) `` ) )
        ? ( __eq h2 `call` ) {
            ? d {
                // a call's owned destructor value goes to its `letd` first
                // thing in A2 (A2-drop.3a), not translated yet
                ^ @ !String String { F ( __u m p `a destructor value a call hands back` ) }
            } {}
            : String got \ ( __intrinsic m t r0 2 ( string_data rest ) x )
            ? > ( string_len got ) 0 { ^ @ !String String { T got } } {}
            ^ ( __call m t r0 2 ( string_data rest ) x )
        } {}
        : Pre pre ( __pre_new )
        : String rv \ ( __rhs m t r0 2 ( __pint h1 ) T pre F )
        ? d {
            // a value of a destructor type: a `letd` binding, whose scope's
            // end runs the destructor on it (the IR's `drop` lines are that end)
            : String _u \ ( __dtor_of m t ( __vty m p ( __pint h1 ) ) )
            : i f ( __dtor_f m ( __vty m p ( __pint h1 ) ) )
            ^ ( __ok ( __wrap pre ( string_data ( __f4 `(.letd % % (%) %)` ( string_data ( __ns x ) ) ( string_data ( __ns f ) ) ( string_data rv ) ( string_data rest ) ) ) ) )
        } {}
        ^ ( __ok ( __wrap pre ( string_data ( __f3 `(.letv % (%) %)` ( string_data ( __ns x ) ) ( string_data rv ) ( string_data rest ) ) ) ) )
    } {}
    ? ( __eq w `eval` ) {
        : String rest \ ( __stmts m t ls + a 1 b tail )
        ( __need m p r0 2 )
        ? ( __eq h1 `call` ) { ^ ( __call m t r0 1 ( string_data rest ) ( __nil ) ) } {}
        ? ( __eq h1 `callind` ) { ^ ( __callind m t r0 1 ( string_data rest ) ( __nil ) ) } {}
        : i x ( __fresh t )
        : Pre pre ( __pre_new )
        : String rv \ ( __rhs m t r0 1 ( __nil ) T pre F )
        ^ ( __ok ( __wrap pre ( string_data ( __f3 `(.letv % (%) %)` ( string_data ( __ns x ) ) ( string_data rv ) ( string_data rest ) ) ) ) )
    } {}
    ? ( __eq w `assign` ) {
        ( __need m p r0 2 )
        ? ! ( __vref h1 ) { ^ @ !String String { F ( __u m p ( string_data ( __f1 `store to %` h1 ) ) ) } } {}
        : i y ( __pint_from h1 1 )
        ? & ( __vhas m p y ) ( __eq ( __vtyd m p y `` ) `void` ) {
            // a join's value that no one takes (a `void` holder): nothing moves
            ^ ( __stmts m t ls + a 1 b tail )
        } {}
        ? ( __is_dtor m ( __vtyd m p y `` ) ) {
            // a destructor binding is given no other value (A2's `letd`)
            ^ @ !String String { F ( __u m p `a destructor binding assigned` ) }
        } {}
        : Pre pre ( __pre_new )
        : String rv \ ( __rhs m t r0 2 y T pre T )
        : i x \ ( __pvar m t h1 )
        : String a1 ( __wrap pre ( string_data ( __f2 `(.assign % (%))` ( string_data ( __ns x ) ) ( string_data rv ) ) ) )
        : String rest \ ( __stmts m t ls + a 1 b tail )
        ^ ( __ok ( __seq ( string_data a1 ) ( string_data rest ) ) )
    } {}
    ^ @ !String String { F ( __u m p ( string_data ( __f1 `statement %` w ) ) ) }
}

// read_caps: a closure's captures read out of its environment (variable
// 0, lent) at the top of its body: one is the environment, more are its
// pairs' fields. A number is copied; a buffer is lent from it.
@ __take TlMod m inout TlSt t i c i src → !String String {
    : String ct \ ( __cap_ty m t . t p ( __vty m . t p c ) )
    ? ( __eq ( string_data ct ) `.int` ) { ^ ( __ok ( __f1 `.expr (.var %)` ( string_data ( __ns src ) ) ) ) } {}
    ^ ( __ok ( __f1 `.var %` ( string_data ( __ns src ) ) ) )
}

@ __read_caps TlMod m inout TlSt t s inner → !String String {
    : ( Vec i ) caps ( vec_clone [i] . t caps )
    : i n ( vec_len [i] caps )
    ? == n 0 { ^ @ !String String { T ( string_from inner ) } } {}
    ? == n 1 {
        : String tk \ ( __take m t ( vec_at [i] caps 0 ) 0 )
        ^ ( __ok ( __f3 `(.letv % (%) %)` ( string_data ( __ns ( __var t ( vec_at [i] caps 0 ) ) ) ) ( string_data tk ) inner ) )
    } {}
    : Pre binds ( __pre_new )
    : ~ i cur 0
    : ~ i k 0
    ~ < k n {
        : i c ( vec_at [i] caps k )
        ? < k - n 1 {
            ( __pre_add binds ( __var t c ) ( string_data ( __f1 `.fst %` ( string_data ( __ns cur ) ) ) ) )
            : i x ( __fresh t )
            ( __pre_add binds x ( string_data ( __f1 `.snd %` ( string_data ( __ns cur ) ) ) ) )
            = cur x
        } {
            : String tk \ ( __take m t c cur )
            ( __pre_add binds ( __var t c ) ( string_data tk ) )
        }
        = k + k 1
    }
    ^ ( __ok ( __wrap binds inner ) )
}

// Where statement l's rvalue starts (`let v r`, `assign p r`: 2; `eval
// r`: 1), or -1 for a statement with none.
@ __wf_rv TlMod m i p i l → i {
    : s w ( __wd m p l 0 )
    ? | ( __eq w `let` ) ( __eq w `assign` ) { ^ 2 } {}
    ? ( __eq w `eval` ) { ^ 1 } {}
    ^ -1
}

@ __wf_bad TlMod m i p s kind i l s what → !v String {
    : String o ( string_from `internal: malformed ` )
    ( string_push_str o kind )
    ( string_push_str o `: ` )
    ( string_push_str o ( __name m p ) )
    ( string_push_str o `, statement ` )
    ( string_push_int o + l 1 )
    ( string_push_str o `: ` )
    ( string_push_str o what )
    ^ @ !v String { F o }
}

// The function's body is well formed where tolean.py does not check it
// (the deviations above): every block closed by its `end`, each closer in
// its block, and no operand count past the operand words there are.
@ __wellformed TlMod m i p → !v String {
    : i nl ( __nl m p )
    : ( Vec String ) open ( vec_new [String] )
    : ~ i l 0
    ~ < l nl {
        : s w ( __wd m p l 0 )
        : i depth ( vec_len [String] open )
        : String top ? > depth 0 ( string_clone ( vec_at [String] open - depth 1 ) ) ( string_new )
        : s tp ( string_data top )
        ? ( __opener w ) { ( vec_push [String] open ( string_from w ) ) } {
            ? ( __eq w `end` ) {
                ? == depth 0 { ^ ( __wf_bad m p `block` l `an end with no block open` ) } {}
                : ?String _o ( vec_pop [String] open )
            } {
                ? ( __eq w `else` ) {
                    ? ! ( __eq tp `if` ) { ^ ( __wf_bad m p `block` l `an else not in an if` ) } {}
                    ( vec_put [String] open - depth 1 ( string_from `else` ) )
                } {}
                ? ( __eq w `arm` ) {
                    ? ! | ( __eq tp `match` ) ( __eq tp `arm` ) { ^ ( __wf_bad m p `block` l `an arm not in a match` ) } {}
                    ( vec_put [String] open - depth 1 ( string_from `arm` ) )
                } {}
                ? ( __eq w `loopcond` ) {
                    ? ! ( __eq tp `loop` ) { ^ ( __wf_bad m p `block` l `a loopcond not in a loop` ) } {}
                    ( vec_put [String] open - depth 1 ( string_from `loopcond` ) )
                } {}
            }
        }
        : i off ( __wf_rv m p l )
        : i nw ( __nw m p l )
        ? & >= off 0 < off nw {
            : s h ( __wd m p l off )
            : ~ i cp -1
            ? | ( __eq h `call` ) ( __eq h `closure` ) { = cp + off 2 } {}
            ? | ( __eq h `callind` ) ( __eq h `scalar` ) { = cp + off 1 } {}
            ? ( __eq h `agg` ) { = cp + off 2 } {}
            ? >= cp 0 {
                ? >= cp nw { ^ ( __wf_bad m p `operands` l ( string_data ( __f1 `a % without its operand count` h ) ) ) } {}
                ? ! ( __int_syntax ( __wd m p l cp ) ) {
                    ^ ( __wf_bad m p `operands` l ( string_data ( __f2 `a % whose operand count is not a number: %` h ( __wd m p l cp ) ) ) )
                } {}
                : i n ( __pcount ( __wd m p l cp ) )
                ? < n 0 { ^ ( __wf_bad m p `operands` l ( string_data ( __f2 `a % that counts % operands` h ( __wd m p l cp ) ) ) ) } {}
                ? > n - nw + cp 1 {
                    ^ ( __wf_bad m p `operands` l ( string_data ( __f3 `a % that counts % operands and has %` h ( __wd m p l cp ) ( string_data ( __ns - nw + cp 1 ) ) ) ) )
                } {}
                // (exactly: only a literal, `agg`, has words after its
                // operands, its type)
                ? & ! ( __eq h `agg` ) < n - nw + cp 1 {
                    ^ ( __wf_bad m p `operands` l ( string_data ( __f3 `a % that counts % operands and has %` h ( __wd m p l cp ) ( string_data ( __ns - nw + cp 1 ) ) ) ) )
                } {}
            } {}
        } {}
        = l + l 1
    }
    : i depth ( vec_len [String] open )
    ? > depth 0 {
        : String o ( string_from `a block (` )
        ( string_push_str o ( string_data ( vec_at [String] open - depth 1 ) ) )
        ( string_push_str o `) with no end before the function's end` )
        ^ ( __wf_bad m p `block` - nl 1 ( string_data o ) )
    } {}
    ^ @ !v String { T }
}

// Fn.__init__ (signature part): the function's parameters, A2's numbering
// of them, its result and what it lends. With `check_locals` F, skips
// checking local variables' types so stubs can reuse the exact same
// signature mapping; with T, runs in the exact order of tolean.py.
@ __fn_sig_init TlMod m inout TlSt t i p b check_locals → !v String {
    \ ( __wellformed m p )
    ? & . m threaded > ( string_len ( vec_at [String] . m serr p ) ) 0 { ^ @ !v String { F ( string_clone ( vec_at [String] . m serr p ) ) } } {}
    : s name ( __name m p )
    : i np ( __np m p )
    = . t p p
    = . t np np
    = . t has_vmap F
    = . t vmap_ids ( __ids_sorted m p )
    = . t vmap ( vec_new [i] )
    = . t caps ( vec_new [i] )
    = . t named ( vec_new [i] )
    = . t prms ( vec_new [i] )
    = . t lits ( vec_new [i] )
    = . t elems ( vec_new [i] )
    = . t views ( vec_new [i] )
    = . t lends ( vec_new [String] )
    = . t depth 0
    : ( Vec i ) ids ( __ids_sorted m p )
    : i nids ( vec_len [i] ids )
    : ~ i top -1
    ? > - np 1 top { = top - np 1 } {}
    ? > nids 0 { ? > ( vec_at [i] ids - nids 1 ) top { = top ( vec_at [i] ids - nids 1 ) } {} } {}
    // past every core variable and the result slot
    = . t next + top 2
    = . t rslot np
    = . t closure ( __sw name `__closure_` )
    ? . t closure {
        // (a closure's code: its environment first, then its parameters,
        // then the result slot; its captures are read out of the
        // environment at the top of the body: A2/Invariant.lean, `Implements`)
        : ( Vec i ) caps ( vec_new [i] )
        : ( Vec i ) prms ( vec_new [i] )
        : ~ i j 0
        ~ < j nids {
            : i k ( vec_at [i] ids j )
            ? == ( __vkind m p k ) 3 { ( vec_push [i] caps k ) } {}
            ? == ( __vkind m p k ) 0 { ( vec_push [i] prms k ) } {}
            = j + j 1
        }
        ? != ( vec_len [i] prms ) np { ^ @ !v String { F ( __u m p `closure parameters` ) } } {}
        : i nc ( vec_len [i] caps )
        = j 0
        ~ < j nc {
            : String _c \ ( __cap_ty m t p ( __vty m p ( vec_at [i] caps j ) ) )
            : String _m \ ( __cap_mode m t p ( vec_at [i] caps j ) )
            = j + j 1
        }
        = j 0
        ~ < j np {
            ? != 0 & ( __vflags m p ( vec_at [i] prms j ) ) 6 { ^ @ !v String { F ( __u m p `a closure parameter taken sink or inout` ) } } {}
            = j + j 1
        }
        ? ( __borrowed m name ) { ^ @ !v String { F ( __u m p `a closure whose result is lent` ) } } {}
        = j 0
        ~ < j nids { ( vec_push [i] . t vmap -1 ) = j + j 1 }
        = j 0
        ~ < j np { ( vec_put [i] . t vmap ( core_bsearch ids ( vec_at [i] prms j ) ) + 1 j ) = j + j 1 }
        // (captures by name: the code's parameters after the interface's)
        : ( Vec i ) named ( vec_new [i] )
        = j 0
        ~ < j nc {
            : i k ( vec_at [i] caps j )
            : ~ b nm \ ( __named_cap m t p k )
            ? nm { = nm ! ( __is_moved m p j ) } {}
            ? nm { ( vec_push [i] named k ) } {}
            = j + j 1
        }
        : i nn ( vec_len [i] named )
        ? & & . m threaded ( __in . m spawned p ) > nn 0 {
            // A3: a spawned closure (class `send`) holds nothing by name
            : i k0 ( __vix m p ( vec_at [i] named 0 ) )
            : s cn ( string_data . ( vec_at [CoreVar] . ( vec_at [CoreFn] . . m ir fns ( __cf m p ) ) vars k0 ) name )
            ^ @ !v String { F ( __u m p ( string_data ( __f1 `a spawned closure capturing % by name` cn ) ) ) }
        } {}
        = j 0
        ~ < j nn { ( vec_put [i] . t vmap ( core_bsearch ids ( vec_at [i] named j ) ) + + 1 np j ) = j + j 1 }
        : ( Vec i ) caps2 ( vec_new [i] )
        = j 0
        ~ < j nc {
            ? ! ( __in named ( vec_at [i] caps j ) ) { ( vec_push [i] caps2 ( vec_at [i] caps j ) ) } {}
            = j + j 1
        }
        = . t rslot + + np 1 nn
        : ~ i nxt + . t rslot 1
        = j 0
        ~ < j nids {
            ? < ( vec_at [i] . t vmap j ) 0 {
                ( vec_put [i] . t vmap j nxt )
                = nxt + nxt 1
            } {}
            = j + j 1
        }
        = . t has_vmap T
        = . t caps caps2
        = . t named named
        = . t prms prms
        = . t next + nxt 1
    } {}
    // (a parameter with no `v` line has type "": only when "" names a
    // destructor type must every index below np be asked; else the ones
    // with a type)
    : ~ i j 0
    ? check_locals {
        : ( Vec i ) order ( __ids_order m p )
        : i no ( vec_len [i] order )
        = j 0
        ~ < j no {
            : String _l \ ( __lean_ty m t ( __vty m p ( vec_at [i] order j ) ) )
            = j + j 1
        }
    } {}
    : b dt0 ( __is_dtor m `` )
    : ( Vec i ) pl ( vec_new [i] )
    ? dt0 { = j 0 ~ < j np { ( vec_push [i] pl j ) = j + j 1 } } {
        = j 0
        ~ < j nids {
            : i k ( vec_at [i] ids j )
            ? & >= k 0 < k np { ( vec_push [i] pl k ) } {}
            = j + j 1
        }
    }
    : i npl ( vec_len [i] pl )
    = j 0
    ~ < j npl {
        ? & ( __is_dtor m ( __vtyd m p ( vec_at [i] pl j ) `` ) ) != 0 & ( __vflags m p ( vec_at [i] pl j ) ) 6 {
            // a `sink` / `inout` destructor parameter: moved to a `letd`
            // first thing, or never assigned (dtorParamsB), not yet
            ^ @ !v String { F ( __u m p `a destructor value as a sink or inout parameter` ) }
        } {}
        = j + j 1
    }
    ? ( __is_dtor m ( __ret m p ) ) { ^ @ !v String { F ( __u m p `a destructor value handed back` ) } } {}
    : String rt \ ( __lean_ty m t ( __ret m p ) )
    = . t res_own ! ( __eq ( string_data rt ) `.int` )
    = . t res_ty rt
    ( __view_vars m t )
    ? ( __eq ( __sval m name `retdyn` `` ) `1` ) {
        // owned on some paths and lent on others, answered per call: A2's
        // results are one or the other
        ^ @ !v String { F ( __u m p `a result owned or lent per call` ) }
    } {}
    : b bor ( __borrowed m name )
    ? & & ( __shas m name `ret_alias` ) ! bor . t res_own {
        ^ @ !v String { F ( __u m p ( string_data ( __f1 `a result aliasing parameter %` ( __sval m name `ret_alias` `` ) ) ) ) }
    } {}
    : ~ b any_ret F
    : ~ b lit_only T
    : i nl ( __nl m p )
    = j 0
    ~ < j nl {
        : s w0 ( __wd m p j 0 )
        ? | ( __eq w0 `ret` ) ( __eq w0 `retnx` ) {
            = any_ret T
            ? ! & > ( __nw m p j ) 1 ( __eq ( __wd m p j 1 ) `c` ) { = lit_only F } {}
        } {}
        = j + j 1
    }
    = lit_only & any_ret lit_only
    : s rv ( __sval m name `rviews` `:` )
    ? & & bor | ( __eq rv `:` ) ( __eq rv `` ) ! lit_only {
        // lent, but from no parameter's storage: a copy of a view an
        // argument holds, not translated yet. (AGORA-980: one that hands
        // back only literals lends nothing, `Rhs.slit`.)
        ^ @ !v String { F ( __u m p `a result copying a view an argument holds` ) }
    } {}
    ? bor {
        // a result that views what it was handed: a `slice` of it, not
        // owned, depending on the parameters it names
        ? ! ( __eq ( __ret m p ) `i8*` ) { ^ @ !v String { F ( __u m p ( string_data ( __f1 `a borrowed result of type %` ( __ret m p ) ) ) ) } } {}
        = . t res_ty ( string_from `(.slice .int)` )
        = . t res_own F
        : ( Vec i ) ks ( vec_new [i] )
        : ( Vec String ) kinds ( vec_new [String] )
        \ ( __view_deps m name ks kinds )
        : i nk ( vec_len [i] ks )
        = j 0
        ~ < j nk {
            : i k ( vec_at [i] ks j )
            ? < k np {
                ( vec_push [String] . t lends ( __f2 `(%, %)` ( string_data ( __ns k ) ) ( string_data ( vec_at [String] kinds j ) ) ) )
            } {}
            = j + j 1
        }
    } {}
    ^ @ !v String { T }
}

// Fn.__init__: the function's variables, A2's numbering of them, its
// result and what it lends.
@ __fn_init TlMod m inout TlSt t i p → !v String {
    ^ ( __fn_sig_init m t p T )
}

// mode: parameter `i`'s A2 mode: `sink`, `inout`, a handle the function
// changes through as its summary says (AGORA-994), or read only.
@ __mode TlMod m inout TlSt t i i → !String String {
    : i fl ( __vflags m . t p i )
    ? != 0 & fl 4 { ^ ( __ok ( string_from `.sink` ) ) } {}
    ? != 0 & fl 2 { ^ ( __ok ( string_from `(.inout .replace)` ) ) } {}
    : String ch ( __summary_change m ( __name m . t p ) i )
    ? > ( string_len ch ) 0 {
        : String vl \ ( __vlean m t i )
        ? ( __sw ( string_data vl ) `(.vec` ) { ^ ( __ok ( __f1 `(.inout %)` ( string_data ch ) ) ) } {}
    } {}
    ^ ( __ok ( string_from `.inp` ) )
}

// The `params` list of a function (normal or closure), after `__fn_sig_init`.
@ __fn_params TlMod m inout TlSt t → !String String {
    : i p . t p
    : String params ( string_new )
    : ~ i j 0
    ? . t closure {
        // the environment (lent, `inp`), then the interface's parameters
        : ( Vec String ) ets ( vec_new [String] )
        : ( Vec i ) caps ( vec_clone [i] . t caps )
        : i nc ( vec_len [i] caps )
        = j 0
        ~ < j nc {
            : String ct \ ( __cap_ty m t p ( __vty m p ( vec_at [i] caps j ) ) )
            ( vec_push [String] ets ct )
            = j + j 1
        }
        ( string_push_str params ( string_data ( __f1 `(.inp, %)` ( string_data ( __env_ty ets ) ) ) ) )
        : ( Vec i ) prms ( vec_clone [i] . t prms )
        : i npr ( vec_len [i] prms )
        = j 0
        ~ < j npr {
            : String vl \ ( __vlean m t ( vec_at [i] prms j ) )
            ( string_push_str params ( string_data ( __f1 `, (.inp, %)` ( string_data vl ) ) ) )
            = j + j 1
        }
        : ( Vec i ) named ( vec_clone [i] . t named )
        : i nn ( vec_len [i] named )
        = j 0
        ~ < j nn {
            : String md \ ( __cap_mode m t p ( vec_at [i] named j ) )
            : String vl \ ( __vlean m t ( vec_at [i] named j ) )
            ( string_push_str params ( string_data ( __f2 `, (%, %)` ( string_data md ) ( string_data vl ) ) ) )
            = j + j 1
        }
    } {
        : i np . t np
        = j 0
        ~ < j np {
            : String md \ ( __mode m t j )
            : String vl \ ( __vlean m t j )
            ? > j 0 { ( string_push_str params `, ` ) } {}
            ( string_push_str params ( string_data ( __f2 `(%, %)` ( string_data md ) ( string_data vl ) ) ) )
            = j + j 1
        }
    }
    ^ ( __ok params )
}

@ __fn_lends TlSt t → String {
    : String lends ( string_new )
    : i nle ( vec_len [String] . t lends )
    : ~ i j 0
    ~ < j nle {
        ? > j 0 { ( string_push_str lends `, ` ) } {}
        ( string_push_str lends ( string_data ( vec_at [String] . t lends j ) ) )
        = j + j 1
    }
    ^ lends
}

// Fn.lean: the function as A2's `Fn`.
@ __lean TlMod m inout TlSt t → !String String {
    : i p . t p
    : ( Vec i ) all ( vec_new [i] )
    : i nl ( __nl m p )
    : ~ i j 0
    ~ < j nl { ( vec_push [i] all j ) = j + j 1 }
    // (a `void` function may fall off its end: its result is the unit)
    : String tail ? ( __eq ( __ret m p ) `void` ) ( __f1 `(.assign % (.expr (.lit 0)))` ( string_data ( __ns . t rslot ) ) ) ( string_from `.skip` )
    : ~ String inner \ ( __stmts m t all 0 nl ( string_data tail ) )
    // (every literal temporary is bound at the statement that consumes it:
    // __stmts leaves none)
    ? > ( vec_len [i] . t lits ) 0 { ^ @ !String String { F ( string_from `internal: a literal temporary bound by no statement` ) } } {}
    ? . t closure { = inner \ ( __read_caps m t ( string_data inner ) ) } {}
    : String body ( __f1 `(.block %)` ( string_data inner ) )
    : String params \ ( __fn_params m t )
    : String lends ( __fn_lends t )
    : s own ? . t res_own `true` `false`
    : String a ( __f5 `{ params := [%], resTy := %, resOwn := %, lends := [%], rholds := [%],\n` ( string_data params ) ( string_data . t res_ty ) own ( string_data lends ) ( string_data lends ) )
    ^ ( __ok ( __f3 `%    outHolds := [], body := %, nvars := % }` ( string_data a ) ( string_data body ) ( string_data ( __ns + . t next 1 ) ) ) )
}

// ── The program ──────────────────────────────────────────────────────

// moved_caps: per closure code, the captures (its kind-3 variables) that
// every literal of it moves into the environment: the creating function
// releases the binding nowhere and reads it no more after the literal
// (AGORA-994).
@ __moved_caps TlMod m → ( Vec ( Vec i ) ) {
    : i nf ( vec_len [i] . m prog )
    : ( Vec ( Vec i ) ) out ( vec_new [( Vec i )] )
    : ( Vec b ) seen ( vec_new [b] )
    : ~ i q 0
    ~ < q nf { ( vec_push [( Vec i )] out ( vec_new [i] ) ) ( vec_push [b] seen F ) = q + q 1 }
    : ~ i p 0
    ~ < p nf {
        : i nl ( __nl m p )
        : ~ i li 0
        ~ < li nl {
            ? & & >= ( __nw m p li ) 5 ( __eq ( __wd m p li 0 ) `let` ) ( __eq ( __wd m p li 2 ) `closure` ) {
                : s code ( __wd m p li 3 )
                : i n ( __pcount ( __wd m p li 4 ) )
                : ( Vec i ) moved ( vec_new [i] )
                : ~ i j 0
                ~ & < j n < + 5 j ( __nw m p li ) {
                    : s op ( __wd m p li + 5 j )
                    ? ( __vref op ) {
                        // (only a binding of the function's own, a local or a
                        // temporary, is moved)
                        : i kd ( __vkind m p ( __pint_from op 1 ) )
                        ? | == kd 1 == kd 2 {
                            : String num ( __from op 1 )
                            : ~ b dropped F
                            : ~ i l 0
                            ~ & < l nl ! dropped {
                                ? & >= ( __nw m p l ) 2 & ( __eq ( __wd m p l 0 ) `drop` ) ( __eq ( __wd m p l 1 ) ( string_data num ) ) { = dropped T } {}
                                = l + l 1
                            }
                            : ~ b used F
                            = l + li 1
                            ~ & & ! dropped < l nl ! used {
                                : i nw ( __nw m p l )
                                : ~ i q2 0
                                ~ & < q2 nw ! used {
                                    : String wq ( string_from ( __wd m p l q2 ) )
                                    : ( Slice u ) tq ( slice_of_str ( string_data wq ) )
                                    : i nq ( slice_len [u] tq )
                                    : ~ i x 0
                                    ~ & < x nq ! used {
                                        : ~ i z x
                                        ~ & < z nq != ( slice_byte tq z ) 47 { = z + z 1 }
                                        ? < x z {
                                            : String tok ( string_new )
                                            ( string_push_window tok tq x - z x )
                                            ? ( __eq ( string_data tok ) op ) { = used T } {}
                                        } {}
                                        = x + z 1
                                    }
                                    = q2 + q2 1
                                }
                                = l + l 1
                            }
                            ? & ! dropped ! used { ( vec_push [i] moved j ) } {}
                        } {}
                    } {}
                    = j + j 1
                }
                : i ci ( __mget . m names code )
                ? >= ci 0 {
                    ? ( vec_at [b] seen ci ) {
                        // the intersection with the literals before
                        : ( Vec i ) prev ( vec_at [( Vec i )] out ci )
                        : ( Vec i ) both ( vec_new [i] )
                        : i npv ( vec_len [i] prev )
                        : ~ i k 0
                        ~ < k npv {
                            ? ( __in moved ( vec_at [i] prev k ) ) { ( vec_push [i] both ( vec_at [i] prev k ) ) } {}
                            = k + k 1
                        }
                        ( vec_put [( Vec i )] out ci both )
                    } {
                        ( vec_put [( Vec i )] out ci moved )
                        ( vec_put [b] seen ci T )
                    }
                } {}
            } {}
            = li + li 1
        }
        = p + p 1
    }
    ^ out
}

// The variables' flags of each program function: a parameter the walk
// inferred consumed (`sink=`) or kept (`keeps=`) is one the callee takes
// over, as a declared `sink` is (AGORA-994).
@ __flags CoreIR ir ( Vec i ) prog ( Vec ( Vec i ) ) sinkp → ( Vec ( Vec i ) ) {
    : ( Vec ( Vec i ) ) out ( vec_new [( Vec i )] )
    : i nf ( vec_len [i] prog )
    : ~ i p 0
    ~ < p nf {
        : CoreFn fn ( vec_at [CoreFn] . ir fns ( vec_at [i] prog p ) )
        : ( Vec i ) fl ( vec_new [i] )
        : i nv ( vec_len [i] . fn vids )
        : ~ i k 0
        ~ < k nv {
            ( vec_push [i] fl . ( vec_at [CoreVar] . fn vars ( vec_at [i] . fn vrec k ) ) flags )
            = k + k 1
        }
        : ( Vec i ) sk ( vec_new [i] )
        : i si ( core_sum_index ir ( string_data . fn name ) )
        ? >= si 0 {
            : CoreSum sm ( vec_at [CoreSum] . ir sums si )
            : ( Vec String ) ws ( vec_new [String] )
            : i ks ( core_sum_key sm `sink` )
            ? >= ks 0 {
                : ( Slice u ) t ( slice_of_str ( string_data ( vec_at [String] . sm vals ks ) ) )
                ( core_split_words t 0 ( slice_len [u] t ) ws )
            } {}
            : i kk ( core_sum_key sm `keeps` )
            ? >= kk 0 {
                : ( Slice u ) t ( slice_of_str ( string_data ( vec_at [String] . sm vals kk ) ) )
                ( core_split_words t 0 ( slice_len [u] t ) ws )
            } {}
            : i nw ( vec_len [String] ws )
            = k 0
            ~ < k nw {
                : s w ( string_data ( vec_at [String] ws k ) )
                ? ( __isdig w ) {
                    // (past 64 bits: past every parameter count)
                    : i v ( __pidx w )
                    ? & >= v 0 & < v . fn np ! ( __in sk v ) { ( vec_push [i] sk v ) } {}
                } {}
                = k + k 1
            }
        } {}
        ( vec_push [( Vec i )] out fl )
        ( vec_push [( Vec i )] sinkp sk )
        = p + p 1
    }
    ^ out
}

// A3: the spawns of each program function: `call thread_spawn_owned 1 vC`
// whose closure value vC is, through `let v use w` copies, a literal of
// the function (`let v closure code …`), no binding of the chain assigned.
// Every value of the chain goes to sendv (its code to sendc), each code to
// spawned (once). T when the program spawns at all.
// A count word, 0 where it is not one (__wellformed refuses it later).
@ __wcount s w → i { ^ ? ( __int_syntax w ) ( __pcount w ) 0 }

// The word positions of line l that are operands or places (a call's
// callee, a count, a variant, a field name and the like are not): what a
// statement reads or writes.
@ __operand_words TlMod m i p i l → ( Vec i ) {
    : ( Vec i ) out ( vec_new [i] )
    : i nw ( __nw m p l )
    : s w ( __wd m p l 0 )
    // (`assign <place> …`, `if/match/loopcond/ret <op>`, `foreach <x> <op>`)
    ? | | | | ( __eq w `assign` ) ( __eq w `if` ) ( __eq w `match` ) ( __eq w `loopcond` ) ( __eq w `ret` ) { ( vec_push [i] out 1 ) } {}
    ? ( __eq w `foreach` ) { ( vec_push [i] out 2 ) } {}
    : i off ( __wf_rv m p l )
    ? & >= off 0 < off nw {
        : s h ( __wd m p l off )
        : ~ i from -1
        : ~ i cnt 0
        ? | ( __eq h `use` ) ( __eq h `payload` ) { = from + off 1 = cnt 1 } {}
        ? | | | ( __eq h `call` ) ( __eq h `closure` ) ( __eq h `agg` ) ( __eq h `opaque` ) {
            ? < + off 2 nw { = from + off 3 = cnt ( __wcount ( __wd m p l + off 2 ) ) } {}
        } {}
        ? | ( __eq h `callind` ) ( __eq h `scalar` ) {
            ? < + off 1 nw { = from + off 2 = cnt ( __wcount ( __wd m p l + off 1 ) ) } {}
        } {}
        : ~ i j 0
        ~ & & >= from 0 < j cnt < + from j nw {
            ( vec_push [i] out + from j )
            = j + j 1
        }
    } {}
    ^ out
}

// Does line l name one of `chain`'s variables as an operand (a whole
// variable `v<id>`, or the root of a place `v<id>/…`) other than where it
// may: the spawn line `sl` its argument chain[0], the copy line dl[i] of
// chain[i] its source chain[i + 1]?
@ __names_chain TlMod m i p i l ( Vec i ) chain ( Vec i ) dl i sl → b {
    : ( Vec i ) ops ( __operand_words m p l )
    : i no ( vec_len [i] ops )
    : i nc ( vec_len [i] chain )
    : ~ i q 0
    ~ < q no {
        : s word ( __wd m p l ( vec_at [i] ops q ) )
        : i sl2 ( nurl_str_find word `/` )
        : String root ? < sl2 0 ( string_from word ) ( __sl word 0 sl2 )
        : ~ i c 0
        ~ < c nc {
            ? ( __is_v ( string_data root ) ( vec_at [i] chain c ) ) {
                : b at_spawn & == l sl == c 0
                : b at_copy & > c 0 == l ( vec_at [i] dl - c 1 )
                ? ! | at_spawn at_copy { ^ T } {}
            } {}
            = c + c 1
        }
        = q + q 1
    }
    ^ F
}

// A3: is the spawn of `chain` (its literal bound at line dl[last], the
// spawn at line sl) the closure's only use? thread_spawn_owned copies the
// environment, and the translation moves the closure into the wrapper:
// one used again (after the spawn, or a spawn repeated by a loop around
// it), passed on, or read in any other way is not translated (""
// when it is the only use, else why).
@ __spawn_uses TlMod m i p ( Vec i ) chain ( Vec i ) dl i sl → String {
    : i nl ( __nl m p )
    : i lit ( vec_at [i] dl - ( vec_len [i] dl ) 1 )
    // (a loop opened between the literal and the spawn, still open there)
    : ( Vec String ) open ( vec_new [String] )
    : ~ i l + lit 1
    ~ < l sl {
        : s w ( __wd m p l 0 )
        ? ( __opener w ) { ( vec_push [String] open ( string_from w ) ) } {
            ? & ( __eq w `end` ) > ( vec_len [String] open ) 0 { : ?String _o ( vec_pop [String] open ) } {}
        }
        = l + l 1
    }
    ? | ( __sin open `loop` ) ( __sin open `foreach` ) {
        ^ ( string_from `a spawned closure used again after its spawn (thread_spawn_owned copies the environment; the copy is not translated yet)` )
    } {}
    = l 0
    ~ < l nl {
        ? ( __names_chain m p l chain dl sl ) {
            ? > l sl {
                ^ ( string_from `a spawned closure used again after its spawn (thread_spawn_owned copies the environment; the copy is not translated yet)` )
            } {}
            : i off ( __wf_rv m p l )
            ? & >= off 0 ( __eq ( __wd m p l off ) `call` ) {
                ^ ( string_from `a spawned closure passed to a function that takes the ordinary closure type` )
            } {}
            ^ ( string_from `a spawned closure used other than by its spawn` )
        } {}
        = l + l 1
    }
    ^ ( string_new )
}

@ __spawn_scan TlMod m ( Vec ( Vec i ) ) sendv ( Vec ( Vec i ) ) sendc ( Vec i ) spawned ( Vec String ) serr → b {
    : ~ b threaded F
    : i nf ( vec_len [i] . m prog )
    : ~ i p 0
    ~ < p nf {
        : ( Vec i ) sv ( vec_new [i] )
        : ( Vec i ) sc ( vec_new [i] )
        : ~ String err ( string_new )
        : i nl ( __nl m p )
        : ~ i l 0
        ~ < l nl {
            : i nw ( __nw m p l )
            : ~ i ap -1
            ? & & & >= nw 6 ( __eq ( __wd m p l 0 ) `let` ) ( __eq ( __wd m p l 2 ) `call` ) ( __eq ( __wd m p l 3 ) `thread_spawn_owned` ) { = ap 5 } {}
            ? & & & >= nw 5 ( __eq ( __wd m p l 0 ) `eval` ) ( __eq ( __wd m p l 1 ) `call` ) ( __eq ( __wd m p l 2 ) `thread_spawn_owned` ) { = ap 4 } {}
            ? >= ap 0 {
                = threaded T
                : s op ( __wd m p l ap )
                ? ( __vref op ) {
                    : ( Vec i ) chain ( vec_new [i] )
                    : ( Vec i ) dl ( vec_new [i] )
                    : ~ i id ( __pidx ( string_data ( __from op 1 ) ) )
                    : ~ i code -1
                    : ~ i steps 0
                    : ~ b go T
                    ~ & go < steps nl {
                        = steps + steps 1
                        : String vs ( __ns id )
                        // the statement that binds it
                        : ~ i d 0
                        ~ & < d nl ! & & >= ( __nw m p d ) 3 ( __eq ( __wd m p d 0 ) `let` ) ( __eq ( __wd m p d 1 ) ( string_data vs ) ) { = d + d 1 }
                        ? >= d nl { = go F } {
                            ( vec_push [i] chain id )
                            ( vec_push [i] dl d )
                            : s h ( __wd m p d 2 )
                            ? & & ( __eq h `use` ) == ( __nw m p d ) 4 ( __vref ( __wd m p d 3 ) ) {
                                = id ( __pidx ( string_data ( __from ( __wd m p d 3 ) 1 ) ) )
                            } {
                                ? & ( __eq h `closure` ) >= ( __nw m p d ) 4 { = code ( __mget . m names ( __wd m p d 3 ) ) } {}
                                = go F
                            }
                        }
                    }
                    // (no binding of the chain given another value)
                    : ~ b assigned F
                    : ~ i d2 0
                    ~ < d2 nl {
                        ? & >= ( __nw m p d2 ) 2 ( __eq ( __wd m p d2 0 ) `assign` ) {
                            : s pl ( __wd m p d2 1 )
                            : ~ i q 0
                            ~ < q ( vec_len [i] chain ) {
                                ? ( __is_v pl ( vec_at [i] chain q ) ) { = assigned T } {}
                                = q + q 1
                            }
                        } {}
                        = d2 + d2 1
                    }
                    ? & & >= code 0 ! assigned == 0 ( string_len err ) {
                        : String why ( __spawn_uses m p chain dl l )
                        ? > ( string_len why ) 0 { = err ( __u m p ( string_data why ) ) } {}
                    } {}
                    ? & >= code 0 ! assigned {
                        : ~ i q 0
                        ~ < q ( vec_len [i] chain ) {
                            ( vec_push [i] sv ( vec_at [i] chain q ) )
                            ( vec_push [i] sc code )
                            = q + q 1
                        }
                        ? ! ( __in spawned code ) { ( vec_push [i] spawned code ) } {}
                    } {}
                } {}
            } {}
            = l + l 1
        }
        ( vec_push [( Vec i )] sendv sv )
        ( vec_push [( Vec i )] sendc sc )
        ( vec_push [String] serr err )
        = p + p 1
    }
    ^ threaded
}

// `@W<j>@` → wrapper j's index, base + j.
@ __subst_wrappers s text i base → String {
    : ( Slice u ) t ( slice_of_str text )
    : i n ( slice_len [u] t )
    : String o ( string_with_cap + n 16 )
    : ~ i k 0
    : ~ i st 0
    ~ < k n {
        ? & & == ( slice_byte t k ) 64 < + k 1 n == ( slice_byte t + k 1 ) 87 {
            : ~ i e + k 2
            : ~ i v 0
            ~ & < e n & >= ( slice_byte t e ) 48 <= ( slice_byte t e ) 57 {
                = v + * v 10 - ( slice_byte t e ) 48
                = e + e 1
            }
            ? & < e n == ( slice_byte t e ) 64 {
                ( string_push_window o t st - k st )
                ( string_push_int o + base v )
                = st + e 1
                = k e
            } {}
        } {}
        = k + k 1
    }
    ( string_push_window o t st - n st )
    ^ o
}

// A function of the program's own that the translation does not cover:
// its name, and why (the reason the program would be refused with, were it
// the first).
: TlMiss {
    String name
    String why
}

// A stub emitted for an assumed function (AGORA-1033, formal/C/Complete.lean):
// its index in P, name, signature summary, callee list, local hasThru bit,
// and why it was not translated.
: TlStub {
    i idx
    String name
    String sig
    String callees
    b has_thru
    String why
}

// Is `f` a known non-own intrinsic that changes elements through a borrow
// (`.edit true` in `__intrinsic_`)?
@ __stub_is_thru_intr s f → b {
    ^ | | | | ( __sw f `vec_clear__` ) ( __sw f `vec_truncate__` ) ( __sw f `vec_reserve__` )
    ( __sw f `vec_shrink_to_fit__` ) ( __eq f `string_push_str` )
}

// Is `f` a known non-own intrinsic or pure/IO runtime call that never
// changes elements through a borrow?
@ __stub_is_nonthru_intr s f → b {
    ? | | | | ( __eq f `nurl_println_int` ) ( __eq f `nurl_println` ) ( __eq f `nurl_print` )
    ( __eq f `nurl_print_int` ) ( __eq f `nurl_eprint` ) { ^ T } {}
    ? | | | | ( __eq f `nurl_eprintln` ) ( __eq f `nurl_free_count` ) ( __eq f `nurl_alloc_count` )
    ( __eq f `nurl_str_cat` ) ( __eq f `nurl_str_len` ) { ^ T } {}
    ? | | | | ( __eq f `nurl_str_eq` ) ( __eq f `nurl_str_cmp` ) ( __eq f `nurl_str_starts` )
    ( __eq f `nurl_str_ends` ) ( __eq f `nurl_str_find` ) { ^ T } {}
    ? | | | | ( __eq f `nurl_str_to_int` ) ( __eq f `string_from` ) ( __eq f `string_data` )
    ( __eq f `string_len` ) ( __eq f `string_free` ) { ^ T } {}
    ? | | | | ( __sw f `vec_new__` ) ( __sw f `vec_push__` ) ( __sw f `vec_len__` )
    ( __sw f `vec_free__` ) ( __sw f `vec_at__` ) { ^ T } {}
    ? | | | | ( __sw f `slice_from_vec__` ) ( __sw f `slice_len__` ) ( __sw f `chan_new__` )
    ( __sw f `Channel_share__` ) ( __sw f `chan_send__` ) { ^ T } {}
    ? | | ( __sw f `chan_recv__` ) ( __sw f `chan_try_recv__` ) ( __sw f `chan_close__` ) { ^ T } {}
    ^ ( __eq f `thread_join` )
}

// Classify rvalue at word offset `off` of line `l` in function `p` for a stub:
// records own callees / closure interfaces in `callees` and sets `has_thru`
// when an intrinsic changes elements through a borrow. Refuses (F) any
// rvalue or unknown call whose effect on `calls` or `hasThru` cannot be
// determined syntactically (never guesses).
@ __stub_rv TlMod m inout TlSt t i p i l i off ( Vec i ) callees ( Vec String ) callee_names inout b has_thru → !v String {
    : i nw ( __nw m p l )
    ? >= off nw { ^ @ !v String { F ( __u m p `stub: missing rvalue` ) } } {}
    : s rw ( __wd m p l off )
    // (`none`: a slot not yet given a value, no call and no change)
    ? | | | | | ( __eq rw `use` ) ( __eq rw `agg` ) ( __eq rw `scalar` ) ( __eq rw `payload` ) ( __eq rw `closure` ) ( __eq rw `none` ) {
        ^ @ !v String { T }
    } {}
    ? ( __eq rw `callind` ) {
        ? < nw + off 3 { ^ @ !v String { F ( __u m p `stub: malformed callind` ) } } {}
        : s c0 ( __wd m p l + off 2 )
        ? ! ( __vref c0 ) { ^ @ !v String { F ( __u m p ( string_data ( __f1 `stub: callind through %` c0 ) ) ) } } {}
        : String vl \ ( __vlean m t ( __pint_from c0 1 ) )
        : i sigma \ ( __fn_sigma ( string_data vl ) )
        ? ! ( __in callees sigma ) {
            ( vec_push [i] callees sigma )
            ( vec_push [String] callee_names ( __f1 `fn%` ( string_data ( __ns sigma ) ) ) )
        } {}
        ^ @ !v String { T }
    } {}
    ? ( __eq rw `call` ) {
        ? < nw + off 2 { ^ @ !v String { F ( __u m p `stub: malformed call` ) } } {}
        : s f ( __wd m p l + off 1 )
        : i fi ( __mget . m names f )
        ? >= fi 0 {
            ? ! ( __in callees fi ) {
                ( vec_push [i] callees fi )
                ( vec_push [String] callee_names ( string_from f ) )
            } {}
            ^ @ !v String { T }
        } {}
        ? ( __stub_is_thru_intr f ) {
            = has_thru T
            ^ @ !v String { T }
        } {}
        ? ( __stub_is_nonthru_intr f ) {
            ^ @ !v String { T }
        } {}
        // A stdlib function whose core summary finished its body and neither
        // mutates, reallocates, drops elements of, nor takes inout any
        // parameter cannot change elements through a borrow.
        : i si ( core_sum_index . m ir f )
        ? & >= si 0 & ( __eq ( __sval m f `body_done` `` ) `1` )
        & ! ( __shas m f `mutates` ) & ! ( __shas m f `reallocs` )
        & ! ( __shas m f `ireallocs` ) & ! ( __shas m f `drops` ) ! ( __shas m f `inout` ) {
            ^ @ !v String { T }
        } {}
        ^ @ !v String { F ( __u m p ( string_data ( __f1 `stub: cannot classify call of % for hasThru` f ) ) ) }
    } {}
    ^ @ !v String { F ( __u m p ( string_data ( __f1 `stub: cannot classify rvalue %` rw ) ) ) }
}

// Build a stub `Fn` for function `p` (formal/C/Complete.lean): its signature
// from the core IR (`__fn_sig_init` + `__fn_params` + `__fn_lends`), and a
// body `(.seq s .panic)` whose `Stmt.calls` and `Stmt.hasThru` match the real
// body's. Returns F if any part of the signature or body cannot be classified.
@ __fn_stub TlMod m inout TlSt t i p s why ( Vec TlStub ) stubs → !String String {
    \ ( __fn_sig_init m t p F )
    : String params \ ( __fn_params m t )
    : String lends ( __fn_lends t )
    : s own ? . t res_own `true` `false`
    : ( Vec i ) callees ( vec_new [i] )
    : ( Vec String ) callee_names ( vec_new [String] )
    : ~ b has_thru F
    : i nl ( __nl m p )
    : ~ i l 0
    ~ < l nl {
        : i nw ( __nw m p l )
        ? > nw 0 {
            : s w0 ( __wd m p l 0 )
            ? | | | | | ( __eq w0 `line` ) ( __eq w0 `nop` ) ( __eq w0 `scope` ) ( __eq w0 `end` ) ( __eq w0 `if` ) ( __eq w0 `else` ) {
            } {
                ? | | | | | ( __eq w0 `match` ) ( __eq w0 `arm` ) ( __eq w0 `loop` ) ( __eq w0 `loopcond` ) ( __eq w0 `foreach` ) ( __eq w0 `break` ) {
                } {
                    ? | | | | ( __eq w0 `continue` ) ( __eq w0 `drop` ) ( __eq w0 `ret` ) ( __eq w0 `retnx` ) ( __eq w0 `defer` ) {
                    } {
                        ? ( __eq w0 `let` ) {
                            ? < nw 3 { ^ @ !String String { F ( __u m p `stub: malformed let` ) } } {}
                            : i vid ( __pint ( __wd m p l 1 ) )
                            ? ( __is_dtor m ( __vtyd m p vid `` ) ) {
                                : i df ( __dtor_f m ( __vty m p vid ) )
                                ? < df 0 { ^ @ !String String { F ( __u m p `stub: unknown destructor` ) } } {}
                                ? ! ( __in callees df ) {
                                    ( vec_push [i] callees df )
                                    ( vec_push [String] callee_names ( string_from ( __name m df ) ) )
                                } {}
                            } {}
                            \ ( __stub_rv m t p l 2 callees callee_names has_thru )
                        } {
                            ? ( __eq w0 `assign` ) {
                                \ ( __stub_rv m t p l 2 callees callee_names has_thru )
                            } {
                                ? ( __eq w0 `eval` ) {
                                    \ ( __stub_rv m t p l 1 callees callee_names has_thru )
                                } {
                                    ^ @ !String String { F ( __u m p ( string_data ( __f1 `stub: cannot classify statement %` w0 ) ) ) }
                                }
                            }
                        }
                    }
                }
            }
        } {}
        = l + l 1
    }
    : ~ String s ? has_thru ( string_from `(.edit true 0 (.trunc (.lit 0)))` ) ( string_from `.skip` )
    : ~ i q - ( vec_len [i] callees ) 1
    ~ >= q 0 {
        : String gs ( __ns ( vec_at [i] callees q ) )
        ? ( __eq ( string_data s ) `.skip` ) {
            = s ( __f1 `(.letcall 0 % [] .skip)` ( string_data gs ) )
        } {
            = s ( __f2 `(.seq (.letcall 0 % [] .skip) %)` ( string_data gs ) ( string_data s ) )
        }
        = q - q 1
    }
    : String body ( __f1 `(.seq % .panic)` ( string_data s ) )
    : String a ( __f5 `{ params := [%], resTy := %, resOwn := %, lends := [%], rholds := [%],\n` ( string_data params ) ( string_data . t res_ty ) own ( string_data lends ) ( string_data lends ) )
    : String sig ( __f4 `params := [%], resTy := %, resOwn := %, lends := [%]` ( string_data params ) ( string_data . t res_ty ) own ( string_data lends ) )
    : String cstr ( string_new )
    : i nc ( vec_len [String] callee_names )
    : ~ i ci 0
    ~ < ci nc {
        ? > ci 0 { ( string_push_str cstr `, ` ) } {}
        ( string_push_str cstr ( string_data ( vec_at [String] callee_names ci ) ) )
        = ci + ci 1
    }
    ( vec_push [TlStub] stubs @ TlStub { p ( string_from ( __name m p ) ) sig cstr has_thru ( string_from why ) } )
    ^ ( __ok ( __f2 `%    outHolds := [], body := %, nvars := 0 }` ( string_data a ) ( string_data body ) ) )
}

// One function's term (`__fn_init`, then `__lean`), or why not.
@ __fn_lean TlMod m inout TlSt t i p → !String String {
    \ ( __fn_init m t p )
    ^ ( __lean m t )
}

// The Lean file of the program in core IR `text` (tolean.py's `emit`), or
// why it is not translated; each of its own functions not translated goes
// into `miss`, and `cur` holds the name of the function being translated.
// With `all` F it stops at the first one, as tolean.py does: the verdict
// and its reason are the same either way. With `all` T and a single-threaded
// program, each missed function whose signature and body can be classified
// gets a stub (`__fn_stub`, `stubs`, `def assumed`), so the rest of the
// program can be certified conditionally (AGORA-1033). `reached` gets an
// entry once the functions are translated at all.
@ __emit s text ( Vec TlMiss ) miss ( Vec TlStub ) stubs ( Vec String ) cur b all ( Vec i ) reached → !String String {
    : CoreIR ir \ ( core_read text )
    // The standard library's functions are A2's constructs (`intrinsic`),
    // not bodies to check: their code is phase B's.
    : ( Vec i ) prog ( vec_new [i] )
    : ( HashMap String i ) names ( map_new [String i] )
    : ( HashMap String i ) dtor ( map_new [String i] )
    : i nall ( vec_len [CoreFn] . ir fns )
    : ~ i k 0
    ~ < k nall {
        : CoreFn fn ( vec_at [CoreFn] . ir fns k )
        // a library function: its file starts with `stdlib/` (caps.nu's
        // `__cp_is_lib` is the same rule: N.cap's indices are these)
        ? ! ( __sw ( string_data . fn file ) `stdlib/` ) {
            ( __mset names ( string_data . fn name ) ( vec_len [i] prog ) )
            ( vec_push [i] prog k )
            // a `% Drop` of the program's own: it runs at the end of every
            // value of the type (MEMORY.md §2.14)
            ? ( __sw ( string_data . fn name ) `drop__` ) {
                : String dn ( __pct ( string_data ( __from ( string_data . fn name ) 6 ) ) )
                ( __mset dtor ( string_data dn ) 1 )
            } {}
        } {}
        = k + k 1
    }
    : i nty ( vec_len [CoreTy] . ir tys )
    = k 0
    ~ < k nty {
        : CoreTy ct ( vec_at [CoreTy] . ir tys k )
        ? ( __has ( string_data . ct drops ) `d` ) { ( __mset dtor ( string_data . ct name ) 1 ) } {}
        = k + k 1
    }
    : ( Vec ( Vec i ) ) sinkp ( vec_new [( Vec i )] )
    : ( Vec ( Vec i ) ) flg ( __flags ir prog sinkp )
    : i nfn ( vec_len [i] prog )
    : i main_ix ( __mget names `main` )
    ? < main_ix 0 { ^ @ !String String { F ( string_from `no main` ) } } {}
    : TlMod m @ TlMod { ir prog names dtor flg sinkp ( vec_new [( Vec i )] ) F ( vec_new [( Vec i )] ) ( vec_new [( Vec i )] ) ( vec_new [i] ) ( vec_new [String] ) }
    : ( Vec ( Vec i ) ) moved ( __moved_caps m )
    : TlMod m1 @ TlMod { . m ir . m prog . m names . m dtor . m flg . m sinkp moved F ( vec_new [( Vec i )] ) ( vec_new [( Vec i )] ) ( vec_new [i] ) ( vec_new [String] ) }
    : ( Vec ( Vec i ) ) sendv ( vec_new [( Vec i )] )
    : ( Vec ( Vec i ) ) sendc ( vec_new [( Vec i )] )
    : ( Vec i ) spawned ( vec_new [i] )
    : ( Vec String ) serr ( vec_new [String] )
    : b threaded ( __spawn_scan m1 sendv sendc spawned serr )
    : TlMod mm @ TlMod { . m1 ir . m1 prog . m1 names . m1 dtor . m1 flg . m1 sinkp . m1 moved threaded sendv sendc spawned serr }
    : ( Vec i ) wsig ( vec_new [i] )
    : ~ i k1 0
    ~ < k1 ( vec_len [i] . mm spawned ) { ( vec_push [i] wsig -1 ) = k1 + k1 1 }
    : ~ TlSt t @ TlSt { ( vec_new [String] ) nfn ( vec_new [String] ) 0 0 0 F ( vec_new [i] ) ( vec_new [i] ) 0 ( vec_new [i] ) F ( vec_new [i] )
        ( vec_new [i] ) ( vec_new [i] ) ( vec_new [i] ) 0 ( string_new ) F ( vec_new [i] ) ( vec_new [String] ) wsig }
    // (A3: a program that spawns is decided by A3's checker, C.Cert3)
    : ~ String out ( string_from ? threaded `import C.Cert3\nopen A2 C\n\n` `import C.A2Prog\nopen A2 C\n\n` )
    // Every function is translated, also after one that is not (AGORA-1015):
    // each one the translation does not cover goes into `miss` with its
    // reason, and the program is refused with the first of them, as
    // tolean.py refuses it — unless `all` is set on a single-threaded
    // program and every missed function gets a stub (AGORA-1033).
    ( vec_push [i] reached 1 )
    : ~ i p 0
    : ~ String first ( string_new )
    : ~ b failed F
    : ~ b stub_ok all
    : ( Vec i ) assumed ( vec_new [i] )
    ~ & < p nfn | all ! failed {
        : i nclo0 ( vec_len [String] . t clo_list )
        : i nexp0 ( vec_len [String] . t expanding )
        ( vec_clear [String] cur )
        ( vec_push [String] cur ( string_from ( __name mm p ) ) )
        ?? ( __fn_lean mm t p ) {
            T l → {
                ( string_push_str out `def fn` )
                ( string_push_int out p )
                ( string_push_str out ` : Fn :=\n  ` )
                ( string_push_str out ( string_data l ) )
                ( string_push_char out 10 )
            }
            F e → {
                : b _a ( vec_truncate [String] . t clo_list nclo0 )
                : b _b ( vec_truncate [String] . t expanding nexp0 )
                ( vec_push [TlMiss] miss @ TlMiss { ( string_from ( __name mm p ) ) ( string_clone e ) } )
                ? ! failed {
                    = first ( string_clone e )
                    = failed T
                } {}
                ? & stub_ok ! ( string_starts_with e `internal: ` ) {
                    ?? ( __fn_stub mm t p ( string_data e ) stubs ) {
                        T sl → {
                            ( string_push_str out `def fn` )
                            ( string_push_int out p )
                            ( string_push_str out ` : Fn :=\n  ` )
                            ( string_push_str out ( string_data sl ) )
                            ( string_push_char out 10 )
                            ( vec_push [i] assumed p )
                        }
                        F _se → {
                            : b _c ( vec_truncate [String] . t clo_list nclo0 )
                            : b _d ( vec_truncate [String] . t expanding nexp0 )
                            = stub_ok F
                        }
                    }
                } {
                    = stub_ok F
                }
            }
        }
        = p + p 1
    }
    ( vec_clear [String] cur )
    // Conditional certificate only when every missed function got a stub and
    // at least one own function was actually translated (not all stubbed).
    : i na ( vec_len [i] assumed )
    : b cond & & & failed stub_ok > na 0 < na nfn
    ? & failed ! cond {
        ( vec_clear [TlStub] stubs )
        ^ @ !String String { F first }
    } {}
    // one interface per closure type: the receiver (the closure, lent),
    // then its parameters; its body is never run (a call runs the
    // package's code), so it is one that type-checks: a result of the
    // type, made fresh (a number, or an empty buffer)
    : ~ i kc 0
    ~ < kc ( vec_len [String] . t clo_list ) {
        : String key ( string_clone ( vec_at [String] . t clo_list kc ) )
        // (`send:` + a type: its interface at class `send`, A3)
        : b send ( __sw ( string_data key ) `send:` )
        : String ty ? send ( __from ( string_data key ) 5 ) ( string_clone key )
        : ( Vec String ) sig ( vec_new [String] )
        : b _c \ ( __clo_sig ( string_data ty ) sig )
        : i sigma + nfn kc
        : String ps ( __f2 `(.inp, (.fn [%] %))` ( string_data ( __ns sigma ) ) ? send `.send` `.any` )
        : i ns ( vec_len [String] sig )
        : ~ i j 1
        ~ < j ns {
            : String lt \ ( __lean_ty mm t ( string_data ( vec_at [String] sig j ) ) )
            ( string_push_str ps `, (.inp, ` )
            ( string_push_str ps ( string_data lt ) )
            ( string_push_str ps `)` )
            = j + j 1
        }
        : String rty \ ( __lean_ty mm t ( string_data ( vec_at [String] sig 0 ) ) )
        : s rt ( string_data rty )
        : s own ? ( __eq rt `.int` ) `false` `true`
        : i rs ns
        : ~ String made ( string_new )
        ? ( __eq rt `.int` ) { = made ( string_from `(.expr (.lit 0))` ) } {
            // rty.count("(") == 1
            : ( Slice u ) rv ( slice_of_str rt )
            : ~ i np 0
            : ~ i z 0
            ~ < z ( slice_len [u] rv ) { ? == ( slice_byte rv z ) 40 { = np + np 1 } {} = z + z 1 }
            ? & ( __sw rt `(.vec ` ) == np 1 { = made ( __f1 `(.new %)` ( string_data ( __sl rt 6 -1 ) ) ) } {
                ^ @ !String String { F ( __f2 `closure type %: a result of type %` ( string_data ty ) rt ) }
            }
        }
        : String sg ( __ns sigma )
        : String a ( __f5 `def fn% : Fn :=\n  { params := [%], resTy := %, resOwn := %, lends := [], rholds := [],\n` ( string_data sg ) ( string_data ps ) rt own `` )
        ( string_push_str out ( string_data ( __f4 `%    outHolds := [], body := (.block (.seq (.assign % %) (.exit 0))), nvars := % }\n` ( string_data a ) ( string_data ( __ns rs ) ) ( string_data made ) ( string_data ( __ns + rs 1 ) ) ) ) )
        = kc + kc 1
    }
    // A3: one spawn wrapper per closure code spawned: it takes the closure
    // over (`sink`, of its class `send`) and calls it, with no arguments;
    // A3 runs a call of it as the new thread
    : i nclo ( vec_len [String] . t clo_list )
    : i nsp ( vec_len [i] . mm spawned )
    : ~ i wj 0
    ~ < wj nsp {
        : i sg ( vec_at [i] . t wsig wj )
        ? < sg 0 { ^ @ !String String { F ( string_from `internal: a spawned closure code whose spawn was not translated` ) } } {}
        : String sgs ( __ns sg )
        : String a ( __f3 `def fn% : Fn :=\n  { params := [(.sink, (.fn [%] .send))], resTy := .int, resOwn := false, lends := [], rholds := [],\n` ( string_data ( __ns + + nfn nclo wj ) ) ( string_data sgs ) `` )
        ( string_push_str out ( string_data ( __f2 `%    outHolds := [], body := (.block (.seq (.callc 2 0 0 % [] .skip) (.seq (.assign 1 (.expr (.lit 0))) (.exit 0)))), nvars := 3 }\n` ( string_data a ) ( string_data sgs ) ) ) )
        = wj + wj 1
    }
    ( string_push_str out `\ndef P : Prog := [` )
    : i ntot + + nfn nclo nsp
    = k 0
    ~ < k ntot {
        ? > k 0 { ( string_push_str out `, ` ) } {}
        ( string_push_str out `fn` )
        ( string_push_int out k )
        = k + k 1
    }
    ( string_push_str out `]\ndef entry : Stmt := .letcall 0 ` )
    ( string_push_int out main_ix )
    ? threaded {
        ( string_push_str out ` [] .skip\ndef spawns : List Nat := [` )
        = wj 0
        ~ < wj nsp {
            ? > wj 0 { ( string_push_str out `, ` ) } {}
            ( string_push_int out + + nfn nclo wj )
            = wj + wj 1
        }
        ? cond {
            ( string_push_str out `]\ndef assumed : List Nat := [` )
            : ~ i ai 0
            ~ < ai na {
                ? > ai 0 { ( string_push_str out `, ` ) } {}
                ( string_push_int out ( vec_at [i] assumed ai ) )
                = ai + ai 1
            }
            ( string_push_str out `]\n\n#eval certOK3BA P spawns assumed entry 1\n` )
        } {
            ( string_push_str out `]\n\n#eval certOK3B P spawns entry 1\n` )
        }
        // the spawn sites name their wrapper `@W<j>@` until the wrappers'
        // indices are known
        ^ @ !String String { T ( __subst_wrappers ( string_data out ) + nfn nclo ) }
    } {}
    ? cond {
        ( string_push_str out ` [] .skip\ndef assumed : List Nat := [` )
        : ~ i ai 0
        ~ < ai na {
            ? > ai 0 { ( string_push_str out `, ` ) } {}
            ( string_push_int out ( vec_at [i] assumed ai ) )
            = ai + ai 1
        }
        ( string_push_str out `]\n\n#eval certOK2BA P assumed entry 1\n` )
        ^ @ !String String { T out }
    } {}
    ( string_push_str out ` [] .skip\n\n#eval progOK2B P && (checkA2 P entry.vars (fun _ => none) [] entry).isSome && stmtCodesB P entry\n` )
    ^ @ !String String { T out }
}

// The Lean file of the program in core IR `text`, or why it is not
// translated: tolean.py's `unsupported` reason, or `internal: …` where
// the core IR is not one the translation can read.
@ tolean_translate s text → !String String {
    : ( Vec TlMiss ) miss ( vec_new [TlMiss] )
    : ( Vec TlStub ) stubs ( vec_new [TlStub] )
    ^ ( __translate text miss stubs F )
}

// tolean_translate, and each of the program's own functions it does not
// translate into `miss`, with its reason (AGORA-1015), in the order of the
// core IR. When single-threaded and every missed function can be stubbed
// (with at least one own function translated), emits stubs and `def assumed`
// and records each stub in `stubs` (AGORA-1033). Otherwise refuses with the
// first reason, as tolean_translate does.
@ tolean_translate_fns s text ( Vec TlMiss ) miss ( Vec TlStub ) stubs → !String String { ^ ( __translate text miss stubs T ) }

@ __translate s text ( Vec TlMiss ) miss ( Vec TlStub ) stubs b all → !String String {
    : ~ String res ( string_new )
    : ~ String why ( string_new )
    : ~ b ok F
    : String tx ( string_from text )
    : ( Vec String ) cur ( vec_new [String] )
    : ( Vec i ) reached ( vec_new [i] )
    : !v PanicInfo r ( recover \ → v {
        ?? ( __emit ( string_data tx ) miss stubs cur all reached ) {
            T o → {
                = res o
                = ok T
            }
            F e → { = why e }
        }
    } )
    ?? r {
        T _ → {}
        F pi → {
            = ok F
            ( vec_clear [TlStub] stubs )
            : ~ String iw ( string_clone . pi msg )
            ? ! ( string_starts_with iw `internal: ` ) { = iw ( __f1 `internal: %` ( string_data . pi msg ) ) } {}
            ?? ( vec_get [String] cur 0 ) {
                T fname → {
                    // (a function stopped the translation: before it, a
                    // function not covered refuses the program first, as the
                    // translation one function at a time stopped there)
                    : i nm ( vec_len [TlMiss] miss )
                    ? == nm 0 { = why ( string_clone iw ) } {
                        = why ( string_clone . ( vec_at [TlMiss] miss 0 ) why )
                    }
                    ( vec_push [TlMiss] miss @ TlMiss { ( string_clone fname ) ( string_clone iw ) } )
                    ( vec_push [TlMiss] miss @ TlMiss { ( string_new ) ( __f1 `internal: the translation stopped in %` ( string_data fname ) ) } )
                }
                F _ → { = why ( string_clone iw ) }
            }
        }
    }
    ? ok { ^ @ !String String { T res } } {}
    // (refused before any function was translated: an entry with an empty
    // name, and no function named before it, says that none was reached)
    ? == ( vec_len [i] reached ) 0 { ( vec_push [TlMiss] miss @ TlMiss { ( string_new ) ( string_clone why ) } ) } {}
    ^ @ !String String { F why }
}
