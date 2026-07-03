// packages/wasmbuilder/src/toolchain.nu — locate (or provision) everything a
// local wasm32-wasi build needs, using only what the installed NURL
// toolchain already ships.
//
// The wasm pipeline needs three things beyond nurlc itself:
//
//   1. a compiler+linker that lowers LLVM IR to a wasm32-wasi module.
//      The toolchain's bundled `zig cc` (at $NURL_HOME/zig/zig, preferred
//      by nurl.sh for native builds too) does this out of the box — zig
//      carries its own wasi-libc and wasm-ld, so NO wasi-sdk is needed.
//   2. the NURL runtime compiled for wasm32 (runtime.wasm.o). The installed
//      stdlib ships runtime.c, so we compile it on first use and cache the
//      object keyed by the SOURCE HASH — a toolchain upgrade that changes
//      runtime.c automatically invalidates the cache. No version skew.
//   3. (optional) canvas/audio host-import objects, same on-demand scheme.
//
// Resolution order for the wasm compiler:
//   $NURL_ZIG → $NURL_HOME/zig/zig → `zig` on PATH → $WASI_CLANG (a
//   wasi-sdk clang, for setups that already have one) → download a pinned,
//   sha256-verified zig release into $NURL_HOME/zig (opt out with
//   NURL_WASM_NO_DOWNLOAD=1).
//
// Everything is namespaced wb_/__wb_ — NURL has one flat function
// namespace and this module is meant to be imported by other packages
// (swarm-mcp, nurl-mcp).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/process.nu`
$ `stdlib/std/hash.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/json.nu`
$ `stdlib/ext/http_cli.nu`

// The zig release wasmbuilder provisions when none is found. Matches the
// version the release workflow bundles (.github/workflows/release.yml
// ZIG_VER) so a provisioned zig behaves exactly like a bundled one.
@ __wb_zig_version → s { ^ `0.13.0` }

@ wb_is_windows → b {
    : ?String ev ( env_get `OS` )
    : ~ b w F
    ?? ev {
        T e → { = w ( nurl_str_eq ( string_data e ) `Windows_NT` ) ( string_free e ) }
        F → {}
    }
    ^ w
}

// $NURL_HOME, defaulting to <home>/.nurl — the same layout
// tools/install-toolchain.sh and get-nurl.{sh,ps1} produce.
@ wb_nurl_home → String {
    : ?String ev ( env_get `NURL_HOME` )
    ?? ev { T e → { ^ e } F → {} }
    : ~ String home ( string_new )
    ? ( wb_is_windows )
    { ( string_free home ) = home ( env_var_or `USERPROFILE` `.` ) }
    { ( string_free home ) = home ( env_var_or `HOME` `.` ) }
    : String p ( path_join ( string_data home ) `.nurl` )
    ( string_free home )
    ^ p
}

// The directory holding the stdlib C sources (runtime.c & friends).
// $NURL_STDLIB is the toolchain PREFIX (import strings like
// `stdlib/core/string.nu` resolve against it), so the C sources live at
// $NURL_STDLIB/stdlib/. Fall back to $NURL_HOME/stdlib for direct runs.
@ wb_stdlib_dir → String {
    : ?String ev ( env_get `NURL_STDLIB` )
    ?? ev { T e → {
            : String p ( path_join ( string_data e ) `stdlib` )
            ( string_free e )
            ^ p
        } F → {} }
    : String home ( wb_nurl_home )
    : String p ( path_join ( string_data home ) `stdlib` )
    ( string_free home )
    ^ p
}

// True when `cmd <args>` runs and exits 0 — the "is this tool here and
// alive" probe (ProcessNotFound and non-zero exits both count as no).
@ __wb_runs s cmd s arg → b {
    : !Output ProcessErr r ( process_run1 cmd arg )
    ?? r {
        T o → {
            : b ok ( output_success o )
            ( output_free o )
            ^ ok
        }
        F _ → { ^ F }
    }
}

// ── nurlc ─────────────────────────────────────────────────────────────

