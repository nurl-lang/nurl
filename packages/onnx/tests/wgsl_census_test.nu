// packages/onnx/tests/wgsl_census_test.nu — the WebGPU kernel set covers
// the executor.
//
// On the gpu package's WebGPU backend a kernel is looked up by entry name
// in a fixed WGSL set (deps/gpu/web/kernels_wgsl.js) and launched with the
// argument cells the executor marshals for its CUDA-C parameter list. Up
// to 0.9.1 that set was a hand-kept copy of the pre-0.7 executor's kernels
// (`gemm`, `osigmoid`, `int` cells); when the executor moved onto gpukit
// nothing noticed, and every WebGPU build (objdet's wasm module,
// yoloe-demo's WebGPU engine) failed at run time with "no WGSL kernel
// named gk32_…". This is the tripwire, and needs no device, no browser
// and no compiler. Against the kernel census (rt_kernel_census — the
// record kernels_static.c is generated from):
//
//   - gpukit's kernels are checked ones, named `<base>__gk<16 hex>`; the
//     table is keyed by the base name, so no two census kernels may share
//     one,
//   - every census kernel has a WGSL entry,
//   - whose `sig` is, character for character, the parameter list the
//     census recorded (kernels_wgsl.js generates the bindings, the
//     uniform block and the argument decoding from `sig`, so an equal sig
//     is an equal cell layout),
//   - every parameter type has a marshalling row in kernels_wgsl.js's
//     CTYPES,
//   - an entry's `names` (the WGSL name of each `__gk_p<k>`) is the
//     binding the census source reads that parameter by, so a body reads
//     the buffer it means,
//   - the set holds no entry the census does not record (a stale kernel
//     is dead weight that still claims a layout), and
//   - the set carries the sentinel gpu_open probes (GPU_WGSL_SENTINEL).
//
// gpu's tests/webgpu_test.sh runs every kernel on a real WebGPU device.
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/wgsl_census_test.nu /tmp/wt && /tmp/wt

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `src/runtime.nu`
$ `stdlib/core/slice.nu`

: ~ i g_fail 0

@ check b cond s name → v {
    ? cond { ( nurl_print `  ok  ` ) } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name ) ( nurl_print `\n` )
}

@ fail2 s what s name → v {
    ( nurl_print `  FAIL ` ) ( nurl_print what ) ( nurl_print name ) ( nurl_print `\n` )
    = g_fail + g_fail 1
}

// bytes [at, at+len) of `t` as a String
@ __sub s t i at i len → String {
    : String out ( string_new )
    ( string_push_window out ( slice_of_str t ) at len )
    ^ out
}

@ __is_id i c → b { ^ | | | & >= c 97 <= c 122 & >= c 65 <= c 90 & >= c 48 <= c 57 == c 95 }

: WgslEntry { String name String sig String names }

