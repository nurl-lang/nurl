// gpukit/checked.nu — kernels a safe caller may write.
//
// gk_run hands a kernel's source to the device compiler as is: a kernel
// can index any address it is given, so only `unsafe` code may launch
// one. A CHECKED kernel is written in a subset that cannot: its body
// reaches memory only through
//
//     LD(name, i)        the element at i of buffer `name` (its last
//                        element when i is outside it)
//     ST(name, i, v)     store v there (nothing past its end; outputs only)
//
// which gpukit defines per buffer from that buffer's own length, so every
// access is checked against the memory the call bound. The body sees its
// scalars by name, `gid` (this thread's index) and `nthreads` (how many
// run; a thread past it returns before the body). It may declare scalar
// locals, branch, loop and call the math functions below — nothing that
// makes or follows an address:
//
//   • no pointer declaration or dereference: a `*` that is not between
//     two operands, a `&` that takes an address, `[` `]`, `.`/`->`
//     (number literals aside), `#`, quotes and backslashes;
//   • no name gpukit keeps for itself (anything starting with `__`, bar
//     the rounding intrinsics), no `asm`, `goto`, `typedef`, `struct`,
//     casts by keyword, `new` or `delete`;
//   • calls only to LD / ST and a fixed list of math functions;
//   • braces and parentheses that balance, so the body cannot close the
//     kernel and write code after it.
//
// gk_run_checked rejects a body outside the subset (F, and the reason in
// gk_checked_error) before anything is compiled. What remains is a kernel
// that cannot reach memory it was not given, so launching one is safe.
//
//   : ~ GkCall c ( gk_call_new )
//   ( gk_call_in_f c `x` xs )         // moved in; ( gk_call_take_f c `y` ) moves out
//   ( gk_call_out_f c `y` ( vec_zeroed [f] n ) )
//   ( gk_call_i64 c `n` n )
//   : b ok ( gk_run_checked kit c `scale2` `ST(y, gid, 2.0 * LD(x, gid));` n 256 )
//   : ( Vec f ) ys ( gk_call_take_f c `y` )

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/floatbits.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/arc.nu`
$ `stdlib/std/hashmap.nu`
$ `gpukit.nu`
$ `devbuf.nu`

// One binding: kind 0 f64 input, 1 f64 output, 2 i64 input, 3 i64 output,
// 4 i64 scalar, 5 f64 scalar, 6 f64 input view, 7 i64 input view, 8 device
// buffer read, 9 device buffer read and written, 10 f64 output view, 11 i64
// output view, 12 16-bit float device buffer read (as floats). `slot` indexes fv / iv for a buffer and holds
// the value (an f64's bits) for a scalar.
: GkCall {
    ( Vec String ) names
    ( Vec i ) kinds
    ( Vec i ) slots
    ( Vec ( Vec f ) ) fv
    ( Vec ( Vec i ) ) iv
    ( Vec ( Slice f ) ) fs  // inputs bound as views: read where they are
    ( Vec ( Slice i ) ) is
    ( Vec GkBuf ) db  // device buffers (gk_call_dev / _dev_in): used where they live
    ( Vec GkHBuf ) hb  // 16-bit float buffers (gk_call_half_in): read where they live
    ( Vec GkBBuf ) qb  // byte buffers (gk_call_bytes_in): read where they live
    String err  // why gk_run_checked refused the kernel ("" when it did not)
}

@ gk_call_new → GkCall {
    ^ @ GkCall { ( vec_new [String] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [( Vec f )] ) ( vec_new [( Vec i )] ) ( vec_new [( Slice f )] ) ( vec_new [( Slice i )] ) ( vec_new [GkBuf] ) ( vec_new [GkHBuf] ) ( vec_new [GkBBuf] ) ( string_new ) }
}

@ __gkc_add inout GkCall c s name i kind i slot → v {
    ( vec_push [String] . c names ( string_from name ) )
    ( vec_push [i] . c kinds kind )
    ( vec_push [i] . c slots slot )
}

@ gk_call_in_f inout GkCall c s name sink ( Vec f ) v → v {
    ( __gkc_add c name 0 ( vec_len [( Vec f )] . c fv ) )
    ( vec_push [( Vec f )] . c fv v )
}

@ gk_call_out_f inout GkCall c s name sink ( Vec f ) v → v {
    ( __gkc_add c name 1 ( vec_len [( Vec f )] . c fv ) )
    ( vec_push [( Vec f )] . c fv v )
}

@ gk_call_in_i inout GkCall c s name sink ( Vec i ) v → v {
    ( __gkc_add c name 2 ( vec_len [( Vec i )] . c iv ) )
    ( vec_push [( Vec i )] . c iv v )
}

@ gk_call_out_i inout GkCall c s name sink ( Vec i ) v → v {
    ( __gkc_add c name 3 ( vec_len [( Vec i )] . c iv ) )
    ( vec_push [( Vec i )] . c iv v )
}

// An input read where it is — a view of the caller's data, no copy; the
// borrow checker keeps what it views alive while the call holds it.
@ gk_call_view_f inout GkCall c s name ( Slice f ) v → v {
    ( __gkc_add c name 6 ( vec_len [( Slice f )] . c fs ) )
    ( vec_push [( Slice f )] . c fs v )
}

// An output read and written where it is — a view of the caller's storage
// (a Slice is writable, as slice_put is): the kernel's stores land in it,
// and an element the kernel does not write keeps its value.
@ gk_call_view_out_f inout GkCall c s name ( Slice f ) v → v {
    ( __gkc_add c name 10 ( vec_len [( Slice f )] . c fs ) )
    ( vec_push [( Slice f )] . c fs v )
}

@ gk_call_view_out_i inout GkCall c s name ( Slice i ) v → v {
    ( __gkc_add c name 11 ( vec_len [( Slice i )] . c is ) )
    ( vec_push [( Slice i )] . c is v )
}

@ gk_call_view_i inout GkCall c s name ( Slice i ) v → v {
    ( __gkc_add c name 7 ( vec_len [( Slice i )] . c is ) )
    ( vec_push [( Slice i )] . c is v )
}

@ gk_call_i64 inout GkCall c s name i x → v { ( __gkc_add c name 4 x ) }

@ gk_call_f64 inout GkCall c s name f x → v { ( __gkc_add c name 5 ( f64_to_bits x ) ) }

// A device buffer the kernel reads (gk_run_checked_dev): nothing is copied;
// the call holds another owner of the buffer's block while it holds the
// binding, and the caller keeps its own.
@ gk_call_dev_in inout GkCall c s name GkBuf b → v {
    ( __gkc_add c name 8 ( vec_len [GkBuf] . c db ) )
    ( vec_push [GkBuf] . c db ( gk_buf_view b 0 . b n ) )
}

// A buffer of 16-bit floats (f16 or bf16) the kernel reads: LD(name, i)
// is the element as a float, converted exactly. Read only. (The call holds
// another owner of the buffer; the caller keeps its own.)
@ gk_call_half_in inout GkCall c s name GkHBuf h → v {
    ( __gkc_add c name 12 ( vec_len [GkHBuf] . c hb ) )
    ( vec_push [GkHBuf] . c hb ( _gk_hbuf_share h ) )
}

// A byte buffer the kernel reads (gk_run_checked_dev): LD gives a byte,
// LD16 / LD32 the aligned word holding it (see GkBBuf).
@ gk_call_bytes_in inout GkCall c s name GkBBuf q → v {
    ( __gkc_add c name 13 ( vec_len [GkBBuf] . c qb ) )
    ( vec_push [GkBBuf] . c qb ( _gk_bbuf_share q ) )
}

// A byte buffer the kernel reads and writes: as gk_call_bytes_in, and
// ST(name, i, v) stores the low byte of v at byte i (a store out of range
// is dropped).
@ gk_call_bytes inout GkCall c s name GkBBuf q → v {
    ( __gkc_add c name 14 ( vec_len [GkBBuf] . c qb ) )
    ( vec_push [GkBBuf] . c qb ( _gk_bbuf_share q ) )
}

// A device buffer the kernel reads and writes.
@ gk_call_dev inout GkCall c s name GkBuf b → v {
    ( __gkc_add c name 9 ( vec_len [GkBuf] . c db ) )
    ( vec_push [GkBuf] . c db ( gk_buf_view b 0 . b n ) )
}

// Give scalar `name` a new value — one call launched again and again. F
// when the call has no such scalar.
@ gk_call_set_i64 inout GkCall c s name i x → b {
    : i k ( __gkc_find c name )
    ? | < k 0 != ( vec_at [i] . c kinds k ) 4 { ^ F } {}
    ^ ( vec_set [i] . c slots k x )
}

@ gk_call_set_f64 inout GkCall c s name f x → b {
    : i k ( __gkc_find c name )
    ? | < k 0 != ( vec_at [i] . c kinds k ) 5 { ^ F } {}
    ^ ( vec_set [i] . c slots k ( f64_to_bits x ) )
}

@ __gkc_find GkCall c s name → i {
    : i n ( vec_len [String] . c names )
    : ~ i k 0
    ~ < k n {
        ? != 0 ( nurl_str_eq ( string_data ( vec_at [String] . c names k ) ) name ) { ^ k } {}
        = k + k 1
    }
    ^ -1
}

// Move buffer `name` back out of the call (an empty Vec when there is none).
@ gk_call_take_f inout GkCall c s name → ( Vec f ) {
    : i k ( __gkc_find c name )
    ? | < k 0 > ( vec_at [i] . c kinds k ) 1 { ^ ( vec_new [f] ) } {}
    ?? ( vec_replace [( Vec f )] . c fv ( vec_at [i] . c slots k ) ( vec_new [f] ) ) {
        T v → { ^ v }
        F → { ^ ( vec_new [f] ) }
    }
}

@ gk_call_take_i inout GkCall c s name → ( Vec i ) {
    : i k ( __gkc_find c name )
    ? | < k 0 | < ( vec_at [i] . c kinds k ) 2 > ( vec_at [i] . c kinds k ) 3 { ^ ( vec_new [i] ) } {}
    ?? ( vec_replace [( Vec i )] . c iv ( vec_at [i] . c slots k ) ( vec_new [i] ) ) {
        T v → { ^ v }
        F → { ^ ( vec_new [i] ) }
    }
}

@ __gkc_eq s a s b → b { ^ != 0 ( nurl_str_eq a b ) }

// Is `w` one of the space-separated words of `list`?
@ __gkc_word_in s list s w → b {
    : ( Slice u ) lv ( slice_of_str list )
    : ( Slice u ) wv ( slice_of_str w )
    : i n ( slice_len [u] lv )
    : i m ( slice_len [u] wv )
    ? == m 0 { ^ F } {}
    : ~ i k 0
    ~ < k n {
        ~ & < k n == ( slice_byte lv k ) 32 { = k + k 1 }
        : i s0 k
        ~ & < k n != ( slice_byte lv k ) 32 { = k + k 1 }
        ? == - k s0 m {
            : ~ b same T
            : ~ i j 0
            ~ & same < j m { ? != ( slice_byte lv + s0 j ) ( slice_byte wv j ) { = same F } {} = j + j 1 }
            ? same { ^ T } {}
        } {}
    }
    ^ F
}

@ __gkc_char i c → String {
    : ~ String o ( string_new )
    ( string_push_char o c )
    ^ o
}

@ __gkc_sub ( Slice u ) b i s0 i e → String {
    : ~ String o ( string_new )
    : ~ i k s0
    ~ < k e { ( string_push_char o ( slice_byte b k ) ) = k + k 1 }
    ^ o
}

// Kernels checked and built before: key (name, bindings, body) → the
// built source and its entry point, shared (an Arc) so a launch reads them
// in place. A fit launches the same kernel every round; checking its body
// once is enough.
: GkcBuilt { String src String ename b shfl }  // shfl: the blocks must be whole warps

: GkcCache { ( Vec String ) keys ( Vec ( Arc GkcBuilt ) ) built }

@ __gkc_cache0 → ( Locked GkcCache ) { ^ ( locked_new [GkcCache] @ GkcCache { ( vec_new [String] ) ( vec_new [( Arc GkcBuilt )] ) } ) }

: ( Locked GkcCache ) g_gkc_cache ( __gkc_cache0 )

@ __gkc_none → ( Arc GkcBuilt ) { ^ ( arc_new [GkcBuilt] @ GkcBuilt { ( string_new ) ( string_new ) F } ) }

// What was built for `key` (an empty source when nothing was, or while it
// is being built), and its cache index in `idx` (-1 when never checked).
@ __gkc_lookup s key inout i idx → ( Arc GkcBuilt ) {
    : ~ GkcCache c ( locked_take [GkcCache] g_gkc_cache )
    = idx -1
    : i n ( vec_len [String] . c keys )
    : ~ i k 0
    ~ < k n {
        ? != 0 ( nurl_str_eq ( string_data ( vec_at [String] . c keys k ) ) key ) { = idx k = k n } { = k + k 1 }
    }
    : ~ ( Arc GkcBuilt ) r ( __gkc_none )
    ? >= idx 0 { = r ( arc_clone [GkcBuilt] ( vec_at [( Arc GkcBuilt )] . c built idx ) ) } {}
    ( locked_restore [GkcCache] g_gkc_cache c )
    ^ r
}

// A cache entry for `key`, its source to come: its index names the
// kernel's entry point, so two kernels the caller gave one name never
// share a compiled one (the kit caches kernels by entry name).
@ __gkc_reserve s key → i {
    : ~ GkcCache c ( locked_take [GkcCache] g_gkc_cache )
    : i idx ( vec_len [String] . c keys )
    ( vec_push [String] . c keys ( string_from key ) )
    ( vec_push [( Arc GkcBuilt )] . c built ( __gkc_none ) )
    ( locked_restore [GkcCache] g_gkc_cache c )
    ^ idx
}

// Record what entry `idx` built, and hand it back.
@ __gkc_store i idx sink String src sink String ename b shfl → ( Arc GkcBuilt ) {
    : ( Arc GkcBuilt ) a ( arc_new [GkcBuilt] @ GkcBuilt { src ename shfl } )
    : ~ GkcCache c ( locked_take [GkcCache] g_gkc_cache )
    : b _ok ( vec_set [( Arc GkcBuilt )] . c built idx ( arc_clone [GkcBuilt] a ) )
    ( locked_restore [GkcCache] g_gkc_cache c )
    ^ a
}

// The entry point of cache entry `idx`: `kname__gkc<idx>`.
@ __gkc_entry s kname i idx → String {
    : ~ String e ( string_from kname )
    ( string_push_str e `__gkc` ) ( string_push_int e idx )
    ^ e
}

// ── The subset ────────────────────────────────────────────────────────

// Why the last gk_run_checked over `c` refused its kernel ("" when it did not).
@ gk_checked_error GkCall c → s { ^ ( string_data . c err ) }

@ __gkc_alpha i c → b { ^ | | & >= c 97 <= c 122 & >= c 65 <= c 90 == c 95 }

@ __gkc_digit i c → b { ^ & >= c 48 <= c 57 }

// The math a body may call.
@ __gkc_callable s w → b {
    ? ( __gkc_word_in `LD ST if for while switch return sizeof min max abs fabs fabsf sqrt sqrtf rsqrt rsqrtf exp expf exp2 exp2f expm1 log logf log2 log2f log1p log1pf log10 sin sinf cos cosf tan tanf tanh tanhf sinh cosh atan atanf atan2 atan2f asin acos pow powf fmin fminf fmax fmaxf floor floorf ceil ceilf round roundf trunc truncf fmod fmodf erf erff erfc erfcf isnan isinf isfinite copysign copysignf __dadd_rn __dsub_rn __dmul_rn __ddiv_rn __fadd_rn __fsub_rn __fmul_rn __fdiv_rn __fsqrt_rn __dsqrt_rn SYNC SHARED_D SHARED_F SHARED_L SHFL_DOWN SHFL_XOR LOCAL_D LOCAL_F LOCAL_L LD16 LD32 LD4 F16 BF16 WIN WINS LEN WIN2 LD2 ST2 ROWS COLS` w ) { ^ T } {}
    ^ ( __gkc_type w )
}

@ __gkc_type s w → b {
    ^ ( __gkc_word_in `float double int long short char unsigned signed bool void auto const size_t` w )
}

// Names a body may not use at all.
@ __gkc_banned s w → b {
    ? ( __gkc_word_in `asm goto typedef struct union class template typename new delete operator this extern static register namespace using reinterpret_cast const_cast static_cast dynamic_cast decltype alignas volatile nullptr NULL` w ) { ^ T } {}
    // gpukit's own names, and every reserved one, bar the intrinsics
    : ( Slice u ) wv ( slice_of_str w )
    ? & >= ( slice_len [u] wv ) 2 & == ( slice_byte wv 0 ) 95 == ( slice_byte wv 1 ) 95 {
        ^ ! ( __gkc_word_in `__dadd_rn __dsub_rn __dmul_rn __ddiv_rn __fadd_rn __fsub_rn __fmul_rn __fdiv_rn __fsqrt_rn __dsqrt_rn` w )
    } {}
    ^ F
}

// The reason a body is refused, `at` the offending name or character.
@ __gkc_why s why s at → String {
    : ~ String o ( string_from why )
    ? != 0 ( nurl_str_len at ) { ( string_push_str o `: ` ) ( string_push_str o at ) } {}
    ^ o
}

// `body` with ` = 0` after each local declared without a value (`inits`,
// byte offsets, ascending).
@ __gkc_with_inits s body ( Vec i ) inits → String {
    : ( Slice u ) b ( slice_of_str body )
    : i n ( slice_len [u] b )
    : ~ String o ( string_with_cap + n * 4 ( vec_len [i] inits ) )
    : ~ i at 0
    : ~ i q 0
    : i m ( vec_len [i] inits )
    ~ < q m {
        : i p ( vec_at [i] inits q )
        ( string_push_window o b at - p at )
        ( string_push_str o ` = 0` )
        = at p
        = q + q 1
    }
    ( string_push_window o b at - n at )
    ^ o
}

// Is `body` inside the subset? `bufs` lists the buffer names LD / ST may
// take (outputs also in `outs`, byte buffers — LD16 / LD32 — in `wbufs`,
// the f32 buffers LD4 may read in `f4bufs`).
@ __gkc_check s body s bufs s outs s wbufs s f4bufs s w2 inout ( Vec i ) inits → String {
    : ( Slice u ) b ( slice_of_str body )
    : i n ( slice_len [u] b )
    : ~ i k 0
    // what came before the current token: 0 start/operator, 1 operand
    // (a name, a number, `)`), 2 a type name
    : ~ i prev 0
    : ~ i paren 0
    : ~ i brace 0
    // LD / ST just seen: its first argument must be a buffer
    : ~ i want_buf 0
    // a declaration's paren depth (-1 outside one), and whether the next
    // name declares (after its type, or a `,` of the declaration)
    : ~ i decl -1
    : ~ b want_decl F
    ~ < k n {
        : i c ( slice_byte b k )
        ? | | == c 32 == c 10 | | == c 9 == c 13 == c 12 {
            = k + k 1
            continue
        } {}
        // comments
        ? & == c 47 < + k 1 n {
            : i d ( slice_byte b + k 1 )
            ? == d 47 { ~ & < k n != ( slice_byte b k ) 10 { = k + k 1 } continue } {}
            ? == d 42 {
                = k + k 2
                ~ & < + k 1 n ! & == ( slice_byte b k ) 42 == ( slice_byte b + k 1 ) 47 { = k + k 1 }
                ? >= + k 1 n { ^ ( __gkc_why `unterminated comment` `` ) } {}
                = k + k 2
                continue
            } {}
        } {}
        ? ( __gkc_alpha c ) {
            : i s0 k
            ~ & < k n | ( __gkc_alpha ( slice_byte b k ) ) ( __gkc_digit ( slice_byte b k ) ) { = k + k 1 }
            : String w ( __gkc_sub b s0 k )
            : s ws ( string_data w )
            ? ( __gkc_banned ws ) { ^ ( __gkc_why `name not allowed in a checked kernel` ws ) } {}
            // UNROLL is a hint on the loop right after it, nothing else
            ? ( __gkc_eq ws `UNROLL` ) {
                : ~ i j1 k
                ~ & < j1 n <= ( slice_byte b j1 ) 32 { = j1 + j1 1 }
                ? & & < + j1 2 n & == ( slice_byte b j1 ) 102 == ( slice_byte b + j1 1 ) 111 & == ( slice_byte b + j1 2 ) 114 | >= + j1 3 n ! | ( __gkc_alpha ( slice_byte b + j1 3 ) ) ( __gkc_digit ( slice_byte b + j1 3 ) ) {} { ^ ( __gkc_why `UNROLL goes right before a for loop` ws ) }
            } {}
            // A local declared without a value gets 0 (`inits`: where the
            // ` = 0` goes) — a C local read before it is given one is
            // undefined behaviour, not just a stale number.
            ? & ! ( __gkc_type ws ) | want_decl == prev 2 {
                : ~ i j0 k
                ~ & < j0 n <= ( slice_byte b j0 ) 32 { = j0 + j0 1 }
                : i nc ? < j0 n ( slice_byte b j0 ) 0
                ? | want_decl & != nc 40 & != nc 41 != nc 42 {
                    ? & == nc 61 ! & < + j0 1 n == ( slice_byte b + j0 1 ) 61 {} { ( vec_push [i] inits k ) }
                    = decl paren
                    = want_decl F
                } {}
            } {}
            ? > want_buf 0 {
                ? ! ( __gkc_word_in bufs ws ) { ^ ( __gkc_why `LD / ST takes a buffer of this call` ws ) } {}
                // a 2-D window is read with LD2 / ST2, and only one is
                : b two | == want_buf 5 == want_buf 6
                ? & two ! ( __gkc_word_in w2 ws ) { ^ ( __gkc_why `LD2 / ST2 take a 2-D window (WIN2)` ws ) } {}
                ? & ! two ( __gkc_word_in w2 ws ) { ^ ( __gkc_why `a 2-D window is read with LD2 / ST2` ws ) } {}
                ? & == want_buf 6 ! ( __gkc_word_in outs ws ) { ^ ( __gkc_why `ST2 into a window of a buffer that is not an output` ws ) } {}
                ? & == want_buf 2 ! ( __gkc_word_in outs ws ) { ^ ( __gkc_why `ST into a buffer that is not an output` ws ) } {}
                ? & == want_buf 3 ! ( __gkc_word_in wbufs ws ) { ^ ( __gkc_why `LD16 / LD32 read a byte buffer (gk_call_bytes_in)` ws ) } {}
                ? & == want_buf 4 ! ( __gkc_word_in f4bufs ws ) { ^ ( __gkc_why `LD4 reads an f32 device buffer that starts 16-byte aligned and holds at least 4 elements` ws ) } {}
                = want_buf 0
            } {}
            // a call: only LD / ST and the math list
            : ~ i j k
            ~ & < j n | == ( slice_byte b j ) 32 | == ( slice_byte b j ) 9 == ( slice_byte b j ) 10 { = j + j 1 }
            ? & < j n == ( slice_byte b j ) 40 {
                ? ( __gkc_callable ws ) {} { ^ ( __gkc_why `call to a function outside the checked list` ws ) }
                ? ( __gkc_eq ws `LD` ) { = want_buf 1 } {}
                ? ( __gkc_eq ws `ST` ) { = want_buf 2 } {}
                ? | ( __gkc_eq ws `LD16` ) ( __gkc_eq ws `LD32` ) { = want_buf 3 } {}
                ? ( __gkc_eq ws `LD4` ) { = want_buf 4 } {}
                ? ( __gkc_eq ws `LD2` ) { = want_buf 5 } {}
                ? ( __gkc_eq ws `ST2` ) { = want_buf 6 } {}
            } {}
            = prev ? ( __gkc_type ws ) 2 ? ( __gkc_word_in `return` ws ) 0 1
            continue
        } {}
        ? ( __gkc_digit c ) {
            // a number: digits, `.`, an exponent and its sign, x/X, suffixes
            ~ & < k n | | ( __gkc_digit ( slice_byte b k ) ) ( __gkc_alpha ( slice_byte b k ) ) | == ( slice_byte b k ) 46 & | == ( slice_byte b k ) 43 == ( slice_byte b k ) 45 | == ( slice_byte b - k 1 ) 101 == ( slice_byte b - k 1 ) 69 { = k + k 1 }
            = prev 1
            continue
        } {}
        // `.5`
        ? & == c 46 & < + k 1 n ( __gkc_digit ( slice_byte b + k 1 ) ) {
            = k + k 1
            ~ & < k n | | ( __gkc_digit ( slice_byte b k ) ) ( __gkc_alpha ( slice_byte b k ) ) | == ( slice_byte b k ) 46 & | == ( slice_byte b k ) 43 == ( slice_byte b k ) 45 | == ( slice_byte b - k 1 ) 101 == ( slice_byte b - k 1 ) 69 { = k + k 1 }
            = prev 1
            continue
        } {}
        ? | | | == c 35 == c 34 == c 39 | | == c 91 == c 93 | == c 46 == c 92 { ^ ( __gkc_why `character not allowed in a checked kernel` ( string_data ( __gkc_char c ) ) ) } {}
        ? | | == c 64 == c 36 == c 96 { ^ ( __gkc_why `character not allowed in a checked kernel` ( string_data ( __gkc_char c ) ) ) } {}
        ? & == c 45 & < + k 1 n == ( slice_byte b + k 1 ) 62 { ^ ( __gkc_why `member access through a pointer` `->` ) } {}
        // `*`: only between two operands (a product), never after a type
        ? == c 42 {
            ? & == prev 1 ! & < + k 1 n == ( slice_byte b + k 1 ) 41 {} { ^ ( __gkc_why `a pointer type or dereference` `*` ) }
            = k + k 1
            ? & < k n == ( slice_byte b k ) 61 { = k + k 1 } {}  // *=
            = prev 0
            continue
        } {}
        // `&`: `&&`, `&=`, or between two operands; never an address
        ? == c 38 {
            ? & < + k 1 n == ( slice_byte b + k 1 ) 38 { = k + k 2 = prev 0 continue } {}
            ? == prev 1 {} { ^ ( __gkc_why `taking an address` `&` ) }
            = k + k 1
            ? & < k n == ( slice_byte b k ) 61 { = k + k 1 } {}
            = prev 0
            continue
        } {}
        ? == c 40 { = paren + paren 1 = prev 0 = k + k 1 continue } {}
        ? == c 41 { = paren - paren 1 ? < paren 0 { ^ ( __gkc_why `unbalanced )` `` ) } {} ? < paren decl { = decl -1 } {} = prev 1 = k + k 1 continue } {}
        ? == c 59 { = decl -1 = want_decl F = prev 0 = k + k 1 continue } {}
        ? & == c 44 == paren decl { = want_decl T = prev 0 = k + k 1 continue } {}
        ? == c 123 { = brace + brace 1 = prev 0 = k + k 1 continue } {}
        ? == c 125 { = brace - brace 1 ? < brace 0 { ^ ( __gkc_why `unbalanced }` `` ) } {} = prev 0 = k + k 1 continue } {}
        // any other operator or punctuation
        ? ( __gkc_word_in `43 45 47 37 61 60 62 33 126 94 124 63 58 59 44` ( nurl_str_int c ) ) { = prev 0 = k + k 1 continue } {}
        ^ ( __gkc_why `character not allowed in a checked kernel` ( string_data ( __gkc_char c ) ) )
    }
    ? | != paren 0 != brace 0 { ^ ( __gkc_why `unbalanced ( ) or { } in the kernel body` `` ) } {}
    ^ ( string_new )
}

// A name a binding may have: a plain identifier, not reserved.
@ __gkc_name_ok s w → b {
    : ( Slice u ) wv ( slice_of_str w )
    : i n ( slice_len [u] wv )
    ? == n 0 { ^ F } {}
    ? ( __gkc_alpha ( slice_byte wv 0 ) ) {} { ^ F }
    : ~ i k 1
    ~ < k n { ? | ( __gkc_alpha ( slice_byte wv k ) ) ( __gkc_digit ( slice_byte wv k ) ) {} { ^ F } = k + k 1 }
    ? | | ( __gkc_banned w ) ( __gkc_callable w ) ( __gkc_word_in `gid nthreads tid bid bdim nblocks UNROLL` w ) { ^ F } {}
    ^ T
}

@ __gkc_ty i kind → s { ? ( __gkc_isf kind ) { ^ `double` } {} ^ `long long` }

// An f64 binding (input, output or view)?
@ __gkc_isf i kind → b { ^ | | | == kind 0 == kind 1 == kind 6 == kind 10 }

// The length binding `k` is bound with (-1: a scalar).
@ __gkc_blen GkCall c i k → i {
    : i kd ( vec_at [i] . c kinds k )
    : i sl ( vec_at [i] . c slots k )
    ? | == kd 0 == kd 1 { ^ ( vec_len [f] ( vec_at [( Vec f )] . c fv sl ) ) } {}
    ? | == kd 2 == kd 3 { ^ ( vec_len [i] ( vec_at [( Vec i )] . c iv sl ) ) } {}
    ? | == kd 6 == kd 10 { ^ ( slice_len [f] ( vec_at [( Slice f )] . c fs sl ) ) } {}
    ? | == kd 7 == kd 11 { ^ ( slice_len [i] ( vec_at [( Slice i )] . c is sl ) ) } {}
    ^ -1
}

// Which length each buffer's checks compare against: the first buffer bound
// with the same length (its own index when none before it is). Buffers of
// one length share one bound, so a kernel indexing several of them by one
// index (a tree's parallel node arrays) checks that index once.
@ __gkc_groups GkCall c → ( Vec i ) {
    : i nb ( vec_len [String] . c names )
    : ~ ( Vec i ) g ( vec_with_cap [i] nb )
    : ~ i k 0
    ~ < k nb {
        : i ln ( __gkc_blen c k )
        : ~ i r k
        ? >= ln 0 {
            : ~ i j 0
            ~ < j k { ? == ( __gkc_blen c j ) ln { = r j = j k } { = j + j 1 } }
        } {}
        ( vec_push [i] g r )
        = k + k 1
    }
    ^ g
}

// The accessors every checked kernel's source starts with. A load is
// clamped into its buffer: an index outside it reads the buffer's LAST
// element, never memory past it (an empty binding is one zero element).
// On a GPU the clamp is the cheap form; the `32` loads, used when every
// buffer of a launch has 1 to 2^32 - 1 elements, clamp with one 32-bit
// min of the index's low half (64-bit arithmetic there kept a loop's loads
// from being strength-reduced and ran a convolution 1.8x slower) — the same
// last element for any index below 2^32 either way, and still an element of
// the buffer beyond it. A store outside its buffer does nothing.
@ __gkc_header → s {
    ^ `#ifndef __GK_CHECKED_H