// Locate nurlc: $NURLC → $NURL_HOME/bin/nurlc → `nurlc` on PATH.
// The $NURL_HOME/bin shim is preferred over PATH because it exports
// NURL_STDLIB, keeping stdlib import resolution correct even when
// wasmbuilder itself was started without the shims.
@ wb_find_nurlc → !String String {
    : ?String ev ( env_get `NURLC` )
    ?? ev { T e → { ^ @ !String String { T e } } F → {} }
    : String home ( wb_nurl_home )
    : String bindir ( path_join ( string_data home ) `bin` )
    : ~ String cand ( path_join ( string_data bindir ) `nurlc` )
    ? ( wb_is_windows ) {
        : String c2 ( string_from ( string_data cand ) )
        ( string_push_str c2 `.bat` )
        ( string_free cand ) = cand c2
    } {}
    ( string_free home ) ( string_free bindir )
    ? ( file_exists ( string_data cand ) ) { ^ @ !String String { T cand } } {}
    ( string_free cand )
    ? ( __wb_runs `nurlc` `--version` ) { ^ @ !String String { T ( string_from `nurlc` ) } } {}
    ^ @ !String String { F ( string_from `nurlc not found — install the NURL toolchain first: curl -fsSL https://nurl-lang.org/install.sh | sh (then add $HOME/.nurl/bin to PATH), or set $NURLC` ) }
}

// ── the wasm compiler (zig cc, or a wasi-sdk clang) ───────────────────

// WbCompiler.cmd is the executable; is_zig=T means invoke as `cmd cc …`
// (zig's clang driver), F means a wasi-sdk clang invoked as `cmd …`.
: WbCompiler {
    String cmd
    b is_zig
}

@ wb_compiler_free WbCompiler c → v { ( string_free . c cmd ) }

// Probe a zig binary: `zig version` must run and exit 0.
@ __wb_zig_ok s zig → b { ^ ( __wb_runs zig `version` ) }

@ wb_find_compiler b allow_download → !WbCompiler String {
    // 1. explicit override
    : ?String ev ( env_get `NURL_ZIG` )
    ?? ev { T e → { ^ @ !WbCompiler String { T @ WbCompiler { e T } } } F → {} }

    // 2. the toolchain's bundled zig
    : String home ( wb_nurl_home )
    : ~ String cand ( path_join ( string_data home ) `zig` )
    : String cand2 ( path_join ( string_data cand ) ? ( wb_is_windows ) `zig.exe` `zig` )
    ( string_free cand ) ( string_free home )
    ? ( file_exists ( string_data cand2 ) ) { ^ @ !WbCompiler String { T @ WbCompiler { cand2 T } } } {}
    ( string_free cand2 )

    // 3. a zig on PATH
    ? ( __wb_zig_ok `zig` ) { ^ @ !WbCompiler String { T @ WbCompiler { ( string_from `zig` ) T } } } {}

    // 4. an explicit wasi-sdk clang (for boxes that already carry one)
    : ?String wc ( env_get `WASI_CLANG` )
    ?? wc { T c → { ^ @ !WbCompiler String { T @ WbCompiler { c F } } } F → {} }

    // 5. provision a pinned zig into $NURL_HOME/zig
    : ?String nodl ( env_get `NURL_WASM_NO_DOWNLOAD` )
    : ~ b may_download allow_download
    ?? nodl { T n → { ? > ( string_len n ) 0 { = may_download F } {} ( string_free n ) } F → {} }
    ? may_download {
        : !String String pz ( __wb_provision_zig )
        ?? pz {
            T zp → { ^ @ !WbCompiler String { T @ WbCompiler { zp T } } }
            F e → { ^ @ !WbCompiler String { F e } }
        }
    } {}
    ^ @ !WbCompiler String { F ( string_from `no wasm compiler found: no bundled zig ($NURL_HOME/zig/zig), no zig on PATH, no $WASI_CLANG — and downloads are disabled. Unset NURL_WASM_NO_DOWNLOAD, or install zig 0.13.0 and set $NURL_ZIG.` ) }
}

// ── zig provisioning ──────────────────────────────────────────────────

