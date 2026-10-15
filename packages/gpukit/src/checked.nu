// gpukit/checked.nu — kernels a safe caller may write.
//
// gk_run hands a kernel's source to the device compiler as is: a kernel
// can index any address it is given, so only `unsafe` code may launch
// one. A CHECKED kernel is written in a subset that cannot: its body
// reaches memory only through
//
//     LD(name, i)        the element at i of buffer `name` (element 0 when
//                        i is outside it)
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
$ `gpukit.nu`

// One binding: kind 0 f64 input, 1 f64 output, 2 i64 input, 3 i64 output,
// 4 i64 scalar, 5 f64 scalar, 6 f64 input view, 7 i64 input view. `slot` indexes fv / iv for a buffer and holds
// the value (an f64's bits) for a scalar.
: GkCall {
    ( Vec String ) names
    ( Vec i ) kinds
    ( Vec i ) slots
    ( Vec ( Vec f ) ) fv
    ( Vec ( Vec i ) ) iv
    ( Vec ( Slice f ) ) fs  // inputs bound as views: read where they are
    ( Vec ( Slice i ) ) is
    String err  // why gk_run_checked refused the kernel ("" when it did not)
}

@ gk_call_new → GkCall {
    ^ @ GkCall { ( vec_new [String] ) ( vec_new [i] ) ( vec_new [i] ) ( vec_new [( Vec f )] ) ( vec_new [( Vec i )] ) ( vec_new [( Slice f )] ) ( vec_new [( Slice i )] ) ( string_new ) }
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

@ gk_call_view_i inout GkCall c s name ( Slice i ) v → v {
    ( __gkc_add c name 7 ( vec_len [( Slice i )] . c is ) )
    ( vec_push [( Slice i )] . c is v )
}

@ gk_call_i64 inout GkCall c s name i x → v { ( __gkc_add c name 4 x ) }

@ gk_call_f64 inout GkCall c s name f x → v { ( __gkc_add c name 5 ( f64_to_bits x ) ) }

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

// Kernels checked and built before: key (name, bindings, body) → source.
// A fit launches the same kernel every round; checking its body once is
// enough.
: GkcCache { ( Vec String ) keys ( Vec String ) srcs }

@ __gkc_cache0 → ( Locked GkcCache ) { ^ ( locked_new [GkcCache] @ GkcCache { ( vec_new [String] ) ( vec_new [String] ) } ) }

: ( Locked GkcCache ) g_gkc_cache ( __gkc_cache0 )

// The built source for `key`, "" when it was never checked.
@ __gkc_cached s key → String {
    : ~ GkcCache c ( locked_take [GkcCache] g_gkc_cache )
    : ~ String r ( string_new )
    : i n ( vec_len [String] . c keys )
    : ~ i k 0
    ~ < k n {
        ? != 0 ( nurl_str_eq ( string_data ( vec_at [String] . c keys k ) ) key ) { = r ( string_from ( string_data ( vec_at [String] . c srcs k ) ) ) = k n } { = k + k 1 }
    }
    ( locked_restore [GkcCache] g_gkc_cache c )
    ^ r
}

@ __gkc_remember s key s src → v {
    : ~ GkcCache c ( locked_take [GkcCache] g_gkc_cache )
    ( vec_push [String] . c keys ( string_from key ) )
    ( vec_push [String] . c srcs ( string_from src ) )
    ( locked_restore [GkcCache] g_gkc_cache c )
}

// ── The subset ────────────────────────────────────────────────────────

// Why the last gk_run_checked over `c` refused its kernel ("" when it did not).
@ gk_checked_error GkCall c → s { ^ ( string_data . c err ) }

@ __gkc_alpha i c → b { ^ | | & >= c 97 <= c 122 & >= c 65 <= c 90 == c 95 }

@ __gkc_digit i c → b { ^ & >= c 48 <= c 57 }

// The math a body may call.
@ __gkc_callable s w → b {
    ? ( __gkc_word_in `LD ST if for while switch return sizeof min max abs fabs fabsf sqrt sqrtf rsqrt rsqrtf exp expf exp2 exp2f expm1 log logf log2 log2f log1p log1pf log10 sin sinf cos cosf tan tanf tanh tanhf sinh cosh atan atanf atan2 atan2f asin acos pow powf fmin fminf fmax fmaxf floor floorf ceil ceilf round roundf trunc truncf fmod fmodf erf erff erfc erfcf isnan isinf isfinite copysign copysignf __dadd_rn __dsub_rn __dmul_rn __ddiv_rn __fadd_rn __fsub_rn __fmul_rn __fdiv_rn __fsqrt_rn __dsqrt_rn __syncthreads` w ) { ^ T } {}
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
        ^ ! ( __gkc_word_in `__dadd_rn __dsub_rn __dmul_rn __ddiv_rn __fadd_rn __fsub_rn __fmul_rn __fdiv_rn __fsqrt_rn __dsqrt_rn __syncthreads` w )
    } {}
    ^ F
}