// The table's entries: every line `<name>: { sig: "<sig>"` starting in
// column 0 (the format kernels_wgsl.js documents for its entries).
@ wgsl_entries s text → ( Vec WgslEntry ) {
    : ( Vec WgslEntry ) out ( vec_new [WgslEntry] )
    : ( Vec String ) lines ( string_split ( string_from text ) `\n` )
    : ~ i k 0
    ~ < k ( vec_len [String] lines ) {
        ?? ( vec_get [String] lines k ) {
            T ln → {
                : s l ( string_data ln )
                : i colon ( nurl_str_find l `: { sig: "` )
                ? & > colon 0 ( __is_id ( nurl_str_get l 0 ) ) {
                    : i s0 + colon 10
                    : String rest ( __sub l s0 - ( nurl_str_len l ) s0 )
                    : i q ( nurl_str_find ( string_data rest ) `"` )
                    ? >= q 0 {
                        // `, names: "<names>"` after the sig, on the same line
                        : ~ String nms ( string_new )
                        : String after ( __sub l + s0 q - - ( nurl_str_len l ) s0 q )
                        : i na ( nurl_str_find ( string_data after ) `names: "` )
                        ? >= na 0 {
                            : String nt ( __sub ( string_data after ) + na 8 - - ( string_len after ) na 8 )
                            : i nq ( nurl_str_find ( string_data nt ) `"` )
                            ? >= nq 0 { = nms ( __sub ( string_data nt ) 0 nq ) } {}
                        } {}
                        ( vec_push [WgslEntry] out @ WgslEntry { ( __sub l 0 colon ) ( __sub l s0 q ) nms } )
                    } {}
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ out
}

// The quoted keys of the `export const CTYPES = { "<ctype>": "<kind>", … };`
// line: the C parameter types the WebGPU glue can marshal.
@ wgsl_ctypes s text → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i at ( nurl_str_find text `export const CTYPES = {` )
    ? < at 0 { ^ out } {}
    : String tail ( __sub text at - ( nurl_str_len text ) at )
    : i nl ( nurl_str_find ( string_data tail ) `\n` )
    : String line ( __sub ( string_data tail ) 0 ? < nl 0 ( string_len tail ) nl )
    : s t ( string_data line )
    : ( Slice u ) t_v ( slice_of_str t )
    : i n ( nurl_str_len t )
    // walk the quoted strings; a key is one followed by `:`
    : ~ i i 0
    ~ < i n {
        ? == ( slice_byte t_v i ) 34 {
            : ~ i e + i 1
            ~ & < e n != ( slice_byte t_v e ) 34 { = e + e 1 }
            ? & < + e 1 n == ( slice_byte t_v + e 1 ) 58 {
                ( vec_push [String] out ( __sub t + i 1 - - e i 1 ) )
            } {}
            = i + e 1
        } { = i + i 1 }
    }
    ^ out
}

// The parameter list a census kernel was recorded with: `(…)` right after
// its entry name in the source.
@ census_sig s name s src → String {
    : String head ( string_from name )
    ( string_push_str head `(` )
    : i at ( nurl_str_find src ( string_data head ) )
    ? < at 0 { ^ ( string_new ) } {}
    : i s0 + at ( nurl_str_len name )
    : String rest ( __sub src s0 - ( nurl_str_len src ) s0 )
    : i close ( nurl_str_find ( string_data rest ) `)` )
    ? < close 0 { ^ ( string_new ) } {}
    ^ ( __sub src s0 + close 1 )
}

@ has_str ( Vec String ) v s x → b {
    : ~ i k 0
    ~ < k ( vec_len [String] v ) {
        ?? ( vec_get [String] v k ) { T e → { ? ( nurl_str_eq ( string_data e ) x ) { ^ T } {} } F _ → {} }
        = k + k 1
    }
    ^ F
}

// The C type of each parameter in `(…)` — the parameter text without its
// trailing name. Appended to `out`.
@ sig_types s sig ( Vec String ) out → v {
    : i n ( nurl_str_len sig )
    ? < n 2 { ^ } {}
    : String inner ( __sub sig 1 - n 2 )
    ? == ( string_len ( string_trim inner ) ) 0 { ^ } {}
    : ( Vec String ) parts ( string_split inner `,` )
    : ~ i k 0
    ~ < k ( vec_len [String] parts ) {
        ?? ( vec_get [String] parts k ) {
            T part → {
                : String p ( string_trim part )
                : s ps ( string_data p )
                : ( Slice u ) ps_v ( slice_of_str ps )
                : ~ i e ( string_len p )
                ~ & > e 0 ( __is_id ( slice_byte ps_v - e 1 ) ) { = e - e 1 }
                : String ty ( __sub ps 0 e )
                ( vec_push [String] out ( string_trim ty ) )
            }
            F _ → {}
        }
        = k + k 1
    }
}

// A checked kernel's base name: `<base>__gk<16 hex>` (with `_<n>` after it
// when two keys hashed alike) without the suffix; any other name as is.
@ base_name s name → String {
    : ( Slice u ) v ( slice_of_str name )
    : i n ( nurl_str_len name )
    : ~ i k - n 20
    ~ >= k 1 {
        ? & & == ( slice_byte v k ) 95 == ( slice_byte v + k 1 ) 95 & == ( slice_byte v + k 2 ) 103 == ( slice_byte v + k 3 ) 107 {
            : ~ b hex T
            : ~ i j 0
            ~ < j 16 {
                : i c ( slice_byte v + + k 4 j )
                ? | & >= c 48 <= c 57 & >= c 97 <= c 102 {} { = hex F }
                = j + j 1
            }
            : i e + k 20
            : ~ b tail == e n
            ? & ! tail & < e n == ( slice_byte v e ) 95 {
                = tail T
                : ~ i m + e 1
                ? >= m n { = tail F } {}
                ~ < m n { : i d ( slice_byte v m ) ? & >= d 48 <= d 57 {} { = tail F } = m + m 1 }
            } {}
            ? & hex tail { ^ ( __sub name 0 k ) } {}
        } {}
        = k - k 1
    }
    ^ ( string_from name )
}

// The binding a checked kernel's source reads parameter `__gk_p<k>` by:
// its `#define __GK_LD_<name>(i) <load>(__gk_p<k>, …` line. "" when none.
@ census_bind s src i k → String {
    : String pk ( string_new )
    ( string_push_str pk `(__gk_p` ) ( string_push_int pk k ) ( string_push_str pk `, ` )
    : ( Vec String ) lines ( string_split ( string_from src ) `\n` )
    : ~ i j 0
    ~ < j ( vec_len [String] lines ) {
        : s l ( string_data ( vec_at [String] lines j ) )
        ? & == ( nurl_str_find l `#define __GK_LD_` ) 0 >= ( nurl_str_find l ( string_data pk ) ) 0 {
            : String rest ( __sub l 16 - ( nurl_str_len l ) 16 )
            : i par ( nurl_str_find ( string_data rest ) `(` )
            ? > par 0 { ^ ( __sub ( string_data rest ) 0 par ) } {}
        } {}
        = j + j 1
    }
    ^ ( string_new )
}

// The `names` an entry must carry for a census source: the binding of
// each `__gk_p<k>`, k = 0, 1, … while there is one, space-separated.
@ census_names s src → String {
    : ~ String o ( string_new )
    : ~ i k 0
    ~ T {
        : String pk ( string_new )
        ( string_push_str pk `__gk_p` ) ( string_push_int pk k ) ( string_push_str pk `,` )
        ? < ( nurl_str_find src ( string_data pk ) ) 0 { break } {}
        : String b ( census_bind src k )
        ? > k 0 { ( string_push_char o 32 ) } {}
        ( string_push_str o ( string_data b ) )
        = k + k 1
    }
    ^ o
}

@ main → i {
    : s path `deps/gpu/web/kernels_wgsl.js`
    : ~ String js ( string_new )
    ?? ( read_file path ) {
        T t → { = js t }
        F _ → { ( check F `read deps/gpu/web/kernels_wgsl.js (run from the package root)` ) ^ 1 }
    }
    : ( Vec WgslEntry ) table ( wgsl_entries ( string_data js ) )
    : ( Vec String ) ctypes ( wgsl_ctypes ( string_data js ) )
    : i nt ( vec_len [WgslEntry] table )

    ( nurl_print `[table]\n` )
    ( check >= nt 25 `kernels_wgsl.js entries found` )
    ( check >= ( vec_len [String] ctypes ) 4 `kernels_wgsl.js CTYPES found` )
    // no entry twice — a JS object literal keeps the LAST, silently
    : ~ i dups 0
    : ~ i a 0
    ~ < a nt {
        : ~ i b + a 1
        ~ < b nt {
            ?? ( vec_get [WgslEntry] table a ) {
                T ea → {
                    ?? ( vec_get [WgslEntry] table b ) {
                        T eb → { ? ( string_eq . ea name . eb name ) { ( fail2 `entry defined twice: ` ( string_data . ea name ) ) = dups + dups 1 } {} }
                        F _ → {}
                    }
                }
                F _ → {}
            }
            = b + b 1
        }
        = a + a 1
    }
    ( check == dups 0 `no entry defined twice` )
    : ~ b sentinel F
    : ~ i k 0
    ~ < k nt {
        ?? ( vec_get [WgslEntry] table k ) {
            T e → {
                ? ( nurl_str_eq ( string_data . e name ) GPU_WGSL_SENTINEL ) {
                    = sentinel ( nurl_str_eq ( string_data . e sig ) `()` )
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ( check sentinel `the set carries gpu_open's probe sentinel (GPU_WGSL_SENTINEL, no parameters)` )

    ( nurl_print `[census → WGSL]\n` )
    : GpuKit kit ( gk_open_census )
    ( check == ( rt_kernel_census kit ) 0 `gpukit accepts every census call` )
    : i nk ( gk_kernel_count kit )
    ( check >= nk 25 `census recorded the executor's kernels` )
    : ~ i missing 0
    : ~ i differ 0
    : ~ i untyped 0
    : ~ i twice 0
    : ~ i misnamed 0
    = k 0
    ~ < k nk {
        : String name__s ( gk_census_name kit k )
        : s full ( string_data name__s )
        : String base__s ( base_name full )
        : s name ( string_data base__s )
        : String src__s ( gk_census_src kit k )
        : String want ( census_sig full ( string_data src__s ) )
        ? == ( string_len want ) 0 { ( fail2 `census source has no parameter list: ` full ) } {}
        // the table answers by base name: it must name one kernel
        : ~ i q2 + k 1
        ~ < q2 nk {
            : String o__s ( gk_census_name kit q2 )
            : String ob ( base_name ( string_data o__s ) )
            ? ( nurl_str_eq ( string_data ob ) name ) { ( fail2 `two census kernels share a base name: ` name ) = twice + twice 1 } {}
            = q2 + q2 1
        }
        : ~ i found -1
        : ~ i j 0
        ~ < j nt {
            ?? ( vec_get [WgslEntry] table j ) { T e → { ? ( nurl_str_eq ( string_data . e name ) name ) { = found j } {} } F _ → {} }
            = j + j 1
        }
        ? >= found 0 {
            : String wantn ( census_names ( string_data src__s ) )
            ?? ( vec_get [WgslEntry] table found ) {
                T e → {
                    ? ( string_eq . e names wantn ) {} {
                        ( fail2 `WGSL names are not the bindings the census source reads (update names AND body): ` name )
                        ( nurl_print `         census: ` ) ( nurl_print ( string_data wantn ) ) ( nurl_print `\n` )
                        ( nurl_print `         wgsl:   ` ) ( nurl_print ( string_data . e names ) ) ( nurl_print `\n` )
                        = misnamed + misnamed 1
                    }
                }
                F _ → {}
            }
        } {}
        ? < found 0 {
            ( fail2 `no WGSL kernel for census kernel: ` name )
            = missing + missing 1
        } {
            ?? ( vec_get [WgslEntry] table found ) {
                T e → {
                    ? ( string_eq . e sig want ) {} {
                        ( fail2 `WGSL sig differs from the census parameter list (update the entry's sig AND its body): ` name )
                        ( nurl_print `         census: ` ) ( nurl_print ( string_data want ) ) ( nurl_print `\n` )
                        ( nurl_print `         wgsl:   ` ) ( nurl_print ( string_data . e sig ) ) ( nurl_print `\n` )
                        = differ + differ 1
                    }
                }
                F _ → {}
            }
        }
        : ( Vec String ) tys ( vec_new [String] )
        ( sig_types ( string_data want ) tys )
        : ~ i q 0
        ~ < q ( vec_len [String] tys ) {
            ?? ( vec_get [String] tys q ) {
                T ty → {
                    ? ( has_str ctypes ( string_data ty ) ) {} {
                        : String what ( string_from `parameter type with no CTYPES row (` )
                        ( string_push_str what ( string_data ty ) )
                        ( string_push_str what `) in: ` )
                        ( fail2 ( string_data what ) name )
                        = untyped + untyped 1
                    }
                }
                F _ → {}
            }
            = q + q 1
        }
        = k + k 1
    }
    ( check == twice 0 `no two census kernels share a base name (the table's key)` )
    ( check == missing 0 `every census kernel has a WGSL kernel` )
    ( check == misnamed 0 `every entry names the bindings its census kernel reads` )
    ( check == differ 0 `every WGSL sig is the census parameter list` )
    ( check == untyped 0 `every parameter type is marshallable (CTYPES)` )

    ( nurl_print `[WGSL → census]\n` )
    : ~ i stale 0
    = k 0
    ~ < k nt {
        ?? ( vec_get [WgslEntry] table k ) {
            T e → {
                : s en ( string_data . e name )
                ? ( nurl_str_eq en GPU_WGSL_SENTINEL ) {} {
                    : ~ b seen F
                    : ~ i q 0
                    ~ < q nk {
                        : String cn ( gk_census_name kit q )
                        : String cb ( base_name ( string_data cn ) )
                        ? ( nurl_str_eq ( string_data cb ) en ) { = seen T } {}
                        = q + q 1
                    }
                    ? seen {} { ( fail2 `WGSL kernel the executor no longer launches: ` en ) = stale + stale 1 }
                }
            }
            F _ → {}
        }
        = k + k 1
    }
    ( check == stale 0 `no WGSL kernel outside the census` )

    ? == g_fail 0 { ( nurl_print `\nALL PASS\n` ) ^ 0 }
    { ( nurl_print `\n` ) ( nurl_print ( nurl_str_int g_fail ) ) ( nurl_print ` FAILED\n` ) ^ 1 }
}