// "<arch>-<os>" key used by ziglang.org/download/index.json, e.g.
// "x86_64-linux". Windows arch comes from PROCESSOR_ARCHITECTURE; POSIX
// from `uname -m`/`uname -s`.
@ __wb_zig_platform_key → !String String {
    ? ( wb_is_windows ) {
        : String pa ( env_var_or `PROCESSOR_ARCHITECTURE` `AMD64` )
        : b arm ( nurl_str_eq ( string_data pa ) `ARM64` )
        ( string_free pa )
        ^ @ !String String { T ( string_from ? arm `aarch64-windows` `x86_64-windows` ) }
    } {}
    : !Output ProcessErr mr ( process_run1 `uname` `-m` )
    : !Output ProcessErr sr ( process_run1 `uname` `-s` )
    : ~ String machine ( string_new )
    : ~ String sysname ( string_new )
    ?? mr { T o → { ( string_free machine ) = machine ( string_from ( output_stdout o ) ) ( output_free o ) } F _ → {} }
    ?? sr { T o → { ( string_free sysname ) = sysname ( string_from ( output_stdout o ) ) ( output_free o ) } F _ → {} }
    : String m ( string_trim machine )
    : String sy ( string_trim sysname )
    ( string_free machine ) ( string_free sysname )
    ? == ( string_len m ) 0 {
        ( string_free m ) ( string_free sy )
        ^ @ !String String { F ( string_from `could not detect platform (uname failed)` ) }
    } {}
    : ~ String key ( string_new )
    // zig names: x86_64 / aarch64. uname may say arm64 (macOS).
    ? ( nurl_str_eq ( string_data m ) `arm64` ) { ( string_push_str key `aarch64` ) } { ( string_push_str key ( string_data m ) ) }
    ( string_push_str key ? ( nurl_str_eq ( string_data sy ) `Darwin` ) `-macos` `-linux` )
    ( string_free m ) ( string_free sy )
    ^ @ !String String { T key }
}

// sha256 of a file via the OS's standard hasher (sha256sum / shasum -a 256
// / certutil). Shelling out beats hashing 50 MB in pure NURL, and one of
// these ships on every supported platform.
@ __wb_file_sha256_hex s path → !String String {
    : !Output ProcessErr r1 ( process_run1 `sha256sum` path )
    ?? r1 { T o → {
            ? ( output_success o ) {
                : String out ( string_from ( output_stdout o ) )
                ( output_free o )
                : String hex ( __wb_first_token out )
                ( string_free out )
                ^ @ !String String { T hex }
            } { ( output_free o ) }
        } F _ → {} }
    : !Output ProcessErr r2 ( process_run3 `shasum` `-a` `256` path )
    ?? r2 { T o → {
            ? ( output_success o ) {
                : String out ( string_from ( output_stdout o ) )
                ( output_free o )
                : String hex ( __wb_first_token out )
                ( string_free out )
                ^ @ !String String { T hex }
            } { ( output_free o ) }
        } F _ → {} }
    // Windows: certutil prints the hex (possibly spaced) on the 2nd line.
    : !Output ProcessErr r3 ( process_run3 `certutil` `-hashfile` path `SHA256` )
    ?? r3 { T o → {
            ? ( output_success o ) {
                : String out ( string_from ( output_stdout o ) )
                ( output_free o )
                : String hex ( __wb_certutil_hex out )
                ( string_free out )
                ? > ( string_len hex ) 0 { ^ @ !String String { T hex } } {}
                ( string_free hex )
            } { ( output_free o ) }
        } F _ → {} }
    ^ @ !String String { F ( string_from `no sha256 tool found (tried sha256sum, shasum, certutil)` ) }
}

// First whitespace-delimited token of a string (sha256sum's "<hex>  <file>").
@ __wb_first_token String st → String {
    : String t ( string_trim st )
    : ~ i e 0
    : i n ( string_len t )
    ~ & < e n & != ( string_get t e ) 32 & != ( string_get t e ) 9 != ( string_get t e ) 10 { = e + e 1 }
    : String tok ( string_substr t 0 e )
    ( string_free t )
    ^ tok
}

