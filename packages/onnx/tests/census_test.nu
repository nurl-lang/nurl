// packages/onnx/tests/census_test.nu — the static kernel set covers the
// executor.
//
// The static / wasm builds link a FIXED kernel set, generated from
// rt_kernel_census (src/runtime.nu). Up to 0.9.0 that set was a list kept
// by hand in tools/gen_static_kernels.nu; when the executor moved onto
// gpukit's kernel library the list was never updated, and the generator
// kept importing a deleted file — the static backend and every wasm build
// were broken for three releases with every test green. This test is the
// tripwire, and needs no device and no compiler:
//
//   - every gkd_* wrapper the package's sources call is exercised by the
//     census (a new op handler that forgets the census fails HERE, not in
//     a browser);
//   - gpukit accepts every census call (a wrapper whose validation moved
//     under the census fails here);
//   - every recorded kernel can run on the static backend (no block
//     barriers), and kernels_static.c generates with every override still
//     matching its kernel's parameter list and every kernel registered.
//
// tests/static_test.sh compiles that file and runs a model on it.
// Run from the package root:
//   NURL_STDLIB=<repo> ../../nurl.sh tests/census_test.nu /tmp/ct && /tmp/ct

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `src/static_kernels.nu`
$ `stdlib/core/slice.nu`

: ~ i g_fail 0

@ check b cond s name → v {
    ? cond { ( nurl_print `  ok  ` ) } { ( nurl_print `  FAIL ` ) = g_fail + g_fail 1 }
    ( nurl_print name ) ( nurl_print `\n` )
}

// bytes [at, at+len) of `t` as a String
unsafe @ __sub s t i at i len → String { ^ ( string_from_bytes # *u + # i t at len ) }

@ __is_id i c → b { ^ | | & >= c 97 <= c 122 & >= c 48 <= c 57 == c 95 }

// Every distinct `( gkd_<name>` call in `text`, appended to `found`.
@ calls_in s text ( Vec String ) found → v {
    : ( Slice u ) text_v ( slice_of_str text )
    : i n ( nurl_str_len text )
    : ~ i at 0
    ~ < at n {
        : String rest ( __sub text at - n at )
        : i hit ( nurl_str_find ( string_data rest ) `( gkd_` )
        ? < hit 0 { = at n } {
            : i s0 + + at hit 2
            : ~ i e s0
            ~ & < e n ( __is_id ( slice_byte text_v e ) ) { = e + e 1 }
            : String name ( __sub text s0 - e s0 )
            : ~ b dup F
            : ~ i k 0
            ~ < k ( vec_len [String] found ) {
                ?? ( vec_get [String] found k ) { T f → { ? ( nurl_str_eq ( string_data f ) ( string_data name ) ) { = dup T } {} } F _ → {} }
                = k + k 1
            }
            ? dup {} { ( vec_push [String] found name ) }
            = at e
        }
    }
}

@ main → i {
    // ── 1. the census covers every gkd_* call the package makes ──
    ( nurl_print `[coverage]\n` )
    : ~ String census_body ( string_new )
    : ( Vec String ) called ( vec_new [String] )
    ?? ( fs_glob `src/*.nu` ) {
        T files → {
            : ~ i f 0
            ~ < f ( vec_len [String] files ) {
                ?? ( vec_get [String] files f ) {
                    T path → {
                        ?? ( read_file ( string_data path ) ) {
                            T text → {
                                : s t ( string_data text )
                                : i cz ( nurl_str_find t `\n@ rt_kernel_census ` )
                                ? >= cz 0 {
                                    // the census itself is not a caller to cover
                                    = census_body ( __sub t cz - ( nurl_str_len t ) cz )
                                    : String head ( __sub t 0 cz )
                                    ( calls_in ( string_data head ) called )
                                } {
                                    ( calls_in t called )
                                }
                            }
                            F _ → ( check F `read a source file` )
                        }
                    }
                    F _ → {}
                }
                = f + f 1
            }
        }
        F _ → ( check F `glob src/*.nu (run from the package root)` )
    }
    ( check > ( string_len census_body ) 0 `rt_kernel_census found` )
    ( check >= ( vec_len [String] called ) 20 `executor's gkd_* calls found` )
    : ~ i k 0
    ~ < k ( vec_len [String] called ) {
        ?? ( vec_get [String] called k ) {
            T name → {
                : String needle ( string_from `( ` )
                ( string_push_str needle ( string_data name ) )
                ( string_push_str needle ` ` )
                : String msg ( string_from `census calls ` )
                ( string_push_str msg ( string_data name ) )
                ( check >= ( nurl_str_find ( string_data census_body ) ( string_data needle ) ) 0 ( string_data msg ) )
            }
            F _ → {}
        }
        = k + k 1
    }

    // ── 2. gpukit accepts the census; every kernel can run statically ──
    ( nurl_print `[census]\n` )
    : GpuKit kit ( gk_open_census )
    ( check ( gk_is_census kit ) `a census kit opens with no device` )
    ( check == ( rt_kernel_census kit ) 0 `gpukit accepts every census call` )
    : i nk ( gk_kernel_count kit )
    ( check >= nk 25 `census recorded the executor's kernels` )
    : ~ i barriers 0
    = k 0
    ~ < k nk {
        : s src ( gk_census_src kit k )
        ? | >= ( nurl_str_find src `__syncthreads` ) 0 >= ( nurl_str_find src `__shared__` ) 0 { = barriers + barriers 1 } {}
        = k + k 1
    }
    ( check == barriers 0 `no recorded kernel needs block barriers` )

    // ── 3. kernels_static.c generates and registers every kernel ──
    ( nurl_print `[generate]\n` )
    : String out ( string_with_cap 131072 )
    : ( Vec String ) names ( vec_new [String] )
    ( check == ( onnx_static_kernels_c out names ) 0 `kernels_static.c generates (every override still fits)` )
    ( check == ( vec_len [String] names ) nk `one static entry per recorded kernel` )
    : ~ i missing 0
    = k 0
    ~ < k nk {
        : String row ( string_from `{ "` )
        ( string_push_str row ( gk_census_name kit k ) )
        ( string_push_str row `", __nurl_sl_` )
        ? < ( nurl_str_find ( string_data out ) ( string_data row ) ) 0 { = missing + missing 1 } {}
        = k + k 1
    }
    ( check == missing 0 `every recorded kernel is in the registry` )
    ( check >= ( nurl_str_find ( string_data out ) `{ "__nurl_static_set", ` ) 0 `registry carries the gpu package's probe sentinel` )

    ? == g_fail 0 { ( nurl_print `\nALL PASS\n` ) ^ 0 }
    { ( nurl_print `\n` ) ( nurl_print ( nurl_str_int g_fail ) ) ( nurl_print ` FAILED\n` ) ^ 1 }
}
