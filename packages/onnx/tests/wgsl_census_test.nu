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
//   - every census kernel has a WGSL entry,
//   - whose `sig` is, character for character, the parameter list the
//     census recorded (kernels_wgsl.js generates the bindings, the
//     uniform block and the argument decoding from `sig`, so an equal sig
//     is an equal cell layout),
//   - every parameter type has a marshalling row in kernels_wgsl.js's
//     CTYPES,
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
unsafe

@ __sub s t i at i len → String { ^ ( string_from_bytes # *u + # i t at len ) }

@ __is_id i c → b { ^ | | | & >= c 97 <= c 122 & >= c 65 <= c 90 & >= c 48 <= c 57 == c 95 }

: WgslEntry { String name String sig }

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
                        ( vec_push [WgslEntry] out @ WgslEntry { ( __sub l 0 colon ) ( __sub l s0 q ) } )
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
    : i n ( nurl_str_len t )
    // walk the quoted strings; a key is one followed by `:`
    : ~ i i 0
    ~ < i n {
        ? == ( nurl_str_get t i ) 34 {
            : ~ i e + i 1
            ~ & < e n != ( nurl_str_get t e ) 34 { = e + e 1 }
            ? & < + e 1 n == ( nurl_str_get t + e 1 ) 58 {
                ( vec_push [String] out ( __sub t + i 1 - - e i 1 ) )
            } {}
            = i + e 1
        } { = i + i 1 }
    }
    ^ out
}

// The parameter list a census kernel was recorded with: `(…)` right after
// its entry name in the source — the same text static_kernels.nu checks
// an override's `sig` against.
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
                : ~ i e ( string_len p )
                ~ & > e 0 ( __is_id ( nurl_str_get ps - e 1 ) ) { = e - e 1 }
                : String ty ( __sub ps 0 e )
                ( vec_push [String] out ( string_trim ty ) )
            }
            F _ → {}
        }
        = k + k 1
    }
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
    = k 0
    ~ < k nk {
        : s name ( gk_census_name kit k )
        : String want ( census_sig name ( gk_census_src kit k ) )
        ? == ( string_len want ) 0 { ( fail2 `census source has no parameter list: ` name ) } {}
        : ~ i found -1
        : ~ i j 0
        ~ < j nt {
            ?? ( vec_get [WgslEntry] table j ) { T e → { ? ( nurl_str_eq ( string_data . e name ) name ) { = found j } {} } F _ → {} }
            = j + j 1
        }
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
    ( check == missing 0 `every census kernel has a WGSL kernel` )
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
                    ~ < q nk { ? ( nurl_str_eq ( gk_census_name kit q ) en ) { = seen T } {} = q + q 1 }
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