// Pull the 64-hex-digit line out of certutil's chatty output.
@ __wb_certutil_hex String out → String {
    : ( Vec String ) lines ( string_split out `\n` )
    : ~ String hex ( string_new )
    : ~ i i 0
    ~ < i ( vec_len [String] lines ) {
        : ?String lo ( vec_get [String] lines i )
        ?? lo { T line → {
                : String c ( string_replace line ` ` `` )
                : String ct ( string_trim c )
                ( string_free c )
                : ~ b all_hex > ( string_len ct ) 0
                : ~ i k 0
                ~ < k ( string_len ct ) {
                    : i ch ( string_get ct k )
                    : b is_hex | & >= ch 48 <= ch 57 | & >= ch 97 <= ch 102 & >= ch 65 <= ch 70
                    ? is_hex {} { = all_hex F }
                    = k + k 1
                }
                ? & all_hex == ( string_len ct ) 64 {
                    ( string_free hex ) = hex ( string_to_lower ct )
                } { ( string_free ct ) }
            } F → {} }
        = i + i 1
    }
    ( vec_free_with [String] lines \ String s → v { ( string_free s ) } )
    ^ hex
}

// Download + verify + unpack the pinned zig into $NURL_HOME/zig.
// Returns the zig binary path. The archive URL and sha256 come from
// ziglang.org's own signed-adjacent index.json (fetched over HTTPS), so
// nothing here hardcodes hashes that would rot.
@ __wb_provision_zig → !String String {
    : !String String pk ( __wb_zig_platform_key )
    : ~ String key ( string_new )
    ?? pk { T k → { ( string_free key ) = key k } F e → { ^ @ !String String { F e } } }

    ( nurl_eprintln `wasmbuilder: no zig found — downloading zig 0.13.0 (one-time, sha256-verified) into $NURL_HOME/zig ...` )

    // 1. index.json → tarball URL + shasum for (version, platform).
    : !HttpcResp HttpcErr ir ( httpc_get `https://ziglang.org/download/index.json` )
    : ~ String tarball ( string_new )
    : ~ String shasum ( string_new )
    ?? ir {
        T resp → {
            ? != ( httpc_status resp ) 200 {
                ( httpc_resp_free resp ) ( string_free key )
                ^ @ !String String { F ( string_from `zig download index fetch failed (non-200 from ziglang.org)` ) }
            } {}
            : !Json JsonError jr ( json_parse ( httpc_body_str resp ) )
            ?? jr {
                T root → {
                    : ?Json vo ( json_obj_get root ( __wb_zig_version ) )
                    ?? vo { T vj → {
                            : ?Json po ( json_obj_get vj ( string_data key ) )
                            ?? po { T pj → {
                                    : ?Json tb ( json_obj_get pj `tarball` )
                                    : ?Json sh ( json_obj_get pj `shasum` )
                                    ?? tb { T t → { ( string_free tarball ) = tarball ( string_from ( json_str_data t ) ) } F → {} }
                                    ?? sh { T sv → { ( string_free shasum ) = shasum ( string_from ( json_str_data sv ) ) } F → {} }
                                } F → {} }
                        } F → {} }
                    ( json_free root )
                }
                F _ → {}
            }
            ( httpc_resp_free resp )
        }
        F _ → {
            ( string_free key )
            ^ @ !String String { F ( string_from `could not reach ziglang.org (curl missing or offline). Install zig 0.13.0 manually and set $NURL_ZIG, or re-install the toolchain (Linux releases bundle zig).` ) }
        }
    }
    ? | == ( string_len tarball ) 0 == ( string_len shasum ) 0 {
        : String msg ( string_from `zig 0.13.0 has no build for platform ` )
        ( string_push_str msg ( string_data key ) )
        ( string_free key ) ( string_free tarball ) ( string_free shasum )
        ^ @ !String String { F msg }
    } {}
    ( string_free key )

    // 2. download the archive next to its final home.
    : String home ( wb_nurl_home )
    : !v IoErr hd ( dir_create_all ( string_data home ) )
    ?? hd { T _ → {} F _ → {
            ( string_free home ) ( string_free tarball ) ( string_free shasum )
            ^ @ !String String { F ( string_from `cannot create $NURL_HOME` ) }
        } }
    : String arch_name ( path_basename ( string_data tarball ) )
    : String arch_path ( path_join ( string_data home ) ( string_data arch_name ) )
    : !HttpcResp HttpcErr dl ( httpc_get ( string_data tarball ) )
    ?? dl {
        T resp → {
            ? != ( httpc_status resp ) 200 {
                ( httpc_resp_free resp )
                ( string_free home ) ( string_free tarball ) ( string_free shasum ) ( string_free arch_name ) ( string_free arch_path )
                ^ @ !String String { F ( string_from `zig archive download failed (non-200)` ) }
            } {}
            : ( Vec u ) body ( httpc_body_bytes resp )
            ( httpc_resp_free resp )
            : !v IoErr wr ( write_file_bytes ( string_data arch_path ) body )
            ( vec_free [u] body )
            ?? wr { T _ → {} F _ → {
                    ( string_free home ) ( string_free tarball ) ( string_free shasum ) ( string_free arch_name ) ( string_free arch_path )
                    ^ @ !String String { F ( string_from `could not write zig archive under $NURL_HOME` ) }
                } }
        }
        F _ → {
            ( string_free home ) ( string_free tarball ) ( string_free shasum ) ( string_free arch_name ) ( string_free arch_path )
            ^ @ !String String { F ( string_from `zig archive download failed (network)` ) }
        }
    }

    // 3. verify sha256 against the index's shasum.
    : !String String hh ( __wb_file_sha256_hex ( string_data arch_path ) )
    ?? hh {
        T got → {
            : b ok ( string_eq got shasum )
            ? ok { ( string_free got ) } {
                ( file_delete ( string_data arch_path ) )
                : String msg ( string_from `zig archive sha256 MISMATCH (expected ` )
                ( string_push_str msg ( string_data shasum ) )
                ( string_push_str msg `, got ` )
                ( string_push_str msg ( string_data got ) )
                ( string_push_str msg `) — refusing to install` )
                ( string_free got )
                ( string_free home ) ( string_free tarball ) ( string_free shasum ) ( string_free arch_name ) ( string_free arch_path )
                ^ @ !String String { F msg }
            }
        }
        F e → {
            ( string_free home ) ( string_free tarball ) ( string_free shasum ) ( string_free arch_name ) ( string_free arch_path )
            ^ @ !String String { F e }
        }
    }
    ( string_free shasum ) ( string_free tarball )

    // 4. unpack ("tar -xf" everywhere: GNU/bsdtar handle .tar.xz, Windows
    //    10+ bsdtar handles the .zip) and rename the versioned top-level
    //    dir to the canonical $NURL_HOME/zig.
    : ( Vec s ) targs ( vec_new [s] )
    ( vec_push [s] targs `-xf` ) ( vec_push [s] targs ( string_data arch_path ) )
    ( vec_push [s] targs `-C` ) ( vec_push [s] targs ( string_data home ) )
    : !Output ProcessErr tr ( process_run `tar` targs `` )
    ( vec_free [s] targs )
    : ~ b tar_ok F
    ?? tr { T o → { = tar_ok ( output_success o ) ( output_free o ) } F _ → {} }
    ( file_delete ( string_data arch_path ) )
    ( string_free arch_path )
    ? tar_ok {} {
        ( string_free home ) ( string_free arch_name )
        ^ @ !String String { F ( string_from `could not unpack the zig archive (is 'tar' with xz support installed?)` ) }
    }

    // top-level dir = archive name minus .tar.xz / .zip
    : ~ String topdir ( string_from ( string_data arch_name ) )
    ? ( string_ends_with topdir `.tar.xz` ) {
        : String t ( string_substr topdir 0 - ( string_len topdir ) 7 )
        ( string_free topdir ) = topdir t
    } {
        ? ( string_ends_with topdir `.zip` ) {
            : String t ( string_substr topdir 0 - ( string_len topdir ) 4 )
            ( string_free topdir ) = topdir t
        } {}
    }
    ( string_free arch_name )
    : String from ( path_join ( string_data home ) ( string_data topdir ) )
    : String dest ( path_join ( string_data home ) `zig` )
    ( string_free topdir )
    : !v IoErr mv ( fs_rename ( string_data from ) ( string_data dest ) )
    ( string_free from )
    ?? mv { T _ → {} F _ → {
            ( string_free home ) ( string_free dest )
            ^ @ !String String { F ( string_from `could not move the unpacked zig into $NURL_HOME/zig` ) }
        } }
    ( string_free home )

    : String zbin ( path_join ( string_data dest ) ? ( wb_is_windows ) `zig.exe` `zig` )
    ( string_free dest )
    ? ( file_exists ( string_data zbin ) ) {} {
        ( string_free zbin )
        ^ @ !String String { F ( string_from `zig unpacked but $NURL_HOME/zig/zig is missing` ) }
    }
    ( nurl_eprintln `wasmbuilder: zig installed.` )
    ^ @ !String String { T zbin }
}