#define __GK_CHECKED_H
#ifdef __CUDACC__
static __device__ inline double __gk_ldd(const double* p, long long n, long long i) { return p[(unsigned long long)i < (unsigned long long)n ? i : (n > 0 ? n - 1 : 0)]; }
static __device__ inline float __gk_ldf(const float* p, long long n, long long i) { return p[(unsigned long long)i < (unsigned long long)n ? i : (n > 0 ? n - 1 : 0)]; }
static __device__ inline long long __gk_ldl(const long long* p, long long n, long long i) { return p[(unsigned long long)i < (unsigned long long)n ? i : (n > 0 ? n - 1 : 0)]; }
static __device__ inline double __gk_ldd32(const double* p, long long n, long long i) { return p[min((unsigned)i, (unsigned)n - 1u)]; }
static __device__ inline float __gk_ldf32(const float* p, long long n, long long i) { return p[min((unsigned)i, (unsigned)n - 1u)]; }
static __device__ inline long long __gk_ldl32(const long long* p, long long n, long long i) { return p[min((unsigned)i, (unsigned)n - 1u)]; }
static __device__ inline float __gk_h2f(unsigned short h) { float f; asm("cvt.f32.f16 %0, %1;" : "=f"(f) : "h"(h)); return f; }
static __device__ inline float __gk_b2f(unsigned short h) { return __uint_as_float(((unsigned int)h) << 16); }
static __device__ inline float __gk_ldh(const unsigned short* p, long long n, long long i) { return __gk_h2f(p[(unsigned long long)i < (unsigned long long)n ? i : (n > 0 ? n - 1 : 0)]); }
static __device__ inline float __gk_ldb(const unsigned short* p, long long n, long long i) { return __gk_b2f(p[(unsigned long long)i < (unsigned long long)n ? i : (n > 0 ? n - 1 : 0)]); }
static __device__ inline float __gk_ldh32(const unsigned short* p, long long n, long long i) { return __gk_h2f(p[min((unsigned)i, (unsigned)n - 1u)]); }
static __device__ inline float __gk_ldb32(const unsigned short* p, long long n, long long i) { return __gk_b2f(p[min((unsigned)i, (unsigned)n - 1u)]); }
#define UNROLL _Pragma("unroll")
#define __GK_ASSUME(c) __builtin_assume(c)
#else
__attribute__((noinline, cold)) static double __gk_ldd0(const double* p, long long n) { return p[n > 0 ? n - 1 : 0]; }
__attribute__((noinline, cold)) static float __gk_ldf0(const float* p, long long n) { return p[n > 0 ? n - 1 : 0]; }
__attribute__((noinline, cold)) static long long __gk_ldl0(const long long* p, long long n) { return p[n > 0 ? n - 1 : 0]; }
static inline double __gk_ldd(const double* p, long long n, long long i) { if (__builtin_expect((unsigned long long)i >= (unsigned long long)n, 0)) return __gk_ldd0(p, n); return p[i]; }
static inline float __gk_ldf(const float* p, long long n, long long i) { if (__builtin_expect((unsigned long long)i >= (unsigned long long)n, 0)) return __gk_ldf0(p, n); return p[i]; }
static inline long long __gk_ldl(const long long* p, long long n, long long i) { if (__builtin_expect((unsigned long long)i >= (unsigned long long)n, 0)) return __gk_ldl0(p, n); return p[i]; }
#define __gk_ldd32 __gk_ldd
#define __gk_ldf32 __gk_ldf
#define __gk_ldl32 __gk_ldl
// (the host's: from a 32-bit word — on 16-bit registers the shifts and masks
// stall on partial-register merges, 1.17x the cost)
static inline float __gk_h2f(unsigned int h) {
    unsigned int sign = (h >> 15) << 31, e = (h >> 10) & 31u, m = h & 1023u, bits;
    if (e == 0u) {
        if (m == 0u) bits = sign;
        else { int ex = 113; while (!(m & 1024u)) { m <<= 1; ex--; } bits = sign | ((unsigned int)ex << 23) | ((m & 1023u) << 13); }
    } else if (e == 31u) bits = sign | 0x7F800000u | (m << 13);
    else bits = sign | ((e + 112u) << 23) | (m << 13);
    union { unsigned int u; float f; } c; c.u = bits; return c.f;
}
static inline float __gk_b2f(unsigned short h) { union { unsigned int u; float f; } c; c.u = ((unsigned int)h) << 16; return c.f; }
__attribute__((noinline, cold)) static unsigned short __gk_ldu0(const unsigned short* p, long long n) { return p[n > 0 ? n - 1 : 0]; }
static inline float __gk_ldh(const unsigned short* p, long long n, long long i) { if (__builtin_expect((unsigned long long)i >= (unsigned long long)n, 0)) return __gk_h2f(__gk_ldu0(p, n)); return __gk_h2f(p[i]); }
static inline float __gk_ldb(const unsigned short* p, long long n, long long i) { if (__builtin_expect((unsigned long long)i >= (unsigned long long)n, 0)) return __gk_b2f(__gk_ldu0(p, n)); return __gk_b2f(p[i]); }
#define __gk_ldh32 __gk_ldh
#define __gk_ldb32 __gk_ldb
#define UNROLL
#define __GK_ASSUME(c) do { if (!(c)) __builtin_unreachable(); } while (0)
#endif
static __device__ inline void __gk_std(double* p, long long n, long long i, double v) { if ((unsigned long long)i < (unsigned long long)n) p[i] = v; }
static __device__ inline void __gk_stf(float* p, long long n, long long i, float v) { if ((unsigned long long)i < (unsigned long long)n) p[i] = v; }
static __device__ inline void __gk_stl(long long* p, long long n, long long i, long long v) { if ((unsigned long long)i < (unsigned long long)n) p[i] = v; }
static __device__ inline void __gk_stu8(unsigned char* p, long long n, long long i, unsigned int v) { if ((unsigned long long)i < (unsigned long long)n) p[i] = (unsigned char)v; }
#ifdef __CUDACC__
static __device__ inline void __gk_stu8_32(unsigned char* p, long long n, long long i, unsigned int v) { if ((unsigned)i < (unsigned)n) p[(unsigned)i] = (unsigned char)v; }
#else
#define __gk_stu8_32 __gk_stu8
#endif
// A window's index, evaluated once (an index may have a side effect):
// its own inside the window, else 0; a store outside it is dropped.
// Compared signed, inside a lambda the compiler inlines before it looks at
// the loop, so a loop counted to LEN folds the check away — an unsigned
// compare, or the same compare in a helper function, stays in the loop.
#define __GK_WI(i, l) ([&]() { long long __gk_k = (long long)(i); return (__gk_k >= 0 && __gk_k < (l)) ? __gk_k : 0LL; }())
#define __GK_WST(p, o, l, s, i, v) ([&]() { long long __gk_k = (long long)(i); auto __gk_v = (v); if (__gk_k >= 0 && __gk_k < (l)) (p)[(o) + __gk_k * (s)] = __gk_v; }())
#define __GK_WST2(p, o, nr, s, nc, r, c, v) ([&]() { long long __gk_r = (long long)(r); long long __gk_c = (long long)(c); auto __gk_v = (v); if (__gk_r >= 0 && __gk_r < (nr) && __gk_c >= 0 && __gk_c < (nc)) (p)[(o) + __gk_r * (s) + __gk_c] = __gk_v; }())
#ifdef __CUDACC__
static __device__ inline unsigned int __gk_ldu8(const unsigned char* p, long long n, long long i) { return p[(unsigned long long)i < (unsigned long long)n ? i : n - 1]; }
static __device__ inline unsigned int __gk_ldu16(const unsigned char* p, long long n, long long i) { unsigned long long w = (unsigned long long)i >> 1, m = (unsigned long long)n >> 1; return ((const unsigned short*)p)[w < m ? w : m - 1]; }
static __device__ inline unsigned int __gk_ldu32(const unsigned char* p, long long n, long long i) { unsigned long long w = (unsigned long long)i >> 2, m = (unsigned long long)n >> 2; return ((const unsigned int*)p)[w < m ? w : m - 1]; }
#else
// (the host's: a predicted branch, the out-of-range side a cold call, as
// LD's — a select would lengthen every dependent chain)
__attribute__((noinline, cold)) static unsigned int __gk_ldu8_0(const unsigned char* p, long long n) { return p[n - 1]; }
__attribute__((noinline, cold)) static unsigned int __gk_ldu16_0(const unsigned char* p, long long n) { return ((const unsigned short*)p)[((unsigned long long)n >> 1) - 1]; }
__attribute__((noinline, cold)) static unsigned int __gk_ldu32_0(const unsigned char* p, long long n) { return ((const unsigned int*)p)[((unsigned long long)n >> 2) - 1]; }
static inline unsigned int __gk_ldu8(const unsigned char* p, long long n, long long i) { if (__builtin_expect((unsigned long long)i >= (unsigned long long)n, 0)) return __gk_ldu8_0(p, n); return p[i]; }
static inline unsigned int __gk_ldu16(const unsigned char* p, long long n, long long i) { unsigned long long w = (unsigned long long)i >> 1; if (__builtin_expect(w >= ((unsigned long long)n >> 1), 0)) return __gk_ldu16_0(p, n); return ((const unsigned short*)p)[w]; }
static inline unsigned int __gk_ldu32(const unsigned char* p, long long n, long long i) { unsigned long long w = (unsigned long long)i >> 2; if (__builtin_expect(w >= ((unsigned long long)n >> 2), 0)) return __gk_ldu32_0(p, n); return ((const unsigned int*)p)[w]; }
#endif
#ifdef __CUDACC__
static __device__ inline unsigned int __gk_ldu8_32(const unsigned char* p, long long n, long long i) { return p[min((unsigned)i, (unsigned)n - 1u)]; }
static __device__ inline unsigned int __gk_ldu16_32(const unsigned char* p, long long n, long long i) { return ((const unsigned short*)p)[min((unsigned)i >> 1, ((unsigned)n >> 1) - 1u)]; }
static __device__ inline unsigned int __gk_ldu32_32(const unsigned char* p, long long n, long long i) { return ((const unsigned int*)p)[min((unsigned)i >> 2, ((unsigned)n >> 2) - 1u)]; }
#else
#define __gk_ldu8_32 __gk_ldu8
#define __gk_ldu16_32 __gk_ldu16
#define __gk_ldu32_32 __gk_ldu32
#endif
#define LD16(b, i) __GK_LD16_##b(i)
#define LD32(b, i) __GK_LD32_##b(i)
#define LD4(b, i, a0, a1, a2, a3) __GK_LD4_##b(i, a0, a1, a2, a3)
#define WIN(w, b, off, len) long long __gk_wo_##w = (long long)(off); long long __gk_wl_##w = (long long)(len); long long __gk_ws_##w = 1; __GK_WCHK_##b(__gk_wo_##w, __gk_wl_##w, __gk_ws_##w)
#define WINS(w, b, off, len, st) long long __gk_wo_##w = (long long)(off); long long __gk_wl_##w = (long long)(len); long long __gk_ws_##w = (long long)(st); __GK_WCHK_##b(__gk_wo_##w, __gk_wl_##w, __gk_ws_##w)
#define LEN(w) __gk_wl_##w
#define WIN2(w, b, off, nr, st, nc) long long __gk_wo_##w = (long long)(off); long long __gk_wr_##w = (long long)(nr); long long __gk_ws_##w = (long long)(st); long long __gk_wc_##w = (long long)(nc); __GK_WCHK2_##b(__gk_wo_##w, __gk_wr_##w, __gk_ws_##w, __gk_wc_##w)
#define ROWS(w) __gk_wr_##w
#define COLS(w) __gk_wc_##w
#define LD2(w, r, c) __GK_LD2_##w(r, c)
#define ST2(w, r, c, v) __GK_ST2_##w(r, c, v)
#define F16(h) __gk_h2f((unsigned short)(h))
#ifdef __CUDACC__
#define __GK_LD4N(p, n, i, a0, a1, a2, a3) do { float4 __gk_v = ((const float4*)(p))[min((unsigned)((i) >> 2), ((unsigned)(n) >> 2) - 1u)]; (a0) = __gk_v.x; (a1) = __gk_v.y; (a2) = __gk_v.z; (a3) = __gk_v.w; } while (0)
#define __GK_LD4W(p, n, i, a0, a1, a2, a3) do { unsigned long long __gk_g = (unsigned long long)(i) >> 2, __gk_m = (unsigned long long)(n) >> 2; float4 __gk_v = ((const float4*)(p))[__gk_g < __gk_m ? __gk_g : __gk_m - 1]; (a0) = __gk_v.x; (a1) = __gk_v.y; (a2) = __gk_v.z; (a3) = __gk_v.w; } while (0)
#else
__attribute__((noinline, cold)) static const float* __gk_ld4_0(const float* p, long long n) { return p + 4 * (((unsigned long long)n >> 2) - 1); }
#define __GK_LD4W(p, n, i, a0, a1, a2, a3) do { unsigned long long __gk_g = (unsigned long long)(i) >> 2; const float* __gk_q = __builtin_expect(__gk_g < ((unsigned long long)(n) >> 2), 1) ? (p) + 4 * __gk_g : __gk_ld4_0((p), (n)); (a0) = __gk_q[0]; (a1) = __gk_q[1]; (a2) = __gk_q[2]; (a3) = __gk_q[3]; } while (0)
#define __GK_LD4N __GK_LD4W
#endif
#define BF16(h) __gk_b2f((unsigned short)(h))
#ifdef __CUDACC__
static __device__ inline void __gk_std32(double* p, long long n, long long i, double v) { if ((unsigned)i < (unsigned)n) p[(unsigned)i] = v; }
static __device__ inline void __gk_stf32(float* p, long long n, long long i, float v) { if ((unsigned)i < (unsigned)n) p[(unsigned)i] = v; }
static __device__ inline void __gk_stl32(long long* p, long long n, long long i, long long v) { if ((unsigned)i < (unsigned)n) p[(unsigned)i] = v; }
#else
#define __gk_std32 __gk_std
#define __gk_stf32 __gk_stf
#define __gk_stl32 __gk_stl
#endif
#define LD(b, i) __GK_LD_##b(i)
#define ST(b, i, v) __GK_ST_##b(i, v)
#define LOCAL_D(nm, N) __GK_LC_##nm
#define LOCAL_F(nm, N) __GK_LC_##nm
#define LOCAL_L(nm, N) __GK_LC_##nm
#endif
`
}

// The declaration, LD and ST of each per-thread array (`lcn` names, `lct`
// types 0 double / 1 float / 2 long long, `lcz` sizes).
@ __gkc_local_src inout String src ( Vec String ) lcn ( Vec i ) lct ( Vec i ) lcz → v {
    : ~ i k 0
    ~ < k ( vec_len [String] lcn ) {
        : s nm ( string_data ( vec_at [String] lcn k ) )
        : i dt ( vec_at [i] lct k )
        : i z ( vec_at [i] lcz k )
        ( string_push_str src `#undef __GK_LC_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_LC_` ) ( string_push_str src nm )
        ( string_push_char src 32 ) ( string_push_str src ( __gkc_dty dt ) ) ( string_push_str src ` __gk_lc_` ) ( string_push_str src nm )
        ( string_push_char src 91 ) ( string_push_int src z ) ( string_push_char src 93 ) ( string_push_str src ` = {}\n` )
        ( string_push_str src `#undef __GK_LD_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_LD_` ) ( string_push_str src nm ) ( string_push_str src `(i) ` )
        ( string_push_str src ( __gkc_dld dt T ) ) ( string_push_str src `(__gk_lc_` ) ( string_push_str src nm ) ( string_push_str src `, ` ) ( string_push_int src z ) ( string_push_str src `, (long long)(i))\n` )
        ( string_push_str src `#undef __GK_ST_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_ST_` ) ( string_push_str src nm ) ( string_push_str src `(i, v) ` )
        ( string_push_str src ( __gkc_dst dt T ) ) ( string_push_str src `(__gk_lc_` ) ( string_push_str src nm ) ( string_push_str src `, ` ) ( string_push_int src z ) ( string_push_str src `, (long long)(i), (v))\n` )
        = k + k 1
    }
}