// The reason a body is refused, `at` the offending name or character.
@ __gkc_why s why s at → String {
    : ~ String o ( string_from why )
    ? != 0 ( nurl_str_len at ) { ( string_push_str o `: ` ) ( string_push_str o at ) } {}
    ^ o
}

// Is `body` inside the subset? `bufs` lists the buffer names LD / ST may
// take (outputs also in `outs`).
@ __gkc_check s body s bufs s outs → String {
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
            ? > want_buf 0 {
                ? ! ( __gkc_word_in bufs ws ) { ^ ( __gkc_why `LD / ST takes a buffer of this call` ws ) } {}
                ? & == want_buf 2 ! ( __gkc_word_in outs ws ) { ^ ( __gkc_why `ST into a buffer that is not an output` ws ) } {}
                = want_buf 0
            } {}
            // a call: only LD / ST and the math list
            : ~ i j k
            ~ & < j n | == ( slice_byte b j ) 32 | == ( slice_byte b j ) 9 == ( slice_byte b j ) 10 { = j + j 1 }
            ? & < j n == ( slice_byte b j ) 40 {
                ? ( __gkc_callable ws ) {} { ^ ( __gkc_why `call to a function outside the checked list` ws ) }
                ? ( __gkc_eq ws `LD` ) { = want_buf 1 } {}
                ? ( __gkc_eq ws `ST` ) { = want_buf 2 } {}
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
        ? == c 41 { = paren - paren 1 ? < paren 0 { ^ ( __gkc_why `unbalanced )` `` ) } {} = prev 1 = k + k 1 continue } {}
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
    ? | | ( __gkc_banned w ) ( __gkc_callable w ) ( __gkc_word_in `gid nthreads` w ) { ^ F } {}
    ^ T
}

@ __gkc_ty i kind → s { ? | | == kind 0 == kind 1 == kind 6 { ^ `double` } {} ^ `long long` }

// An f64 binding (input, output or view)?
@ __gkc_isf i kind → b { ^ | | == kind 0 == kind 1 == kind 6 }

// The length binding `k` is bound with (-1: a scalar).
@ __gkc_blen GkCall c i k → i {
    : i kd ( vec_at [i] . c kinds k )
    : i sl ( vec_at [i] . c slots k )
    ? | == kd 0 == kd 1 { ^ ( vec_len [f] ( vec_at [( Vec f )] . c fv sl ) ) } {}
    ? | == kd 2 == kd 3 { ^ ( vec_len [i] ( vec_at [( Vec i )] . c iv sl ) ) } {}
    ? == kd 6 { ^ ( slice_len [f] ( vec_at [( Slice f )] . c fs sl ) ) } {}
    ? == kd 7 { ^ ( slice_len [i] ( vec_at [( Slice i )] . c is sl ) ) } {}
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

// The full source: the per-buffer accessors, then the kernel around `body`.
// (On the host a load's check is a branch the CPU predicts, its
// out-of-range side a cold call — no select the compiler could fold it
// into: a select would sit on every dependent load chain, a tree walk's,
// as a predicted branch does not. On a GPU the select is the cheap form.)
@ __gkc_source GkCall c ( Vec i ) grp s kname s body → String {
    : ~ String src ( string_from `#ifdef __CUDACC__
static __device__ inline double __gk_ldd(const double* p, long long n, long long i) { return p[(unsigned long long)i < (unsigned long long)n ? i : 0]; }
static __device__ inline long long __gk_ldl(const long long* p, long long n, long long i) { return p[(unsigned long long)i < (unsigned long long)n ? i : 0]; }
#else
__attribute__((noinline, cold)) static double __gk_ldd0(const double* p) { return p[0]; }
__attribute__((noinline, cold)) static long long __gk_ldl0(const long long* p) { return p[0]; }
static inline double __gk_ldd(const double* p, long long n, long long i) { if (__builtin_expect((unsigned long long)i >= (unsigned long long)n, 0)) return __gk_ldd0(p); return p[i]; }
static inline long long __gk_ldl(const long long* p, long long n, long long i) { if (__builtin_expect((unsigned long long)i >= (unsigned long long)n, 0)) return __gk_ldl0(p); return p[i]; }
#endif
static __device__ inline void __gk_std(double* p, long long n, long long i, double v) { if ((unsigned long long)i < (unsigned long long)n) p[i] = v; }
static __device__ inline void __gk_stl(long long* p, long long n, long long i, long long v) { if ((unsigned long long)i < (unsigned long long)n) p[i] = v; }
#define LD(b, i) __GK_LD_##b(i)
#define ST(b, i, v) __GK_ST_##b(i, v)
` )
    : i nb ( vec_len [String] . c names )
    : ~ i k 0
    ~ < k nb {
        : s nm ( string_data ( vec_at [String] . c names k ) )
        : i kd ( vec_at [i] . c kinds k )
        : String ks ( string_from ( nurl_str_int k ) )
        : String gs ( string_from ( nurl_str_int ( vec_at [i] grp k ) ) )
        ? | < kd 4 > kd 5 {
            ( string_push_str src `#define __GK_LD_` ) ( string_push_str src nm )
            ( string_push_str src ? ( __gkc_isf kd ) `(i) __gk_ldd(__gk_p` `(i) __gk_ldl(__gk_p` )
            ( string_push_str src ( string_data ks ) ) ( string_push_str src `, __gk_n` ) ( string_push_str src ( string_data gs ) )
            ( string_push_str src `, (long long)(i))\n` )
            ? | == kd 1 == kd 3 {
                ( string_push_str src `#define __GK_ST_` ) ( string_push_str src nm )
                ( string_push_str src ? == kd 1 `(i, v) __gk_std(__gk_p` `(i, v) __gk_stl(__gk_p` )
                ( string_push_str src ( string_data ks ) ) ( string_push_str src `, __gk_n` ) ( string_push_str src ( string_data gs ) )
                ( string_push_str src `, (long long)(i), (v))\n` )
            } {}
        } {}
        = k + k 1
    }
    ( string_push_str src `extern "C" __global__ void ` ) ( string_push_str src kname ) ( string_push_char src 40 )
    = k 0
    ~ < k nb {
        : s nm ( string_data ( vec_at [String] . c names k ) )
        : i kd ( vec_at [i] . c kinds k )
        : String ks ( string_from ( nurl_str_int k ) )
        ? | < kd 4 > kd 5 {
            ( string_push_str src ? | | == kd 0 == kd 2 > kd 5 `const ` `` )
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
    ? ( __gkc_name_ok kname ) {} { = . c err ( __gkc_why `kernel name` kname ) ^ F }
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
        ? | == kd 1 == kd 3 { ( string_push_char outs 32 ) ( string_push_str outs nm ) } {}
        = k + k 1
    }
    // (…and which buffers share a length: __gkc_groups.)
    : ( Vec i ) grp ( __gkc_groups c )
    = k 0
    ~ < k nb { ( string_push_char key 3 ) ( string_push_str key ( nurl_str_int ( vec_at [i] grp k ) ) ) = k + k 1 }
    ( string_push_char key 2 ) ( string_push_str key body )
    : ~ String src ( __gkc_cached ( string_data key ) )
    ? == 0 ( string_len src ) {
        = k 0
        ~ < k nb {
            : s nm ( string_data ( vec_at [String] . c names k ) )
            ? ( __gkc_name_ok nm ) {} { = . c err ( __gkc_why `binding name` nm ) ^ F }
            = k + k 1
        }
        = . c err ( __gkc_check body ( string_data bufs ) ( string_data outs ) )
        ? > ( string_len . c err ) 0 { ^ F } {}
        = src ( __gkc_source c grp kname body )
        ( __gkc_remember ( string_data key ) ( string_data src ) )
    } {}
    // the launch: every buffer with its own length, the scalars as given
    : ( Vec GkArg ) call ( vec_new [GkArg] )
    // A load past the end reads element 0 (the check keeps the load itself
    // unconditional), so an empty buffer is bound as one zero element —
    // its length still 0, so nothing is stored into it.
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
        ? == kd 4 { ( vec_push [GkArg] call ( gk_i64 sl ) ) } {}
        ? == kd 5 { ( vec_push [GkArg] call ( gk_i64 sl ) ) } {}
        = k + k 1
    }
    ( vec_push [GkArg] call ( gk_i64 nthreads ) )
    ? == nthreads 0 { ^ T } {}
    ^ ( gk_run kit ( string_data src ) kname ( gk_grid nthreads block ) block call )
}