// ── wasm runtime objects (compiled from the installed stdlib, cached) ─

// Cache root: $NURL_HOME/build/wasmbuilder (created on demand).
@ wb_cache_dir → String {
    : String home ( wb_nurl_home )
    : String b ( path_join ( string_data home ) `build` )
    : String c ( path_join ( string_data b ) `wasmbuilder` )
    ( string_free home ) ( string_free b )
    ^ c
}

// Compile <stdlib>/<src_c> for wasm32-wasi and cache the object keyed by
// the source's content hash: runtime.c changes with the toolchain, so an
// upgrade automatically produces a fresh object that matches it.
// Returns the cached object path.
@ wb_ensure_wasm_obj WbCompiler cc s src_c → !String String {
    : String sdir ( wb_stdlib_dir )
    : String csrc ( path_join ( string_data sdir ) src_c )
    ( string_free sdir )
    ? ( file_exists ( string_data csrc ) ) {} {
        : String msg ( string_from `stdlib C source not found: ` )
        ( string_push_str msg ( string_data csrc ) )
        ( string_push_str msg ` (is the toolchain installed? set $NURL_STDLIB)` )
        ( string_free csrc )
        ^ @ !String String { F msg }
    }
    : !String IoErr srcr ( read_file ( string_data csrc ) )
    : ~ String src ( string_new )
    ?? srcr { T sc → { ( string_free src ) = src sc } F _ → {
            ( string_free csrc )
            ^ @ !String String { F ( string_from `could not read the stdlib C source` ) }
        } }
    : String hex ( sha256_hex ( string_data src ) )
    ( string_free src )
    : String tag ( string_substr hex 0 16 )
    ( string_free hex )

    : String cdir ( wb_cache_dir )
    : !v IoErr mk ( dir_create_all ( string_data cdir ) )
    ?? mk { T _ → {} F _ → {
            ( string_free cdir ) ( string_free csrc ) ( string_free tag )
            ^ @ !String String { F ( string_from `could not create the wasmbuilder cache dir under $NURL_HOME/build` ) }
        } }

    // <name>-<hash16>.wasm.o
    : ~ String oname ( string_from src_c )
    ? ( string_ends_with oname `.c` ) {
        : String t ( string_substr oname 0 - ( string_len oname ) 2 )
        ( string_free oname ) = oname t
    } {}
    ( string_push_str oname `-` )
    ( string_push_str oname ( string_data tag ) )
    ( string_push_str oname `.wasm.o` )
    ( string_free tag )
    : String opath ( path_join ( string_data cdir ) ( string_data oname ) )
    ( string_free cdir ) ( string_free oname )
    ? ( file_exists ( string_data opath ) ) {
        ( string_free csrc )
        ^ @ !String String { T opath }
    } {}

    // compile: [zig] cc --target=wasm32-wasi -O2 -c src -o opath
    : ( Vec s ) args ( vec_new [s] )
    ? . cc is_zig { ( vec_push [s] args `cc` ) } {}
    ( vec_push [s] args `--target=wasm32-wasi` )
    ( vec_push [s] args `-O2` )
    ( vec_push [s] args `-c` )
    ( vec_push [s] args ( string_data csrc ) )
    ( vec_push [s] args `-o` )
    ( vec_push [s] args ( string_data opath ) )
    : !Output ProcessErr r ( process_run ( string_data . cc cmd ) args `` )
    ( vec_free [s] args )
    ?? r {
        T o → {
            ? ( output_success o ) {
                ( output_free o ) ( string_free csrc )
                ^ @ !String String { T opath }
            } {
                : String msg ( string_from `wasm runtime compile failed for ` )
                ( string_push_str msg ( string_data csrc ) )
                ( string_push_str msg `:\n` )
                ( string_push_str msg ( output_stderr o ) )
                ( output_free o ) ( string_free csrc ) ( string_free opath )
                ^ @ !String String { F msg }
            }
        }
        F _ → {
            ( string_free csrc ) ( string_free opath )
            ^ @ !String String { F ( string_from `could not run the wasm compiler` ) }
        }
    }
}