// The per-thread arrays of `toks` into lcn / lct / lcz, and their names
// onto what LD / ST may take (`bufs`, `outs`): "" or why not.
@ __gkc_add_locals ( Vec String ) toks inout ( Vec String ) lcn inout ( Vec i ) lct inout ( Vec i ) lcz inout String bufs inout String outs → String {
    : String e ( __gkc_locals toks lcn lct lcz )
    ? > ( string_len e ) 0 { ^ e } {}
    : ~ i k 0
    ~ < k ( vec_len [String] lcn ) {
        : s ln ( string_data ( vec_at [String] lcn k ) )
        ? ( __gkc_word_in ( string_data bufs ) ln ) { ^ ( __gkc_why `an array named like a binding or another array` ln ) } {}
        ( string_push_char bufs 32 ) ( string_push_str bufs ln )
        ( string_push_char outs 32 ) ( string_push_str outs ln )
        = k + k 1
    }
    ^ ( string_new )
}

// Does every buffer of the launch (lengths in `lens`, -1 for a scalar) fit
// the 32-bit loads: 1 to 2^32 - 1 elements? (An empty one keeps the 64-bit
// load, whose clamp tests for it.)
@ __gkc_narrow ( Vec i ) lens → b {
    : ~ i k 0
    ~ < k ( vec_len [i] lens ) {
        : i ln ( vec_at [i] lens k )
        ? | == ln 0 > ln 4294967295 { ^ F } {}
        = k + k 1
    }
    ^ T
}

// The full source: the per-buffer accessors, then the kernel around `body`.
// (On the host a load's check is a branch the CPU predicts, its
// out-of-range side a cold call — no select the compiler could fold it
// into: a select would sit on every dependent load chain, a tree walk's,
// as a predicted branch does not. On a GPU the select is the cheap form.)
@ __gkc_source GkCall c ( Vec i ) grp s kname s body b narrow ( Vec String ) lcn ( Vec i ) lct ( Vec i ) lcz → String {
    : ~ String src ( string_from ( __gkc_header ) )
    : i nb ( vec_len [String] . c names )
    : ~ i k 0
    ~ < k nb {
        : s nm ( string_data ( vec_at [String] . c names k ) )
        : i kd ( vec_at [i] . c kinds k )
        : String ks ( string_from ( nurl_str_int k ) )
        : String gs ( string_from ( nurl_str_int ( vec_at [i] grp k ) ) )
        ? | < kd 4 > kd 5 {
            ( string_push_str src `#undef __GK_LD_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_LD_` ) ( string_push_str src nm )
            ( string_push_str src ? ( __gkc_isf kd ) `(i) __gk_ldd` `(i) __gk_ldl` )
            ( string_push_str src ? narrow `32(__gk_p` `(__gk_p` )
            ( string_push_str src ( string_data ks ) ) ( string_push_str src `, __gk_n` ) ( string_push_str src ( string_data gs ) )
            ( string_push_str src `, (long long)(i))\n` )
            ? | | == kd 1 == kd 3 | == kd 10 == kd 11 {
                ( string_push_str src `#undef __GK_ST_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_ST_` ) ( string_push_str src nm )
                ( string_push_str src ? ( __gkc_isf kd ) `(i, v) __gk_std(__gk_p` `(i, v) __gk_stl(__gk_p` )
                ( string_push_str src ( string_data ks ) ) ( string_push_str src `, __gk_n` ) ( string_push_str src ( string_data gs ) )
                ( string_push_str src `, (long long)(i), (v))\n` )
            } {}
        } {}
        = k + k 1
    }
    ( __gkc_local_src src lcn lct lcz )
    ( string_push_str src `extern "C" __global__ void ` ) ( string_push_str src kname ) ( string_push_char src 40 )
    = k 0
    ~ < k nb {
        : s nm ( string_data ( vec_at [String] . c names k ) )
        : i kd ( vec_at [i] . c kinds k )
        : String ks ( string_from ( nurl_str_int k ) )
        ? | < kd 4 > kd 5 {
            ( string_push_str src ? | | == kd 0 == kd 2 | == kd 6 == kd 7 `const ` `` )
            ( string_push_str src ( __gkc_ty kd ) ) ( string_push_str src `* __gk_p` ) ( string_push_str src ( string_data ks ) )
            ( string_push_str src `, long long __gk_n` ) ( string_push_str src ( string_data ks ) )
        } {
            ( string_push_str src ? == kd 4 `long long ` `double ` ) ( string_push_str src nm )
        }
        ( string_push_str src `, ` )
        = k + k 1
    }
    ( string_push_str src `long long __gk_nt) {
long long gid = (long long)blockIdx.x * blockDim.x + threadIdx.x;
if (gid >= __gk_nt) return;
long long nthreads = __gk_nt;
(void)nthreads;
{
` )
    ( string_push_str src body )
    ( string_push_str src `
}
}
` )
    ^ src
}

// Check `body`, build the kernel `kname` around it and run `nthreads`
// threads of it (`block` per block) over `c`'s bindings. An output starts
// on the device as the Vec it was bound with and is copied back into `c`
// (gk_call_take_f / _i): an element the kernel does not write keeps its
// value — never what the device memory held before. F — nothing launched — when
// the body is outside the subset (gk_checked_error says why) or a binding
// is malformed; F as well on a device error.
unsafe @ gk_run_checked GpuKit kit inout GkCall c s kname s body i nthreads i block → b {
    = . c err ( string_new )
    ? | < nthreads 0 < block 1 { = . c err ( __gkc_why `thread count` `` ) ^ F } {}
    : ~ String bufs ( string_new )
    : ~ String outs ( string_new )
    // the cache key: the name, every binding's name and kind, the body
    : ~ String key ( string_from kname )
    : i nb ( vec_len [String] . c names )
    : ~ i k 0
    ~ < k nb {
        : s nm ( string_data ( vec_at [String] . c names k ) )
        : i kd ( vec_at [i] . c kinds k )
        ( string_push_char key 1 ) ( string_push_str key nm ) ( string_push_char key + 48 kd )
        ? | < kd 4 > kd 5 { ( string_push_char bufs 32 ) ( string_push_str bufs nm ) } {}
        ? | | == kd 1 == kd 3 | == kd 10 == kd 11 { ( string_push_char outs 32 ) ( string_push_str outs nm ) } {}
        = k + k 1
    }
    // (…and which buffers share a length: __gkc_groups, and whether the
    // loads are the 32-bit ones.)
    : ( Vec i ) grp ( __gkc_groups c )
    : ~ ( Vec i ) lens ( vec_new [i] )
    = k 0
    ~ < k nb { ( vec_push [i] lens ( __gkc_blen c k ) ) = k + k 1 }
    : b narrow ( __gkc_narrow lens )
    ( string_push_char key ? narrow 110 119 )
    = k 0
    ~ < k nb { ( string_push_char key 3 ) ( string_push_str key ( nurl_str_int ( vec_at [i] grp k ) ) ) = k + k 1 }
    ( string_push_char key 2 ) ( string_push_str key body )
    : ~ i idx -1
    : ~ ( Arc GkcBuilt ) hit ( __gkc_lookup ( string_data key ) idx )
    ? == 0 ( string_len . ( arc_get [GkcBuilt] hit ) src ) {
        // (Checked once: the key holds the name, so a hit had it checked.)
        ? ( __gkc_name_ok kname ) {} { = . c err ( __gkc_why `kernel name` kname ) ^ F }
        = k 0
        ~ < k nb {
            : s nm ( string_data ( vec_at [String] . c names k ) )
            ? ( __gkc_name_ok nm ) {} { = . c err ( __gkc_why `binding name` nm ) ^ F }
            ? >= ( vec_at [i] . c kinds k ) 8 { ? | == ( vec_at [i] . c kinds k ) 10 == ( vec_at [i] . c kinds k ) 11 {} { = . c err ( __gkc_why `a device buffer is launched by gk_run_checked_dev` nm ) ^ F } } {}
            = k + k 1
        }
        : ( Vec String ) toks ( __gkc_toks body )
        : ~ ( Vec String ) lcn ( vec_new [String] )
        : ~ ( Vec i ) lct ( vec_new [i] )
        : ~ ( Vec i ) lcz ( vec_new [i] )
        = . c err ( __gkc_add_locals toks lcn lct lcz bufs outs )
        ? > ( string_len . c err ) 0 { ^ F } {}
        : ~ ( Vec i ) inits ( vec_new [i] )
        = . c err ( __gkc_check body ( string_data bufs ) ( string_data outs ) `` `` `` inits )
        ? > ( string_len . c err ) 0 { ^ F } {}
        ? ( __gkc_coop toks ) { = . c err ( __gkc_why `SYNC(), SHARED_* and SHFL_* need a block launch (gk_run_checked_dev)` `` ) ^ F } {}
        ? < idx 0 { = idx ( __gkc_reserve ( string_data key ) ) } {}
        : String en ( __gkc_entry kname idx )
        : String b2 ( __gkc_with_inits body inits )
        : String nsrc ( __gkc_source c grp ( string_data en ) ( string_data b2 ) narrow lcn lct lcz )
        = hit ( __gkc_store idx nsrc en F )
    } {}
    : GkcBuilt hb ( arc_get [GkcBuilt] hit )
    // the launch: every buffer with its own length, the scalars as given
    : ( Vec GkArg ) call ( vec_new [GkArg] )
    // A load past the end reads an element of its buffer (the check keeps
    // the load itself unconditional), so an empty buffer is bound as one
    // zero element — its length still 0, so nothing is stored into it.
    : ( Vec f ) one_f ( vec_zeroed [f] 1 )
    : ( Vec i ) one_i ( vec_zeroed [i] 1 )
    = k 0
    ~ < k nb {
        : i kd ( vec_at [i] . c kinds k )
        : i sl ( vec_at [i] . c slots k )
        ? | == kd 0 == kd 1 {
            : i ln ( vec_len [f] ( vec_at [( Vec f )] . c fv sl ) )
            ? == ln 0 { ( vec_push [GkArg] call ( gk_in_f one_f ) ) } {
                ( vec_push [GkArg] call ? == kd 0 ( gk_in_f ( vec_at [( Vec f )] . c fv sl ) ) ( gk_inout_f ( vec_at [( Vec f )] . c fv sl ) ) )
            }
            ( vec_push [GkArg] call ( gk_i64 ln ) )
        } {}
        ? | == kd 2 == kd 3 {
            : i ln ( vec_len [i] ( vec_at [( Vec i )] . c iv sl ) )
            ? == ln 0 { ( vec_push [GkArg] call ( gk_in_i one_i ) ) } {
                ( vec_push [GkArg] call ? == kd 2 ( gk_in_i ( vec_at [( Vec i )] . c iv sl ) ) ( gk_inout_i ( vec_at [( Vec i )] . c iv sl ) ) )
            }
            ( vec_push [GkArg] call ( gk_i64 ln ) )
        } {}
        ? == kd 6 {
            : ( Slice f ) sv ( vec_at [( Slice f )] . c fs sl )
            : i ln ( slice_len [f] sv )
            ? == ln 0 { ( vec_push [GkArg] call ( gk_in_f one_f ) ) } { ( vec_push [GkArg] call ( gk_buf_in # *u ( slice_data [f] sv ) * ln 8 ) ) }
            ( vec_push [GkArg] call ( gk_i64 ln ) )
        } {}
        ? == kd 7 {
            : ( Slice i ) sv ( vec_at [( Slice i )] . c is sl )
            : i ln ( slice_len [i] sv )
            ? == ln 0 { ( vec_push [GkArg] call ( gk_in_i one_i ) ) } { ( vec_push [GkArg] call ( gk_buf_in # *u ( slice_data [i] sv ) * ln 8 ) ) }
            ( vec_push [GkArg] call ( gk_i64 ln ) )
        } {}
        // An output view: the kernel writes into the caller's storage — it
        // goes up as it is and comes back after the launch.
        ? == kd 10 {
            : ( Slice f ) sv ( vec_at [( Slice f )] . c fs sl )
            : i ln ( slice_len [f] sv )
            ? == ln 0 { ( vec_push [GkArg] call ( gk_in_f one_f ) ) } { ( vec_push [GkArg] call @ GkArg { 3 # *u ( slice_data [f] sv ) * ln 8 0 } ) }
            ( vec_push [GkArg] call ( gk_i64 ln ) )
        } {}
        ? == kd 11 {
            : ( Slice i ) sv ( vec_at [( Slice i )] . c is sl )
            : i ln ( slice_len [i] sv )
            ? == ln 0 { ( vec_push [GkArg] call ( gk_in_i one_i ) ) } { ( vec_push [GkArg] call @ GkArg { 3 # *u ( slice_data [i] sv ) * ln 8 0 } ) }
            ( vec_push [GkArg] call ( gk_i64 ln ) )
        } {}
        ? == kd 4 { ( vec_push [GkArg] call ( gk_i64 sl ) ) } {}
        ? == kd 5 { ( vec_push [GkArg] call ( gk_i64 sl ) ) } {}
        = k + k 1
    }
    ( vec_push [GkArg] call ( gk_i64 nthreads ) )
    ? == nthreads 0 { ^ T } {}
    ^ ( gk_run kit ( string_data . hb src ) ( string_data . hb ename ) ( gk_grid nthreads block ) block call )
}

// ── Block launches: device buffers, SYNC() and shared arrays ──────────
//
// gk_run_checked_dev launches `nblocks` blocks of `block` threads over
// device buffers (gk_call_dev / gk_call_dev_in) and scalars. The body also
// sees `tid` (the thread within its block), `bid` (the block), `bdim`,
// `nblocks`, `gid` and `nthreads`, and may use
//
//     SYNC()                 every thread of the block waits for the rest
//     SHARED_D(name, N);     N doubles shared by the block (SHARED_F: floats,
//                            SHARED_L: long longs), zeroed when the block
//                            starts, reached through LD / ST like a buffer
//
// A barrier some threads of a block skip is undefined behaviour on a GPU,
// so SYNC() is accepted only where every thread of the block provably
// gets to it: each `if` / `for` / `while` around it decides by values the
// whole block shares — scalars, `bid`, `bdim`, `nblocks`, numbers, loads
// from buffers the kernel only reads at such indices, and locals only ever
// given such values (worked out to a fixpoint). `tid`, `gid` and anything
// read from a written buffer or a shared array are per thread. A body
// with SYNC() or a shared array has no `return`, `break`, `continue`,
// `switch` or `do`, braces every `if` / `for` / `while` / `else` body, and
// declares its shared arrays at its own top level.

// The body's tokens: names and numbers, operators (`<<=` … `+=` `==` as
// one), comments dropped.
@ __gkc_toks s body → ( Vec String ) {
    : ( Slice u ) b ( slice_of_str body )
    : i n ( slice_len [u] b )
    : ~ ( Vec String ) t ( vec_new [String] )
    : ~ i k 0
    ~ < k n {
        : i c ( slice_byte b k )
        ? <= c 32 { = k + k 1 continue } {}
        ? & == c 47 < + k 1 n {
            : i d ( slice_byte b + k 1 )
            ? == d 47 { ~ & < k n != ( slice_byte b k ) 10 { = k + k 1 } continue } {}
            ? == d 42 {
                = k + k 2
                ~ & < + k 1 n ! & == ( slice_byte b k ) 42 == ( slice_byte b + k 1 ) 47 { = k + k 1 }
                = k + k 2
                continue
            } {}
        } {}
        : i s0 k
        ? | ( __gkc_alpha c ) ( __gkc_digit c ) {
            : b num ( __gkc_digit c )
            ~ & < k n | | ( __gkc_alpha ( slice_byte b k ) ) ( __gkc_digit ( slice_byte b k ) ) & num | == ( slice_byte b k ) 46 & | == ( slice_byte b k ) 43 == ( slice_byte b k ) 45 | == ( slice_byte b - k 1 ) 101 == ( slice_byte b - k 1 ) 69 { = k + k 1 }
            ( vec_push [String] t ( __gkc_sub b s0 k ) )
            continue
        } {}
        : ~ i len 1
        ? < + k 2 n {
            : String w3 ( __gkc_sub b k + k 3 )
            ? ( __gkc_word_in `<<= >>=` ( string_data w3 ) ) { = len 3 } {}
        } {}
        ? & == len 1 < + k 1 n {
            : String w2 ( __gkc_sub b k + k 2 )
            ? ( __gkc_word_in `== != <= >= && || ++ -- += -= *= /= %= &= |= ^= << >>` ( string_data w2 ) ) { = len 2 } {}
        } {}
        ( vec_push [String] t ( __gkc_sub b k + k len ) )
        = k + k len
    }
    ^ t
}

// Token `k` ("" past the end).
@ __gkc_ti ( Vec String ) t i k → s {
    ? & >= k 0 < k ( vec_len [String] t ) { ^ ( string_data ( vec_at [String] t k ) ) } {}
    ^ ``
}

@ __gkc_isid s w → b {
    : ( Slice u ) wv ( slice_of_str w )
    ^ & > ( slice_len [u] wv ) 0 ( __gkc_alpha ( slice_byte wv 0 ) )
}

// Does the body cooperate within a block (SYNC(), a shared array or a warp
// shuffle)?
@ __gkc_coop ( Vec String ) t → b {
    : i n ( vec_len [String] t )
    : ~ i k 0
    ~ < k n {
        ? ( __gkc_word_in `SYNC SHARED_D SHARED_F SHARED_L SHFL_DOWN SHFL_XOR` ( __gkc_ti t k ) ) { ^ T } {}
        = k + k 1
    }
    ^ F
}

// Does the body use a warp shuffle? (The launch's blocks are then whole
// warps: a shuffle reads the other 31 lanes of its warp, so all 32 exist.)
@ __gkc_shfl ( Vec String ) t → b {
    : i n ( vec_len [String] t )
    : ~ i k 0
    ~ < k n {
        ? ( __gkc_word_in `SHFL_DOWN SHFL_XOR` ( __gkc_ti t k ) ) { ^ T } {}
        = k + k 1
    }
    ^ F
}

// The `)` that closes the `(` at `open`.
@ __gkc_close ( Vec String ) t i open → i {
    : i n ( vec_len [String] t )
    : ~ i d 0
    : ~ i k open
    ~ < k n {
        : s w ( __gkc_ti t k )
        ? ( __gkc_eq w `(` ) { = d + d 1 } {}
        ? ( __gkc_eq w `)` ) { = d - d 1 ? == d 0 { ^ k } {} } {}
        = k + k 1
    }
    ^ n
}

// The first `;` in [lo, hi) outside parentheses (hi when none).
@ __gkc_semi ( Vec String ) t i lo i hi → i {
    : ~ i d 0
    : ~ i k lo
    ~ < k hi {
        : s w ( __gkc_ti t k )
        ? ( __gkc_eq w `(` ) { = d + d 1 } {}
        ? ( __gkc_eq w `)` ) { = d - d 1 } {}
        ? & == d 0 ( __gkc_eq w `;` ) { ^ k } {}
        = k + k 1
    }
    ^ hi
}

// Where the value assigned at `lo` ends: a `;` or `,` at its own depth, or
// a `)` closing past it.
@ __gkc_expr_end ( Vec String ) t i lo → i {
    : i n ( vec_len [String] t )
    : ~ i d 0
    : ~ i k lo
    ~ < k n {
        : s w ( __gkc_ti t k )
        ? ( __gkc_eq w `(` ) { = d + d 1 } {}
        ? ( __gkc_eq w `)` ) { ? == d 0 { ^ k } {} = d - d 1 } {}
        ? & == d 0 | ( __gkc_eq w `;` ) ( __gkc_eq w `,` ) { ^ k } {}
        = k + k 1
    }
    ^ n
}

// The uniformity walk works on ids: every identifier of the body interned
// once, with per-name flags — per thread, a written buffer, a name a value
// can be given to (not a type, not a callable) — so the question it asks
// of every token in every round is a lookup, not a search of a name list.
: GkcU {
    ( Vec i ) id  // per token: its identifier's id, -1 for anything else
    ( Vec i ) var  // per id: 1 when it can name a variable
    ( Vec i ) per  // per id: 1 when per thread
    ( Vec i ) wr  // per id: 1 when a buffer the kernel writes
    ( Vec i ) kd  // per token: 1 if, 2 while, 3 for, 4 else, 5 {, 6 }, 7 a block-wide op, 8 LD, 0 other
    ( Vec i ) asg  // per token: 1 an assignment operator follows, 2 a ++ / -- beside it
    ( Vec i ) e1  // per token: if / while / for — its ) ; an assignment — its value's end
    ( Vec i ) e2  // per token: for — its first ;
    ( Vec i ) e3  // per token: for — its second ;
}

@ __gkc_u_new ( Vec String ) t s nu s writable → GkcU {
    : i n ( vec_len [String] t )
    : ~ ( HashMap String i ) ix ( map_new [String i] )
    : ~ ( Vec String ) names ( vec_new [String] )
    : ~ ( Vec i ) ids ( vec_with_cap [i] n )
    : ~ i k 0
    ~ < k n {
        : s w ( __gkc_ti t k )
        : ~ i id -1
        ? ( __gkc_isid w ) {
            = id ?? ( map_get_with [String i s] ix w \ s x → i { ^ ( hash_string x ) } \ String a s b → b { ^ ( eq_string ( string_data a ) b ) } ) { T v → v F → -1 }
            ? < id 0 {
                = id ( vec_len [String] names )
                ( vec_push [String] names ( string_from w ) )
                : ?i _o ( map_set [String i] ix ( string_from w ) id \ String x → i { ^ ( hash_string ( string_data x ) ) } \ String a String b → b { ^ ( eq_string ( string_data a ) ( string_data b ) ) } )
            } {}
        } {}
        ( vec_push [i] ids id )
        = k + k 1
    }
    : ~ ( Vec i ) kd ( vec_with_cap [i] n )
    : ~ ( Vec i ) asg ( vec_with_cap [i] n )
    : ~ ( Vec i ) e1 ( vec_with_cap [i] n )
    : ~ ( Vec i ) e2 ( vec_with_cap [i] n )
    : ~ ( Vec i ) e3 ( vec_with_cap [i] n )
    = k 0
    ~ < k n {
        : s w ( __gkc_ti t k )
        : ~ i c 0
        ? ( __gkc_eq w `if` ) { = c 1 } {}
        ? ( __gkc_eq w `while` ) { = c 2 } {}
        ? ( __gkc_eq w `for` ) { = c 3 } {}
        ? ( __gkc_eq w `else` ) { = c 4 } {}
        ? ( __gkc_eq w `{` ) { = c 5 } {}
        ? ( __gkc_eq w `}` ) { = c 6 } {}
        ? ( __gkc_word_in `SYNC SHARED_D SHARED_F SHARED_L SHFL_DOWN SHFL_XOR` w ) { = c 7 } {}
        ? ( __gkc_eq w `LD` ) { = c 8 } {}
        : s nx ( __gkc_ti t + k 1 )
        : ~ i a 0
        ? ( __gkc_word_in `= += -= *= /= %= &= |= ^= <<= >>=` nx ) { = a 1 } {
            ? | ( __gkc_word_in `++ --` nx ) ( __gkc_word_in `++ --` ( __gkc_ti t - k 1 ) ) { = a 2 } {}
        }
        : ~ i x1 0
        : ~ i x2 0
        : ~ i x3 0
        ? & >= c 1 <= c 3 { = x1 ( __gkc_close t + k 1 ) } {}
        ? == c 3 { = x2 ( __gkc_semi t + k 2 x1 ) = x3 ( __gkc_semi t + x2 1 x1 ) } {}
        ? & & == a 1 == c 0 >= ( vec_at [i] ids k ) 0 { = x1 ( __gkc_expr_end t + k 2 ) } {}
        ( vec_push [i] kd c ) ( vec_push [i] asg a ) ( vec_push [i] e1 x1 ) ( vec_push [i] e2 x2 ) ( vec_push [i] e3 x3 )
        = k + k 1
    }
    : i m ( vec_len [String] names )
    : ~ ( Vec i ) var ( vec_with_cap [i] m )
    : ~ ( Vec i ) per ( vec_with_cap [i] m )
    : ~ ( Vec i ) wr ( vec_with_cap [i] m )
    = k 0
    ~ < k m {
        : s w ( string_data ( vec_at [String] names k ) )
        ( vec_push [i] var ? | ( __gkc_type w ) ( __gkc_callable w ) 0 1 )
        ( vec_push [i] per ? ( __gkc_word_in nu w ) 1 0 )
        ( vec_push [i] wr ? ( __gkc_word_in writable w ) 1 0 )
        = k + k 1
    }
    ^ @ GkcU { ids var per wr kd asg e1 e2 e3 }
}

@ __gkc_u_idat GkcU u i k → i { ^ ?? ( vec_get [i] . u id k ) { T v → v F → -1 } }

@ __gkc_u_kat GkcU u i k → i { ^ ?? ( vec_get [i] . u kd k ) { T v → v F → 0 } }

// Is [lo, hi) the same for every thread of a block: no per-thread name in
// it, no load from a buffer the kernel writes?
@ __gkc_uni ( Vec String ) t i lo i hi GkcU u → b {
    : ~ i k lo
    ~ < k hi {
        : i id ( __gkc_u_idat u k )
        ? & >= id 0 == 1 ( vec_at [i] . u per id ) { ^ F } {}
        ? == 8 ( vec_at [i] . u kd k ) {
            : i i2 ( __gkc_u_idat u + k 2 )
            ? & >= i2 0 == 1 ( vec_at [i] . u wr i2 ) { ^ F } {}
        } {}
        = k + k 1
    }
    ^ T
}

// The name at `k`, given a value there (`x = …`, `x += …`, `x++`): it is
// per thread from now on unless every thread runs the assignment (`ctx`)
// and computes the same value. T when a name became per thread.
@ __gkc_assign_at ( Vec String ) t i k b ctx inout GkcU u → b {
    : i id ( __gkc_u_idat u k )
    ? < id 0 { ^ F } {}
    ? == 0 ( vec_at [i] . u var id ) { ^ F } {}
    ? == 1 ( vec_at [i] . u per id ) { ^ F } {}
    : i a ( vec_at [i] . u asg k )
    : ~ b per F
    ? == a 1 { = per | ! ctx ! ( __gkc_uni t + k 2 ( vec_at [i] . u e1 k ) u ) } {}
    ? == a 2 { = per ! ctx } {}
    ? per { ( vec_put [i] . u per id 1 ) ^ T } {}
    ^ F
}

@ __gkc_assigns ( Vec String ) t i lo i hi b ctx inout GkcU u → b {
    : ~ b ch F
    : ~ i k lo
    ~ < k hi { = ch | ch ( __gkc_assign_at t k ctx u ) = k + k 1 }
    ^ ch
}

// One walk over a cooperative body: T when a name became per thread. With
// `final`, `err` gets the reason a SYNC() sits where the threads of a
// block may part ("" when none does).
@ __gkc_uwalk ( Vec String ) t inout GkcU u b final inout String err → b {
    : i n ( vec_len [String] t )
    : ~ ( Vec i ) fu ( vec_new [i] )  // per open brace: 1 when the whole block runs it
    : ~ ( Vec i ) fif ( vec_new [i] )  // per open brace: 1 for an if's body
    : ~ i nbad 0  // open braces only some threads enter
    : ~ i pend -1  // what the next `{` is: -1 a plain block, else 1 / 0
    : ~ i pendif 0
    : ~ i lastif -1  // the if whose body just closed: 1 / 0, -1 none
    : ~ i elseu 1  // an `else if`: whether the else side is block-wide
    : ~ b ch F
    : ~ i k 0
    ~ < k n {
        : i kk ( vec_at [i] . u kd k )
        : b ctx == nbad 0
        ? | == kk 1 == kk 2 {
            : i he ( vec_at [i] . u e1 k )
            : b hc & ctx == elseu 1
            = ch | ch ( __gkc_assigns t + k 2 he hc u )
            : b cu & == elseu 1 ( __gkc_uni t + k 2 he u )
            = pend ? cu 1 0
            = pendif ? == kk 1 1 0
            = elseu 1
            = k + he 1
            continue
        } {}
        ? == kk 3 {
            : i he ( vec_at [i] . u e1 k )
            : i s1 ( vec_at [i] . u e2 k )
            : i s2 ( vec_at [i] . u e3 k )
            = ch | ch ( __gkc_assigns t + k 2 s1 ctx u )
            : b cu ( __gkc_uni t + s1 1 s2 u )
            = ch | ch ( __gkc_assigns t + s2 1 he & ctx cu u )
            = pend ? cu 1 0
            = pendif 0
            = k + he 1
            continue
        } {}
        ? == kk 4 {
            ? == 1 ( __gkc_u_kat u + k 1 ) { = elseu ? == lastif 1 1 0 } { = pend ? == lastif 1 1 0 = pendif 0 }
            = k + k 1
            continue
        } {}
        ? == kk 5 {
            : i uu ? < pend 0 1 pend
            ( vec_push [i] fu uu )
            ( vec_push [i] fif pendif )
            ? == uu 0 { = nbad + nbad 1 } {}
            = pend -1
            = pendif 0
            = k + k 1
            continue
        } {}
        ? == kk 6 {
            : i m ( vec_len [i] fu )
            ? > m 0 {
                : i uu ( vec_at [i] fu - m 1 )
                = lastif ? == ( vec_at [i] fif - m 1 ) 1 uu -1
                ? == uu 0 { = nbad - nbad 1 } {}
                : b _a ( vec_truncate [i] fu - m 1 )
                : b _b ( vec_truncate [i] fif - m 1 )
            } {}
            = k + k 1
            continue
        } {}
        ? & & final ! ctx == kk 7 {
            = err ( __gkc_why `SYNC() (or a shared array or a warp shuffle) where the threads of a block may part: every if / for / while around it must decide the same for the whole block` ( __gkc_ti t k ) )
            ^ F
        } {}
        = ch | ch ( __gkc_assign_at t k ctx u )
        = k + k 1
    }
    ^ ch
}

// Is every SYNC() of a cooperative body reached by all threads of a block?
// "" when it is, the reason otherwise.
@ __gkc_sync_check ( Vec String ) t s writable → String {
    : i n ( vec_len [String] t )
    : ~ i k 0
    ~ < k n {
        : s w ( __gkc_ti t k )
        ? ( __gkc_word_in `return break continue switch case default do` w ) {
            ^ ( __gkc_why `a kernel with SYNC(), a shared array or a warp shuffle has no return / break / continue / switch / do (threads leaving early would miss a barrier)` w )
        } {}
        ? ( __gkc_word_in `if for while` w ) {
            : i he ( __gkc_close t + k 1 )
            ? ( __gkc_eq ( __gkc_ti t + he 1 ) `{` ) {} { ^ ( __gkc_why `a kernel with SYNC() braces every if / for / while body` w ) }
        } {}
        ? & ( __gkc_eq w `else` ) ! | ( __gkc_eq ( __gkc_ti t + k 1 ) `{` ) ( __gkc_eq ( __gkc_ti t + k 1 ) `if` ) {
            ^ ( __gkc_why `a kernel with SYNC() braces every else body` w )
        } {}
        = k + k 1
    }
    : ~ String nu ( string_from `tid gid` )
    ( string_push_str nu ( string_data ( __gkc_ld4_targets t ) ) )
    ( string_push_str nu ( string_data ( __gkc_window_names t ) ) )
    : ~ String err ( string_new )
    : ~ i rounds 0
    // (a window's loads are per thread, as a written buffer's are)
    : ~ String wr2 ( string_from writable )
    ( string_push_str wr2 ( string_data ( __gkc_window_names t ) ) )
    : ~ GkcU u ( __gkc_u_new t ( string_data nu ) ( string_data wr2 ) )
    ~ & < rounds 256 ( __gkc_uwalk t u F err ) { = rounds + rounds 1 }
    : b _f ( __gkc_uwalk t u T err )
    ^ err
}

// The shared arrays a cooperative body declares — `SHARED_D(name, N);`
// statements at its own top level, N a number — into names / types (0
// double, 1 float, 2 long long) / sizes. The reason when one is malformed.
@ __gkc_shared ( Vec String ) t inout ( Vec String ) names inout ( Vec i ) tys inout ( Vec i ) sizes → String {
    ^ ( __gkc_arrays t `SHARED_D SHARED_F SHARED_L` 32768 `shared arrays above 32768 bytes per block` names tys sizes )
}

// The per-thread arrays a body declares — `LOCAL_F(name, N);` (LOCAL_D
// doubles, LOCAL_L long longs) at its own top level — the same way. They
// start zeroed; an index the compiler can see (an unrolled loop's) costs
// nothing to check, and the array then lives in registers.
@ __gkc_locals ( Vec String ) t inout ( Vec String ) names inout ( Vec i ) tys inout ( Vec i ) sizes → String {
    ^ ( __gkc_arrays t `LOCAL_D LOCAL_F LOCAL_L` 8192 `per-thread arrays above 8192 bytes` names tys sizes )
}

// The windows a body declares — `WIN(name, buffer, offset, length);` and
// `WINS(name, buffer, offset, length, stride);` statements — into names and
// the buffer each looks into. `devs` names the device buffers a window may
// look into, `taken` every name already in use. The reason when one is
// malformed.
@ __gkc_windows ( Vec String ) t s devs s taken inout ( Vec String ) names inout ( Vec String ) bufs inout ( Vec i ) dims → String {
    : i n ( vec_len [String] t )
    : ~ i k 0
    ~ < k n {
        : s w ( __gkc_ti t k )
        ? | | ( __gkc_eq w `WIN` ) ( __gkc_eq w `WINS` ) ( __gkc_eq w `WIN2` ) {
            : s pv ( __gkc_ti t - k 1 )
            ? | | == k 0 ( __gkc_eq pv `;` ) | ( __gkc_eq pv `{` ) ( __gkc_eq pv `}` ) {} { ^ ( __gkc_why `a window is declared as a statement` w ) }
            : i cl ( __gkc_close t + k 1 )
            ? & < + cl 1 n ( __gkc_eq ( __gkc_ti t + cl 1 ) `;` ) {} { ^ ( __gkc_why `a window is declared as a statement` w ) }
            : s nm ( __gkc_ti t + k 2 )
            : s bf ( __gkc_ti t + k 4 )
            ? & & ( __gkc_eq ( __gkc_ti t + k 1 ) `(` ) ( __gkc_eq ( __gkc_ti t + k 3 ) `,` ) ( __gkc_eq ( __gkc_ti t + k 5 ) `,` ) {} { ^ ( __gkc_why `WIN(name, buffer, offset, length);` w ) }
            ? ( __gkc_name_ok nm ) {} { ^ ( __gkc_why `window name` nm ) }
            ? ( __gkc_word_in `LD ST LD16 LD32 LD4 WIN WINS LEN SYNC WIN2 LD2 ST2 ROWS COLS` nm ) { ^ ( __gkc_why `window name` nm ) } {}
            ? ( __gkc_word_in taken nm ) { ^ ( __gkc_why `a window named like a binding or an array` nm ) } {}
            : ~ i j 0
            ~ < j ( vec_len [String] names ) { ? ( __gkc_eq ( string_data ( vec_at [String] names j ) ) nm ) { ^ ( __gkc_why `window declared twice` nm ) } {} = j + j 1 }
            ? ( __gkc_word_in devs bf ) {} { ^ ( __gkc_why `a window looks into a device or byte buffer of this call` bf ) }
            ( vec_push [String] names ( string_from nm ) )
            ( vec_push [String] bufs ( string_from bf ) )
            ( vec_push [i] dims ? ( __gkc_eq w `WIN2` ) 2 1 )
        } {}
        = k + k 1
    }
    ^ ( string_new )
}

// The names of the windows a body declares, space-separated (per thread
// for SYNC's rule: an offset or a length may differ from thread to thread).
@ __gkc_window_names ( Vec String ) t → String {
    : ~ String o ( string_new )
    : ~ i k 0
    ~ < k ( vec_len [String] t ) {
        ? & | | ( __gkc_eq ( __gkc_ti t k ) `WIN` ) ( __gkc_eq ( __gkc_ti t k ) `WINS` ) ( __gkc_eq ( __gkc_ti t k ) `WIN2` ) ( __gkc_eq ( __gkc_ti t + k 1 ) `(` ) {
            ( string_push_char o 32 ) ( string_push_str o ( __gkc_ti t + k 2 ) )
        } {}
        = k + k 1
    }
    ^ o
}

@ __gkc_arrays ( Vec String ) t s decl i limit s toobig inout ( Vec String ) names inout ( Vec i ) tys inout ( Vec i ) sizes → String {
    : i n ( vec_len [String] t )
    : ~ i depth 0
    : ~ i bytes 0
    : ~ i k 0
    ~ < k n {
        : s w ( __gkc_ti t k )
        ? | ( __gkc_eq w `{` ) ( __gkc_eq w `(` ) { = depth + depth 1 } {}
        ? | ( __gkc_eq w `}` ) ( __gkc_eq w `)` ) { = depth - depth 1 } {}
        ? ( __gkc_word_in decl w ) {
            : s pv ( __gkc_ti t - k 1 )
            ? & == depth 0 | | == k 0 ( __gkc_eq pv `;` ) ( __gkc_eq pv `}` ) {} { ^ ( __gkc_why `an array is declared as a statement of the body's own top level` w ) }
            : s nm ( __gkc_ti t + k 2 )
            : s sz ( __gkc_ti t + k 4 )
            ? & & ( __gkc_eq ( __gkc_ti t + k 1 ) `(` ) ( __gkc_eq ( __gkc_ti t + k 3 ) `,` ) & ( __gkc_eq ( __gkc_ti t + k 5 ) `)` ) ( __gkc_eq ( __gkc_ti t + k 6 ) `;` ) {} { ^ ( __gkc_why `SHARED_D(name, N);` w ) }
            ? ( __gkc_name_ok nm ) {} { ^ ( __gkc_why `array name` nm ) }
            ? ( __gkc_word_in `LD ST LD16 LD32 LD4 WIN WINS LEN SYNC` nm ) { ^ ( __gkc_why `array name` nm ) } {}
            : ~ i j 0
            ~ < j ( vec_len [String] names ) { ? ( __gkc_eq ( string_data ( vec_at [String] names j ) ) nm ) { ^ ( __gkc_why `array declared twice` nm ) } {} = j + j 1 }
            : ( Slice u ) zv ( slice_of_str sz )
            : i zl ( slice_len [u] zv )
            ? & > zl 0 < zl 7 {} { ^ ( __gkc_why `an array's size is a number of at most six digits` sz ) }
            : ~ i v 0
            = j 0
            ~ < j zl {
                : i d ( slice_byte zv j )
                ? ( __gkc_digit d ) {} { ^ ( __gkc_why `an array's size is a number` sz ) }
                = v + * v 10 - d 48
                = j + j 1
            }
            ? < v 1 { ^ ( __gkc_why `an array has at least one element` sz ) } {}
            : i ty ? | ( __gkc_eq w `SHARED_D` ) ( __gkc_eq w `LOCAL_D` ) 0 ? | ( __gkc_eq w `SHARED_F` ) ( __gkc_eq w `LOCAL_F` ) 1 2
            = bytes + bytes * v ? == ty 1 4 8
            ? > bytes limit { ^ ( __gkc_why toobig sz ) } {}
            ( vec_push [String] names ( string_from nm ) )
            ( vec_push [i] tys ty )
            ( vec_push [i] sizes v )
        } {}
        = k + k 1
    }
    ^ ( string_new )
}

// C type, load and store helpers of a device buffer's dtype (GK_F64,
// GK_F32, GK_I64).
@ __gkc_dty i dt → s { ? == dt 1 { ^ `float` } {} ? == dt 2 { ^ `long long` } {} ^ `double` }

@ __gkc_dld i dt b narrow → s {
    ? narrow { ? == dt 1 { ^ `__gk_ldf32` } {} ? == dt 2 { ^ `__gk_ldl32` } {} ^ `__gk_ldd32` } {}
    ? == dt 1 { ^ `__gk_ldf` } {} ? == dt 2 { ^ `__gk_ldl` } {} ^ `__gk_ldd`
}

@ __gkc_dst i dt b narrow → s {
    ? narrow { ? == dt 1 { ^ `__gk_stf32` } {} ? == dt 2 { ^ `__gk_stl32` } {} ^ `__gk_std32` } {}
    ? == dt 1 { ^ `__gk_stf` } {} ? == dt 2 { ^ `__gk_stl` } {} ^ `__gk_std`
}

// The device buffer binding `k` is bound to.
@ __gkc_dbuf GkCall c i k → GkBuf { ^ ( vec_at [GkBuf] . c db ( vec_at [i] . c slots k ) ) }

// The 16-bit float buffer binding `k` (kind 12) is bound to.
@ __gkc_hbuf GkCall c i k → GkHBuf { ^ ( vec_at [GkHBuf] . c hb ( vec_at [i] . c slots k ) ) }

// The byte buffer binding `k` (kind 13) is bound to.
@ __gkc_bbuf GkCall c i k → GkBBuf { ^ ( vec_at [GkBBuf] . c qb ( vec_at [i] . c slots k ) ) }

// Is device, half or byte buffer binding `k` there, with an element (a
// byte buffer: a whole word)?
@ __gkc_live GkCall c i k → b {
    ? | == ( vec_at [i] . c kinds k ) 13 == ( vec_at [i] . c kinds k ) 14 {
        : GkBBuf q ( __gkc_bbuf c k )
        ^ & ( gk_bbuf_ok q ) >= . q n 4
    } {}
    ? == ( vec_at [i] . c kinds k ) 12 {
        : GkHBuf h ( __gkc_hbuf c k )
        ^ & ( gk_hbuf_ok h ) > . h n 0
    } {}
    : GkBuf bk ( __gkc_dbuf c k )
    ^ & ( gk_buf_ok bk ) > . bk n 0
}

// Can LD4 read device buffer binding `k` — f32, 16-byte aligned, at
// least one group of 4? (Part of the cache key: a launch over a buffer
// that cannot builds anew, and its LD4 is refused.)
@ __gkc_aligned4 GkCall c i k → b {
    : GkBuf bk ( __gkc_dbuf c k )
    ^ & & == . bk dtype GK_F32 == 0 % . bk dptr 16 >= . bk n 4
}

// The names LD4 assigns (its last four arguments): per thread, whatever
// the uniformity walk would make of them.
@ __gkc_ld4_targets ( Vec String ) t → String {
    : ~ String o ( string_new )
    : i n ( vec_len [String] t )
    : ~ i k 0
    ~ < k n {
        ? & ( __gkc_eq ( __gkc_ti t k ) `LD4` ) ( __gkc_eq ( __gkc_ti t + k 1 ) `(` ) {
            : i cl ( __gkc_close t + k 1 )
            : ~ i j 1
            ~ < j 8 {
                ? >= - cl j + k 2 { ( string_push_char o 32 ) ( string_push_str o ( __gkc_ti t - cl j ) ) } {}
                = j + j 2
            }
        } {}
        = k + k 1
    }
    ^ o
}

// Its element type, as one character of a cache key (a GkBuf dtype as a
// digit; `h` / `b` for f16 / bf16).
@ __gkc_dtch GkCall c i k → i {
    ? == ( vec_at [i] . c kinds k ) 12 { ^ ? . ( __gkc_hbuf c k ) bf 98 104 } {}
    ? == ( vec_at [i] . c kinds k ) 13 { ^ 113 } {}
    ? == ( vec_at [i] . c kinds k ) 14 { ^ 81 } {}
    ^ + 48 . ( __gkc_dbuf c k ) dtype
}

// Binding `k`'s device byte range [lo, hi) (a device or half buffer).
@ __gkc_drange GkCall c i k inout i lo inout i hi → v {
    ? | == ( vec_at [i] . c kinds k ) 13 == ( vec_at [i] . c kinds k ) 14 {
        : GkBBuf q ( __gkc_bbuf c k )
        = lo . q dptr
        = hi + lo . q n
        ^
    } {}
    ? == ( vec_at [i] . c kinds k ) 12 {
        : GkHBuf h ( __gkc_hbuf c k )
        = lo . h dptr
        = hi + lo * . h n 2
    } {
        : GkBuf bk ( __gkc_dbuf c k )
        = lo . bk dptr
        = hi + lo * . bk n ( gk_buf_esz bk )
    }
}

// Each window's check (per buffer it looks into) and its LD / ST: index
// i of window w is element off + i·stride of its buffer when i < LEN(w),
// else the window's first — so in a loop to LEN(w) the check folds away.
@ __gkc_window_src inout String src GkCall c ( Vec String ) wn ( Vec String ) wb ( Vec i ) wd → v {
    : i nb ( vec_len [String] . c names )
    : ~ i k 0
    ~ < k nb {
        : s nm ( string_data ( vec_at [String] . c names k ) )
        : ~ b used F
        : ~ b used2 F
        : ~ i j 0
        ~ < j ( vec_len [String] wb ) {
            ? ( __gkc_eq ( string_data ( vec_at [String] wb j ) ) nm ) { ? == 2 ( vec_at [i] wd j ) { = used2 T } { = used T } } {}
            = j + j 1
        }
        : i kw ( vec_at [i] . c kinds k )
        : b bytes | == kw 13 == kw 14
        : b wrt | == kw 9 == kw 14
        // (a half window's load is the element as a float, as LD's is)
        : s cv ? == kw 12 ? . ( __gkc_hbuf c k ) bf `__gk_b2f(` `__gk_h2f(` ``
        ? used {
            // A window that does not fit — an empty one included, whose
            // offset nothing else bounds — becomes the empty window at 0
            // (the buffer has an element 0: a launch refuses empty buffers).
            ( string_push_str src `#undef __GK_WCHK_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_WCHK_` ) ( string_push_str src nm )
            ( string_push_str src `(o, l, s) if ((o) < 0 || (l) <= 0 || (s) < 1 || (o) >= __gk_n` ) ( string_push_int src k )
            ( string_push_str src ` || (unsigned long long)((l) - 1) > (unsigned long long)((__gk_n` ) ( string_push_int src k )
            ( string_push_str src ` - 1 - (o)) / (s))) { (o) = 0; (l) = 0; }\n` )
        } {}
        ? used2 {
            // A 2-D window: rows of `nc` elements, `s` apart. The last
            // element, o + (nr - 1)·s + nc - 1, is inside the buffer.
            ( string_push_str src `#undef __GK_WCHK2_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_WCHK2_` ) ( string_push_str src nm )
            ( string_push_str src `(o, nr, s, nc) if ((o) < 0 || (nr) <= 0 || (nc) <= 0 || (s) < 1 || (o) >= __gk_n` ) ( string_push_int src k )
            ( string_push_str src ` || (nc) - 1 > __gk_n` ) ( string_push_int src k ) ( string_push_str src ` - 1 - (o) || (unsigned long long)((nr) - 1) > (unsigned long long)((__gk_n` ) ( string_push_int src k )
            ( string_push_str src ` - (o) - (nc)) / (s))) { (o) = 0; (nr) = 0; (nc) = 0; }\n` )
        } {}
        = j 0
        ~ < j ( vec_len [String] wb ) {
            ? ( __gkc_eq ( string_data ( vec_at [String] wb j ) ) nm ) {
                : s w ( string_data ( vec_at [String] wn j ) )
                ? == 2 ( vec_at [i] wd j ) {
                    ( string_push_str src `#undef __GK_LD2_` ) ( string_push_str src w ) ( string_push_str src `\n#define __GK_LD2_` ) ( string_push_str src w )
                    ( string_push_str src ? bytes `(r, c) ((unsigned int)__gk_p` `(r, c) (` ) ( string_push_str src cv ) ( string_push_str src ? bytes `` `__gk_p` ) ( string_push_int src k ) ( string_push_str src `[__gk_wo_` ) ( string_push_str src w )
                    ( string_push_str src ` + __GK_WI((r), __gk_wr_` ) ( string_push_str src w ) ( string_push_str src `) * __gk_ws_` ) ( string_push_str src w )
                    ( string_push_str src ` + __GK_WI((c), __gk_wc_` ) ( string_push_str src w ) ( string_push_str src ? == kw 12 `)]))\n` `)])\n` )
                    ? wrt {
                        ( string_push_str src `#undef __GK_ST2_` ) ( string_push_str src w ) ( string_push_str src `\n#define __GK_ST2_` ) ( string_push_str src w )
                        ( string_push_str src `(r, c, v) __GK_WST2(__gk_p` ) ( string_push_int src k )
                        ( string_push_str src `, __gk_wo_` ) ( string_push_str src w ) ( string_push_str src `, __gk_wr_` ) ( string_push_str src w )
                        ( string_push_str src `, __gk_ws_` ) ( string_push_str src w ) ( string_push_str src `, __gk_wc_` ) ( string_push_str src w )
                        ( string_push_str src ? == kw 14 `, (r), (c), (unsigned int)(v))\n` `, (r), (c), (v))\n` )
                    } {}
                } {
                    // (a byte window's load is the byte, as a byte buffer's LD is)
                    ( string_push_str src `#undef __GK_LD_` ) ( string_push_str src w ) ( string_push_str src `\n#define __GK_LD_` ) ( string_push_str src w )
                    ( string_push_str src ? bytes `(i) ((unsigned int)__gk_p` `(i) (` ) ( string_push_str src cv ) ( string_push_str src ? bytes `` `__gk_p` ) ( string_push_int src k ) ( string_push_str src `[__gk_wo_` ) ( string_push_str src w )
                    ( string_push_str src ` + __GK_WI((i), __gk_wl_` ) ( string_push_str src w )
                    ( string_push_str src `) * __gk_ws_` ) ( string_push_str src w ) ( string_push_str src ? == kw 12 `]))\n` `])\n` )
                    ? wrt {
                        ( string_push_str src `#undef __GK_ST_` ) ( string_push_str src w ) ( string_push_str src `\n#define __GK_ST_` ) ( string_push_str src w )
                        ( string_push_str src `(i, v) __GK_WST(__gk_p` ) ( string_push_int src k )
                        ( string_push_str src `, __gk_wo_` ) ( string_push_str src w ) ( string_push_str src `, __gk_wl_` ) ( string_push_str src w )
                        ( string_push_str src `, __gk_ws_` ) ( string_push_str src w ) ( string_push_str src ? == kw 14 `, (i), (unsigned int)(v))\n` `, (i), (v))\n` )
                    } {}
                }
            } {}
            = j + j 1
        }
        = k + k 1
    }
}

// The source of a block launch: the checked accessors of every device
// buffer and shared array, then the kernel around `body`.
@ __gkc_source_dev GkCall c s ent s body ( Vec String ) shn ( Vec i ) sht ( Vec i ) shz b coop b narrow ( Vec String ) lcn ( Vec i ) lct ( Vec i ) lcz i block ( Vec String ) wn ( Vec String ) wb ( Vec i ) wd → String {
    : ~ String src ( string_from ( __gkc_header ) )
    ? coop {
        ( string_push_str src `#ifndef __GK_COOP_H
#define __GK_COOP_H
#define SYNC() __syncthreads()
#define SHARED_D(nm, N) __GK_SH_##nm
#define SHARED_F(nm, N) __GK_SH_##nm
#define SHARED_L(nm, N) __GK_SH_##nm
#define SHFL_DOWN(v, o) __gk_shfl_down((v), (int)(o))
#define SHFL_XOR(v, m) __gk_shfl_xor((v), (int)(m))
#ifdef __CUDACC__
static __device__ inline float __gk_shfl_down(float v, int o) { return __shfl_down_sync(0xffffffffu, v, (unsigned)o > 31u ? 0u : (unsigned)o); }
static __device__ inline float __gk_shfl_xor(float v, int m) { return __shfl_xor_sync(0xffffffffu, v, (unsigned)m > 31u ? 0 : m); }
static __device__ inline double __gk_shfl_down(double v, int o) { return __shfl_down_sync(0xffffffffu, v, (unsigned)o > 31u ? 0u : (unsigned)o); }
static __device__ inline double __gk_shfl_xor(double v, int m) { return __shfl_xor_sync(0xffffffffu, v, (unsigned)m > 31u ? 0 : m); }
static __device__ inline long long __gk_shfl_down(long long v, int o) { return __shfl_down_sync(0xffffffffu, v, (unsigned)o > 31u ? 0u : (unsigned)o); }
static __device__ inline long long __gk_shfl_xor(long long v, int m) { return __shfl_xor_sync(0xffffffffu, v, (unsigned)m > 31u ? 0 : m); }
static __device__ inline int __gk_shfl_down(int v, int o) { return __shfl_down_sync(0xffffffffu, v, (unsigned)o > 31u ? 0u : (unsigned)o); }
static __device__ inline int __gk_shfl_xor(int v, int m) { return __shfl_xor_sync(0xffffffffu, v, (unsigned)m > 31u ? 0 : m); }
#else
static inline float __gk_shfl_down(float v, int o) { __shared__ float __gk_x[1024]; int t = threadIdx.x; __gk_x[t] = v; __syncthreads(); unsigned l = (unsigned)o > 31u ? 32u : (unsigned)(t & 31) + (unsigned)o; float r = l < 32u ? __gk_x[(t & ~31) + (int)l] : v; __syncthreads(); return r; }
static inline float __gk_shfl_xor(float v, int m) { __shared__ float __gk_x[1024]; int t = threadIdx.x; __gk_x[t] = v; __syncthreads(); float r = (unsigned)m > 31u ? v : __gk_x[(t & ~31) + ((t & 31) ^ m)]; __syncthreads(); return r; }
static inline double __gk_shfl_down(double v, int o) { __shared__ double __gk_x[1024]; int t = threadIdx.x; __gk_x[t] = v; __syncthreads(); unsigned l = (unsigned)o > 31u ? 32u : (unsigned)(t & 31) + (unsigned)o; double r = l < 32u ? __gk_x[(t & ~31) + (int)l] : v; __syncthreads(); return r; }
static inline double __gk_shfl_xor(double v, int m) { __shared__ double __gk_x[1024]; int t = threadIdx.x; __gk_x[t] = v; __syncthreads(); double r = (unsigned)m > 31u ? v : __gk_x[(t & ~31) + ((t & 31) ^ m)]; __syncthreads(); return r; }
static inline long long __gk_shfl_down(long long v, int o) { __shared__ long long __gk_x[1024]; int t = threadIdx.x; __gk_x[t] = v; __syncthreads(); unsigned l = (unsigned)o > 31u ? 32u : (unsigned)(t & 31) + (unsigned)o; long long r = l < 32u ? __gk_x[(t & ~31) + (int)l] : v; __syncthreads(); return r; }
static inline long long __gk_shfl_xor(long long v, int m) { __shared__ long long __gk_x[1024]; int t = threadIdx.x; __gk_x[t] = v; __syncthreads(); long long r = (unsigned)m > 31u ? v : __gk_x[(t & ~31) + ((t & 31) ^ m)]; __syncthreads(); return r; }
static inline int __gk_shfl_down(int v, int o) { __shared__ int __gk_x[1024]; int t = threadIdx.x; __gk_x[t] = v; __syncthreads(); unsigned l = (unsigned)o > 31u ? 32u : (unsigned)(t & 31) + (unsigned)o; int r = l < 32u ? __gk_x[(t & ~31) + (int)l] : v; __syncthreads(); return r; }
static inline int __gk_shfl_xor(int v, int m) { __shared__ int __gk_x[1024]; int t = threadIdx.x; __gk_x[t] = v; __syncthreads(); int r = (unsigned)m > 31u ? v : __gk_x[(t & ~31) + ((t & 31) ^ m)]; __syncthreads(); return r; }
#endif
#endif
` )
    } {}
    : i nb ( vec_len [String] . c names )
    : ~ i k 0
    ~ < k nb {
        : i kd ( vec_at [i] . c kinds k )
        ? | == kd 8 == kd 9 {
            : s nm ( string_data ( vec_at [String] . c names k ) )
            : i dt . ( __gkc_dbuf c k ) dtype
            ( string_push_str src `#undef __GK_LD_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_LD_` ) ( string_push_str src nm ) ( string_push_str src `(i) ` )
            ( string_push_str src ( __gkc_dld dt narrow ) ) ( string_push_str src `(__gk_p` ) ( string_push_int src k )
            ( string_push_str src `, __gk_n` ) ( string_push_int src k ) ( string_push_str src `, (long long)(i))\n` )
            ? ( __gkc_aligned4 c k ) {
                ( string_push_str src `#undef __GK_LD4_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_LD4_` ) ( string_push_str src nm )
                ( string_push_str src ? narrow `(i, a0, a1, a2, a3) __GK_LD4N(__gk_p` `(i, a0, a1, a2, a3) __GK_LD4W(__gk_p` ) ( string_push_int src k )
                ( string_push_str src `, __gk_n` ) ( string_push_int src k ) ( string_push_str src `, (long long)(i), a0, a1, a2, a3)\n` )
            } {}
            ? == kd 9 {
                ( string_push_str src `#undef __GK_ST_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_ST_` ) ( string_push_str src nm ) ( string_push_str src `(i, v) ` )
                ( string_push_str src ( __gkc_dst dt narrow ) ) ( string_push_str src `(__gk_p` ) ( string_push_int src k )
                ( string_push_str src `, __gk_n` ) ( string_push_int src k ) ( string_push_str src `, (long long)(i), (v))\n` )
            } {}
        } {}
        ? == kd 12 {
            : s nm ( string_data ( vec_at [String] . c names k ) )
            ( string_push_str src `#undef __GK_LD_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_LD_` ) ( string_push_str src nm ) ( string_push_str src `(i) ` )
            ( string_push_str src ? . ( __gkc_hbuf c k ) bf `__gk_ldb` `__gk_ldh` ) ( string_push_str src ? narrow `32(__gk_p` `(__gk_p` ) ( string_push_int src k )
            ( string_push_str src `, __gk_n` ) ( string_push_int src k ) ( string_push_str src `, (long long)(i))\n` )
        } {}
        ? | == kd 13 == kd 14 {
            : s nm ( string_data ( vec_at [String] . c names k ) )
            ? == kd 14 {
                ( string_push_str src `#undef __GK_ST_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_ST_` ) ( string_push_str src nm )
                ( string_push_str src ? narrow `(i, v) __gk_stu8_32(__gk_p` `(i, v) __gk_stu8(__gk_p` ) ( string_push_int src k )
                ( string_push_str src `, __gk_n` ) ( string_push_int src k ) ( string_push_str src `, (long long)(i), (v))\n` )
            } {}
            : ~ i w8 0
            ~ < w8 3 {
                : s pre ? == w8 0 `LD_` ? == w8 1 `LD16_` `LD32_`
                : s fn ? == w8 0 `__gk_ldu8` ? == w8 1 `__gk_ldu16` `__gk_ldu32`
                ( string_push_str src `#undef __GK_` ) ( string_push_str src pre ) ( string_push_str src nm )
                ( string_push_str src `\n#define __GK_` ) ( string_push_str src pre ) ( string_push_str src nm ) ( string_push_str src `(i) ` )
                ( string_push_str src fn ) ( string_push_str src ? narrow `_32(__gk_p` `(__gk_p` ) ( string_push_int src k )
                ( string_push_str src `, __gk_n` ) ( string_push_int src k ) ( string_push_str src `, (long long)(i))\n` )
                = w8 + w8 1
            }
        } {}
        = k + k 1
    }
    ( __gkc_local_src src lcn lct lcz )
    ( __gkc_window_src src c wn wb wd )
    : i ns ( vec_len [String] shn )
    = k 0
    ~ < k ns {
        : s nm ( string_data ( vec_at [String] shn k ) )
        : i ty ( vec_at [i] sht k )
        : i z ( vec_at [i] shz k )
        : i dt ? == ty 0 0 ? == ty 1 1 2
        ( string_push_str src `#undef __GK_SH_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_SH_` ) ( string_push_str src nm ) ( string_push_str src ` __shared__ ` )
        ( string_push_str src ( __gkc_dty dt ) ) ( string_push_str src ` __gk_sh_` ) ( string_push_str src nm )
        ( string_push_char src 91 ) ( string_push_int src z ) ( string_push_char src 93 )
        ( string_push_str src `; for (long long __gk_z = tid; __gk_z < ` ) ( string_push_int src z )
        ( string_push_str src `; __gk_z += bdim) __gk_sh_` ) ( string_push_str src nm ) ( string_push_str src `[__gk_z] = 0; __syncthreads()\n` )
        ( string_push_str src `#undef __GK_LD_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_LD_` ) ( string_push_str src nm ) ( string_push_str src `(i) ` ) ( string_push_str src ( __gkc_dld dt narrow ) )
        ( string_push_str src `(__gk_sh_` ) ( string_push_str src nm ) ( string_push_str src `, ` ) ( string_push_int src z ) ( string_push_str src `, (long long)(i))\n` )
        ( string_push_str src `#undef __GK_ST_` ) ( string_push_str src nm ) ( string_push_str src `\n#define __GK_ST_` ) ( string_push_str src nm ) ( string_push_str src `(i, v) ` ) ( string_push_str src ( __gkc_dst dt narrow ) )
        ( string_push_str src `(__gk_sh_` ) ( string_push_str src nm ) ( string_push_str src `, ` ) ( string_push_int src z ) ( string_push_str src `, (long long)(i), (v))\n` )
        = k + k 1
    }
    ( string_push_str src `extern "C" __global__ void ` ) ( string_push_str src ent ) ( string_push_char src 40 )
    = k 0
    ~ < k nb {
        : i kd ( vec_at [i] . c kinds k )
        ? | == kd 8 == kd 9 {
            // (A buffer the kernel only reads overlaps none it writes —
            // __gkc_dev_build refuses that — so it is `__restrict__`: the
            // compiler may read it through the read-only cache and move its
            // loads past the stores.)
            ? == kd 8 { ( string_push_str src `const ` ) } {}
            ( string_push_str src ( __gkc_dty . ( __gkc_dbuf c k ) dtype ) ) ( string_push_str src ? == kd 8 `* __restrict__ __gk_p` `* __gk_p` ) ( string_push_int src k )
            ( string_push_str src `, long long __gk_n` ) ( string_push_int src k )
        } ? == kd 12 {
            ( string_push_str src `const unsigned short* __restrict__ __gk_p` ) ( string_push_int src k )
            ( string_push_str src `, long long __gk_n` ) ( string_push_int src k )
        } ? == kd 13 {
            ( string_push_str src `const unsigned char* __restrict__ __gk_p` ) ( string_push_int src k )
            ( string_push_str src `, long long __gk_n` ) ( string_push_int src k )
        } ? == kd 14 {
            ( string_push_str src `unsigned char* __gk_p` ) ( string_push_int src k )
            ( string_push_str src `, long long __gk_n` ) ( string_push_int src k )
        } {
            ( string_push_str src ? == kd 4 `long long ` `double ` ) ( string_push_str src ( string_data ( vec_at [String] . c names k ) ) )
        }
        ( string_push_str src `, ` )
        = k + k 1
    }
    // (The kernel is built for its block size: `bdim` is that number, and
    // the compiler is told a thread's index is below it — so an index into
    // a shared or per-thread array made of `tid` and loop counters can be
    // seen to be in range, and its check folds away.)
    ( string_push_str src `long long __gk_end) {
long long tid = threadIdx.x; long long bid = blockIdx.x; long long bdim = ` )
    ( string_push_int src block )
    ( string_push_str src `; long long nblocks = gridDim.x;
__GK_ASSUME(threadIdx.x < ` )
    ( string_push_int src block )
    ( string_push_str src `u);
long long gid = bid * bdim + tid; long long nthreads = nblocks * bdim;
(void)tid; (void)bid; (void)bdim; (void)nblocks; (void)gid; (void)nthreads; (void)__gk_end;
{
` )
    ( string_push_str src body )
    ( string_push_str src `
}
}
` )
    ^ src
}

// Check `body` and run `nblocks` blocks of `block` threads of it over `c`'s
// device buffers and scalars — nothing is copied: the kernel reads and
// writes the buffers where they live. F — nothing launched — when the body
// is outside the subset (gk_checked_error says why), a binding is not a
// device buffer or a scalar, a buffer is empty, or one the kernel only
// reads overlaps one it writes; F as well on a device error.
// The kernel `body` builds to over `c`'s bindings, checked (cached by
// name, bindings and body); none (an empty source, gk_checked_error c says
// why) when it is refused.
@ __gkc_dev_build GpuKit kit inout GkCall c s kname s body i nblocks i block → ( Arc GkcBuilt ) {
    = . c err ( string_new )
    ? | | < nblocks 0 < block 1 > block 1024 { = . c err ( __gkc_why `launch shape (0 or more blocks of 1 to 1024 threads)` `` ) ^ ( __gkc_none ) } {}
    : i nb ( vec_len [String] . c names )
    : ~ String key ( string_from `D` )
    ( string_push_str key kname )
    : ~ i k 0
    ~ < k nb {
        : s nm ( string_data ( vec_at [String] . c names k ) )
        : i kd ( vec_at [i] . c kinds k )
        ? | | | | | == kd 8 == kd 9 == kd 12 == kd 13 == kd 14 | == kd 4 == kd 5 {} { = . c err ( __gkc_why `gk_run_checked_dev takes device buffers and scalars` nm ) ^ ( __gkc_none ) }
        ( string_push_char key 1 ) ( string_push_str key nm ) ( string_push_char key + 48 kd )
        ? | | | | == kd 8 == kd 9 == kd 12 == kd 13 == kd 14 {
            ? ( __gkc_live c k ) {} { = . c err ( __gkc_why `an empty or failed device buffer` nm ) ^ ( __gkc_none ) }
            ( string_push_char key ( __gkc_dtch c k ) )
            ? | == kd 8 == kd 9 { ( string_push_char key ? ( __gkc_aligned4 c k ) 97 117 ) } {}
        } {}
        // What the kernel only reads stays put while it runs: no buffer it
        // writes overlaps it.
        ? | | == kd 8 == kd 12 == kd 13 {
            : ~ i lo 0
            : ~ i hi 0
            ( __gkc_drange c k lo hi )
            : ~ i j 0
            ~ < j nb {
                ? | == ( vec_at [i] . c kinds j ) 9 == ( vec_at [i] . c kinds j ) 14 {
                    : ~ i lo2 0
                    : ~ i hi2 0
                    ( __gkc_drange c j lo2 hi2 )
                    ? & < lo hi2 < lo2 hi { = . c err ( __gkc_why `a buffer the kernel reads overlaps one it writes` nm ) ^ ( __gkc_none ) } {}
                } {}
                = j + j 1
            }
        } {}
        = k + k 1
    }
    : ~ ( Vec i ) lens ( vec_new [i] )
    = k 0
    ~ < k nb {
        : i kd ( vec_at [i] . c kinds k )
        ? | == kd 8 == kd 9 { ( vec_push [i] lens . ( __gkc_dbuf c k ) n ) } {}
        ? == kd 12 { ( vec_push [i] lens . ( __gkc_hbuf c k ) n ) } {}
        ? | == kd 13 == kd 14 { ( vec_push [i] lens . ( __gkc_bbuf c k ) n ) } {}
        = k + k 1
    }
    : b narrow ( __gkc_narrow lens )
    ( string_push_char key ? narrow 110 119 )
    ( string_push_char key 3 ) ( string_push_int key block )
    ( string_push_char key 2 ) ( string_push_str key body )
    : ~ i idx -1
    : ~ ( Arc GkcBuilt ) hit ( __gkc_lookup ( string_data key ) idx )
    ? == 0 ( string_len . ( arc_get [GkcBuilt] hit ) src ) {
        // (Checked once: the key holds the name, so a hit had it checked.)
        ? ( __gkc_name_ok kname ) {} { = . c err ( __gkc_why `kernel name` kname ) ^ ( __gkc_none ) }
        : ( Vec String ) toks ( __gkc_toks body )
        : ~ ( Vec String ) shn ( vec_new [String] )
        : ~ ( Vec i ) sht ( vec_new [i] )
        : ~ ( Vec i ) shz ( vec_new [i] )
        = . c err ( __gkc_shared toks shn sht shz )
        ? > ( string_len . c err ) 0 { ^ ( __gkc_none ) } {}
        : ~ String bufs ( string_new )
        : ~ String outs ( string_new )
        : ~ String wbufs ( string_new )
        : ~ String f4bufs ( string_new )
        = k 0
        ~ < k nb {
            : s nm ( string_data ( vec_at [String] . c names k ) )
            ? ( __gkc_name_ok nm ) {} { = . c err ( __gkc_why `binding name` nm ) ^ ( __gkc_none ) }
            : i kd ( vec_at [i] . c kinds k )
            ? | | | | == kd 8 == kd 9 == kd 12 == kd 13 == kd 14 { ( string_push_char bufs 32 ) ( string_push_str bufs nm ) } {}
            ? | == kd 9 == kd 14 { ( string_push_char outs 32 ) ( string_push_str outs nm ) } {}
            ? | == kd 13 == kd 14 { ( string_push_char wbufs 32 ) ( string_push_str wbufs nm ) } {}
            ? & | == kd 8 == kd 9 ( __gkc_aligned4 c k ) { ( string_push_char f4bufs 32 ) ( string_push_str f4bufs nm ) } {}
            = k + k 1
        }
        = k 0
        ~ < k ( vec_len [String] shn ) {
            : s sn ( string_data ( vec_at [String] shn k ) )
            ? ( __gkc_word_in ( string_data bufs ) sn ) { = . c err ( __gkc_why `a shared array named like a binding` sn ) ^ ( __gkc_none ) } {}
            ( string_push_char bufs 32 ) ( string_push_str bufs sn )
            ( string_push_char outs 32 ) ( string_push_str outs sn )
            = k + k 1
        }
        : ~ ( Vec String ) lcn ( vec_new [String] )
        : ~ ( Vec i ) lct ( vec_new [i] )
        : ~ ( Vec i ) lcz ( vec_new [i] )
        = . c err ( __gkc_add_locals toks lcn lct lcz bufs outs )
        ? > ( string_len . c err ) 0 { ^ ( __gkc_none ) } {}
        // windows look into the device buffers (f64 / f32 / i64), the half
        // buffers and the byte buffers
        : ~ String devs ( string_new )
        = k 0
        ~ < k nb {
            : i kd ( vec_at [i] . c kinds k )
            ? | | | | == kd 8 == kd 9 == kd 12 == kd 13 == kd 14 { ( string_push_char devs 32 ) ( string_push_str devs ( string_data ( vec_at [String] . c names k ) ) ) } {}
            = k + k 1
        }
        : ~ ( Vec String ) wn ( vec_new [String] )
        : ~ ( Vec String ) wb ( vec_new [String] )
        : ~ ( Vec i ) wd ( vec_new [i] )
        = . c err ( __gkc_windows toks ( string_data devs ) ( string_data bufs ) wn wb wd )
        ? > ( string_len . c err ) 0 { ^ ( __gkc_none ) } {}
        = k 0
        ~ < k ( vec_len [String] wn ) {
            ( string_push_char bufs 32 ) ( string_push_str bufs ( string_data ( vec_at [String] wn k ) ) )
            ? ( __gkc_word_in ( string_data outs ) ( string_data ( vec_at [String] wb k ) ) ) { ( string_push_char outs 32 ) ( string_push_str outs ( string_data ( vec_at [String] wn k ) ) ) } {}
            = k + k 1
        }
        : ~ ( Vec i ) inits ( vec_new [i] )
        : ~ String w2s ( string_new )
        = k 0
        ~ < k ( vec_len [String] wn ) {
            ? == 2 ( vec_at [i] wd k ) { ( string_push_char w2s 32 ) ( string_push_str w2s ( string_data ( vec_at [String] wn k ) ) ) } {}
            = k + k 1
        }
        = . c err ( __gkc_check body ( string_data bufs ) ( string_data outs ) ( string_data wbufs ) ( string_data f4bufs ) ( string_data w2s ) inits )
        ? > ( string_len . c err ) 0 { ^ ( __gkc_none ) } {}
        : b coop ( __gkc_coop toks )
        ? coop {
            = . c err ( __gkc_sync_check toks ( string_data outs ) )
            ? > ( string_len . c err ) 0 { ^ ( __gkc_none ) } {}
        } {}
        ? < idx 0 { = idx ( __gkc_reserve ( string_data key ) ) } {}
        : String en ( __gkc_entry kname idx )
        : String b2 ( __gkc_with_inits body inits )
        : String nsrc ( __gkc_source_dev c ( string_data en ) ( string_data b2 ) shn sht shz coop narrow lcn lct lcz block wn wb wd )
        = hit ( __gkc_store idx nsrc en ( __gkc_shfl toks ) )
    } {}
    : GkcBuilt hb ( arc_get [GkcBuilt] hit )
    ? & . hb shfl != 0 % block 32 { = . c err ( __gkc_why `a kernel with a warp shuffle runs in blocks of whole warps (a multiple of 32 threads)` `` ) ^ ( __gkc_none ) } {}
    ^ hit
}

// The argument words of a block launch over `c`'s bindings, in the
// kernel's parameter order (a buffer: its address, then its length).
@ __gkc_dev_args GkCall c → ( Vec i ) {
    : i nb ( vec_len [String] . c names )
    : ~ i k 0
    : ~ ( Vec i ) args ( vec_new [i] )
    ~ < k nb {
        : i kd ( vec_at [i] . c kinds k )
        ? | == kd 8 == kd 9 {
            : GkBuf bk ( __gkc_dbuf c k )
            ( vec_push [i] args ( gk_arg_dev bk ) )
            ( vec_push [i] args ( gpu_arg_i64 . bk n ) )
        } ? == kd 12 {
            : GkHBuf hk ( __gkc_hbuf c k )
            ( vec_push [i] args . hk dptr )
            ( vec_push [i] args ( gpu_arg_i64 . hk n ) )
        } ? | == kd 13 == kd 14 {
            : GkBBuf qk ( __gkc_bbuf c k )
            ( vec_push [i] args . qk dptr )
            ( vec_push [i] args ( gpu_arg_i64 . qk n ) )
        } { ( vec_push [i] args ( gpu_arg_i64 ( vec_at [i] . c slots k ) ) ) }
        = k + k 1
    }
    ( vec_push [i] args ( gpu_arg_i64 0 ) )
    ^ args
}

unsafe @ gk_run_checked_dev GpuKit kit inout GkCall c s kname s body i nblocks i block → b {
    : ( Arc GkcBuilt ) hit ( __gkc_dev_build kit c kname body nblocks block )
    : GkcBuilt hb ( arc_get [GkcBuilt] hit )
    ? == 0 ( string_len . hb src ) { ^ F } {}
    : ( Vec i ) args ( __gkc_dev_args c )
    ? == nblocks 0 { ^ T } {}
    ^ ( gk_run_dev kit ( string_data . hb src ) ( string_data . hb ename ) nblocks block args )
}

// ── Recorded launches ─────────────────────────────────────────────────
//
// A program that launches the same kernels over the same buffers again
// and again — an autograd tape replayed every training step — need not
// check, build and bind them every time. gk_record_dev does all of
// gk_run_checked_dev but the launch, and keeps what it built: the kernel,
// the argument words, and a share of every buffer bound (so the buffers
// live as long as the record), on the kit it was made for. gk_replay then
// only launches — no binding names, no cache key, no argument building.
// A record is `raw`: its argument words are addresses, so only gpukit
// makes one.
raw : GkLaunch {
    GpuKit kit
    ( Arc GkcBuilt ) built
    ( Vec i ) args
    ( Vec GkBuf ) hold
    ( Vec GkHBuf ) holdh
    ( Vec GkBBuf ) holdq
    ( Vec String ) snames  // the scalars, by name …
    ( Vec i ) sword  // … and the argument word each one is
    i slot  // the kernel's slot in the kit's cache
    i nblocks
    i block
    b ok
}

// A record that launches nothing (gk_replay answers F).
unsafe @ gk_launch_none GpuKit kit → GkLaunch {
    ^ @ GkLaunch { ( GpuKit_share kit ) ( __gkc_none ) ( vec_new [i] ) ( vec_new [GkBuf] ) ( vec_new [GkHBuf] ) ( vec_new [GkBBuf] ) ( vec_new [String] ) ( vec_new [i] ) -1 0 1 F }
}

@ gk_launch_ok GkLaunch l → b { ^ . l ok }

// Check `body` against `c`'s bindings and build it, as gk_run_checked_dev
// does, and record the launch instead of making it: a record that is not
// ok (gk_checked_error c says why) when it would have answered F.
unsafe @ gk_record_dev GpuKit kit inout GkCall c s kname s body i nblocks i block → GkLaunch {
    : ( Arc GkcBuilt ) hit ( __gkc_dev_build kit c kname body nblocks block )
    ? == 0 ( string_len . ( arc_get [GkcBuilt] hit ) src ) { ^ ( gk_launch_none kit ) } {}
    : ~ ( Vec GkBuf ) hold ( vec_new [GkBuf] )
    : ~ i k 0
    ~ < k ( vec_len [GkBuf] . c db ) { ( vec_push [GkBuf] hold ( vec_at [GkBuf] . c db k ) ) = k + k 1 }
    : ~ ( Vec GkHBuf ) holdh ( vec_new [GkHBuf] )
    = k 0
    ~ < k ( vec_len [GkHBuf] . c hb ) { ( vec_push [GkHBuf] holdh ( vec_at [GkHBuf] . c hb k ) ) = k + k 1 }
    : ~ ( Vec GkBBuf ) holdq ( vec_new [GkBBuf] )
    = k 0
    ~ < k ( vec_len [GkBBuf] . c qb ) { ( vec_push [GkBBuf] holdq ( vec_at [GkBBuf] . c qb k ) ) = k + k 1 }
    : GkcBuilt hb ( arc_get [GkcBuilt] hit )
    : i slot ( _gk_slot_of kit ( string_data . hb src ) ( string_data . hb ename ) )
    ? < slot 0 { = . c err ( __gkc_why `the kernel did not compile` `` ) ^ ( gk_launch_none kit ) } {}
    // where each scalar sits among the argument words (__gkc_dev_args: two
    // words per buffer, one per scalar)
    : ~ ( Vec String ) snames ( vec_new [String] )
    : ~ ( Vec i ) sword ( vec_new [i] )
    : ~ i wd 0
    = k 0
    ~ < k ( vec_len [String] . c names ) {
        : i kd ( vec_at [i] . c kinds k )
        ? | | | | == kd 8 == kd 9 == kd 12 == kd 13 == kd 14 { = wd + wd 2 } {
            ( vec_push [String] snames ( string_from ( string_data ( vec_at [String] . c names k ) ) ) )
            ( vec_push [i] sword wd )
            = wd + wd 1
        }
        = k + k 1
    }
    ^ @ GkLaunch { ( GpuKit_share kit ) hit ( __gkc_dev_args c ) hold holdh holdq snames sword slot nblocks block T }
}

// Give scalar `name` of a recorded launch a new value — a decoder's
// position, a loop count the host advances between replays. F when the
// record has no such scalar. Any value is safe: a scalar is never an
// address, and every index the kernel forms from it is still checked
// against the buffers the record holds.
unsafe @ gk_launch_set_i64 inout GkLaunch l s name i x → b {
    : i k ( __gkc_launch_scalar l name )
    ? < k 0 { ^ F } {}
    ( vec_put [i] . l args k ( gpu_arg_i64 x ) )
    ^ T
}

unsafe @ gk_launch_set_f64 inout GkLaunch l s name f x → b {
    : i k ( __gkc_launch_scalar l name )
    ? < k 0 { ^ F } {}
    ( vec_put [i] . l args k ( f64_to_bits x ) )
    ^ T
}

// Launch `nblocks` blocks from now on (the block size was built in). F
// when nblocks is negative.
unsafe @ gk_launch_set_blocks inout GkLaunch l i nblocks → b {
    ? < nblocks 0 { ^ F } {}
    = . l nblocks nblocks
    ^ T
}

@ __gkc_launch_scalar GkLaunch l s name → i {
    : ~ i k 0
    ~ < k ( vec_len [String] . l snames ) {
        ? ( nurl_str_eq ( string_data ( vec_at [String] . l snames k ) ) name ) { ^ ( vec_at [i] . l sword k ) } {}
        = k + k 1
    }
    ^ -1
}

// Make a recorded launch again, on the kit it was recorded for. F when the
// record is not ok, or on a device error.
unsafe @ gk_replay GkLaunch l → b {
    ? . l ok {} { ^ F }
    ? == . l nblocks 0 { ^ T } {}
    ^ ( _gk_run_slot . l kit . l slot . l nblocks . l block . l args )
}

// (Last: dev.nu's ops are written over GkCall.)
$ `dev.nu`
