// wasm.nu — binary-level N.cap cross-check of a WebAssembly module's import
// section (AGORA-1038).
//
// `nurl-cert verify prog.cert --binary prog.wasm` parses the wasm binary's
// import section (section id 2) and checks every function import against the
// capability classes `N.cap` names, trusting neither nurlc nor the runtime
// source. Malformed wasm, duplicate import sections, NUL bytes inside import
// names, and unknown imports all fail closed.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `util.nu`
$ `caps.nu`

: WasmImp {
    String mod
    String name
    i kind
}

// True when `data` begins with the 4-byte WebAssembly magic `\0asm`.
@ cert_is_wasm ( Vec u ) data → b {
    ? < ( vec_len [u] data ) 4 { ^ F } {}
    : i b0 # i ( vec_at [u] data 0 )
    : i b1 # i ( vec_at [u] data 1 )
    : i b2 # i ( vec_at [u] data 2 )
    : i b3 # i ( vec_at [u] data 3 )
    ^ & & & == b0 0 == b1 97 == b2 115 == b3 109
}

// Read an unsigned 32-bit LEB128 integer at `pos` within `[0, lim)`.
// Rejects truncated encodings, more than 5 bytes, and 5th-byte overflow
// (bits 4..6 set).
@ __wm_u32 ( Vec u ) data i lim inout i pos → !i String {
    : ~ i out 0
    : ~ i shift 0
    : ~ i count 0
    ~ T {
        ? >= pos lim { ^ @ !i String { F ( string_from `truncated wasm LEB128` ) } } {}
        : i byte # i ( vec_at [u] data pos )
        = pos + pos 1
        = count + count 1
        ? > count 5 { ^ @ !i String { F ( string_from `wasm LEB128 exceeds 32 bits` ) } } {}
        ? & == count 5 > & byte 112 0 {
            ^ @ !i String { F ( string_from `wasm LEB128 overflows u32` ) }
        } {}
        = out + out << & byte 127 shift
        ? == & byte 128 0 { ^ @ !i String { T out } } {}
        = shift + shift 7
    }
    ^ @ !i String { F ( string_from `unreachable` ) }
}

// Read a length-prefixed UTF-8 name within `[0, lim)`. Rejects NUL bytes so
// C-string comparisons can never be truncated.
@ __wm_name ( Vec u ) data i lim inout i pos → !String String {
    : i n ?? ( __wm_u32 data lim pos ) {
        T v → v
        F e → { ^ @ !String String { F e } }
    }
    ? > + pos n lim { ^ @ !String String { F ( string_from `truncated wasm name` ) } } {}
    : String out ( string_new )
    : ~ i k 0
    ~ < k n {
        : i b # i ( vec_at [u] data + pos k )
        ? == b 0 { ^ @ !String String { F ( string_from `wasm import name holds a NUL byte` ) } } {}
        ( string_push_char out b )
        = k + k 1
    }
    = pos + pos n
    ^ @ !String String { T out }
}

// Skip a wasm limits descriptor (flags + min [+ max]) within `[0, lim)`.
@ __wm_skip_limits ( Vec u ) data i lim inout i pos → !i String {
    ? >= pos lim { ^ @ !i String { F ( string_from `truncated wasm limits` ) } } {}
    : i flags # i ( vec_at [u] data pos )
    = pos + pos 1
    ? > flags 7 { ^ @ !i String { F ( string_from `invalid wasm limits flags` ) } } {}
    ?? ( __wm_u32 data lim pos ) { T _ → {} F e → { ^ @ !i String { F e } } }
    ? != & flags 1 0 {
        ?? ( __wm_u32 data lim pos ) { T _ → {} F e → { ^ @ !i String { F e } } }
    } {}
    ^ @ !i String { T 0 }
}

// Parse the import section (id 2) of a WebAssembly binary.
@ cert_wasm_imports ( Vec u ) data → !( Vec WasmImp ) String {
    : i len ( vec_len [u] data )
    ? < len 8 { ^ @ !( Vec WasmImp ) String { F ( string_from `wasm binary shorter than 8-byte header` ) } } {}
    ? ! ( cert_is_wasm data ) { ^ @ !( Vec WasmImp ) String { F ( string_from `not a wasm binary` ) } } {}
    : i v0 # i ( vec_at [u] data 4 )
    : i v1 # i ( vec_at [u] data 5 )
    : i v2 # i ( vec_at [u] data 6 )
    : i v3 # i ( vec_at [u] data 7 )
    ? ! & & & == v0 1 == v1 0 == v2 0 == v3 0 {
        ^ @ !( Vec WasmImp ) String { F ( string_from `unsupported wasm binary version` ) }
    } {}
    : ( Vec WasmImp ) imps ( vec_new [WasmImp] )
    : ~ i pos 8
    : ~ i last_sec 0
    : ~ b seen_imp F
    ~ < pos len {
        : i sec_id # i ( vec_at [u] data pos )
        = pos + pos 1
        ? > sec_id 12 { ^ @ !( Vec WasmImp ) String { F ( string_from `unknown wasm section id` ) } } {}
        ? > sec_id 0 {
            ? <= sec_id last_sec {
                ^ @ !( Vec WasmImp ) String { F ( string_from `out-of-order or duplicate wasm section` ) }
            } {}
            = last_sec sec_id
        } {}
        : i sec_sz ?? ( __wm_u32 data len pos ) {
            T v → v
            F e → { ^ @ !( Vec WasmImp ) String { F e } }
        }
        : i sec_end + pos sec_sz
        ? > sec_end len { ^ @ !( Vec WasmImp ) String { F ( string_from `truncated wasm section` ) } } {}
        ? == sec_id 2 {
            ? seen_imp { ^ @ !( Vec WasmImp ) String { F ( string_from `duplicate wasm import section` ) } } {}
            = seen_imp T
            : i cnt ?? ( __wm_u32 data sec_end pos ) {
                T v → v
                F e → { ^ @ !( Vec WasmImp ) String { F e } }
            }
            : ~ i k 0
            ~ < k cnt {
                : String m ?? ( __wm_name data sec_end pos ) {
                    T v → v
                    F e → { ^ @ !( Vec WasmImp ) String { F e } }
                }
                : String nm ?? ( __wm_name data sec_end pos ) {
                    T v → v
                    F e → { ^ @ !( Vec WasmImp ) String { F e } }
                }
                ? >= pos sec_end { ^ @ !( Vec WasmImp ) String { F ( string_from `truncated wasm import kind` ) } } {}
                : i kind # i ( vec_at [u] data pos )
                = pos + pos 1
                ? == kind 0 {
                    // func: typeidx
                    ?? ( __wm_u32 data sec_end pos ) { T _ → {} F e → { ^ @ !( Vec WasmImp ) String { F e } } }
                } {
                    ? == kind 1 {
                        // table: reftype (1 byte) + limits
                        ? >= pos sec_end { ^ @ !( Vec WasmImp ) String { F ( string_from `truncated wasm table import` ) } } {}
                        = pos + pos 1
                        ?? ( __wm_skip_limits data sec_end pos ) { T _ → {} F e → { ^ @ !( Vec WasmImp ) String { F e } } }
                    } {
                        ? == kind 2 {
                            // memory: limits
                            ?? ( __wm_skip_limits data sec_end pos ) { T _ → {} F e → { ^ @ !( Vec WasmImp ) String { F e } } }
                        } {
                            ? == kind 3 {
                                // global: valtype (1 byte) + mut (0 or 1)
                                ? > + pos 2 sec_end { ^ @ !( Vec WasmImp ) String { F ( string_from `truncated wasm global import` ) } } {}
                                : i mutb # i ( vec_at [u] data + pos 1 )
                                ? & != mutb 0 != mutb 1 { ^ @ !( Vec WasmImp ) String { F ( string_from `invalid wasm global mutability` ) } } {}
                                = pos + pos 2
                            } {
                                ? == kind 4 {
                                    // tag: attr (1 byte) + typeidx
                                    ? >= pos sec_end { ^ @ !( Vec WasmImp ) String { F ( string_from `truncated wasm tag import` ) } } {}
                                    = pos + pos 1
                                    ?? ( __wm_u32 data sec_end pos ) { T _ → {} F e → { ^ @ !( Vec WasmImp ) String { F e } } }
                                } {
                                    ^ @ !( Vec WasmImp ) String { F ( string_from `unknown wasm import kind` ) }
                                }
                            }
                        }
                    }
                }
                ( vec_push [WasmImp] imps @ WasmImp { m nm kind } )
                = k + k 1
            }
            ? != pos sec_end { ^ @ !( Vec WasmImp ) String { F ( string_from `trailing bytes in wasm import section` ) } } {}
        } {
            = pos sec_end
        }
    }
    ^ @ !( Vec WasmImp ) String { T imps }
}

@ __wm_has ( Vec String ) doors s cls → b {
    : i n ( vec_len [String] doors )
    : ~ i k 0
    ~ < k n {
        ? ( nc_is ( vec_at [String] doors k ) cls ) { ^ T } {}
        = k + k 1
    }
    ^ F
}

@ __wm_eq s a s b → b {
    ^ == 0 ( nurl_str_cmp a b )
}

// Check one wasm function import `(mod, name)` against the classes `N.cap`
// names (and the bundle's `caps.tsv` for `env` imports). Returns empty string
// when allowed, else the missing capability class(es).
@ __wm_imp_missing s mod s name ( Vec String ) doors ( Vec CapRow ) tab → String {
    ? ( __wm_eq mod `wasi_snapshot_preview1` ) {
        ? | ( __wm_eq name `args_get` ) ( __wm_eq name `args_sizes_get` ) {
            ? ( __wm_has doors `args` ) { ^ ( string_new ) } { ^ ( string_from `args` ) }
        } {}
        ? | ( __wm_eq name `environ_get` ) ( __wm_eq name `environ_sizes_get` ) {
            ? ( __wm_has doors `env` ) { ^ ( string_new ) } { ^ ( string_from `env` ) }
        } {}
        ? | ( __wm_eq name `clock_res_get` ) ( __wm_eq name `clock_time_get` ) {
            ? ( __wm_has doors `clock` ) { ^ ( string_new ) } { ^ ( string_from `clock` ) }
        } {}
        ? ( __wm_eq name `random_get` ) {
            ? ( __wm_has doors `random` ) { ^ ( string_new ) } { ^ ( string_from `random` ) }
        } {}
        ? ( __wm_eq name `proc_exit` ) {
            ? ( __wm_has doors `exit` ) { ^ ( string_new ) } { ^ ( string_from `exit` ) }
        } {}
        ? ( __wm_eq name `proc_raise` ) {
            ? ( __wm_has doors `proc.signal` ) { ^ ( string_new ) } { ^ ( string_from `proc.signal` ) }
        } {}
        ? ( __wm_eq name `sched_yield` ) {
            ? ( __wm_has doors `thread` ) { ^ ( string_new ) } { ^ ( string_from `thread` ) }
        } {}
        ? ( __wm_eq name `fd_write` ) {
            ? | | | ( __wm_has doors `stdio.out` ) ( __wm_has doors `stdio.err` ) ( __wm_has doors `fd` ) ( __wm_has doors `fs.write` ) {
                ^ ( string_new )
            } { ^ ( string_from `stdio.out/fd/fs.write` ) }
        } {}
        ? ( __wm_eq name `fd_read` ) {
            ? | | | ( __wm_has doors `stdio.in` ) ( __wm_has doors `fd` ) ( __wm_has doors `fs.read` ) ( __wm_has doors `fs.write` ) {
                ^ ( string_new )
            } { ^ ( string_from `stdio.in/fd/fs.read` ) }
        } {}
        ? | | | | | | | | | | | | | | | |
        ( __wm_eq name `fd_close` ) ( __wm_eq name `fd_seek` ) ( __wm_eq name `fd_tell` )
        ( __wm_eq name `fd_fdstat_get` ) ( __wm_eq name `fd_fdstat_set_flags` ) ( __wm_eq name `fd_fdstat_set_rights` )
        ( __wm_eq name `fd_filestat_get` ) ( __wm_eq name `fd_filestat_set_size` ) ( __wm_eq name `fd_filestat_set_times` )
        ( __wm_eq name `fd_pread` ) ( __wm_eq name `fd_pwrite` ) ( __wm_eq name `fd_sync` )
        ( __wm_eq name `fd_datasync` ) ( __wm_eq name `fd_advise` ) ( __wm_eq name `fd_allocate` )
        ( __wm_eq name `fd_renumber` ) ( __wm_eq name `poll_oneoff` ) {
            ? | | ( __wm_has doors `fd` ) ( __wm_has doors `fs.write` ) ( __wm_has doors `fs.read` ) {
                ^ ( string_new )
            } { ^ ( string_from `fd` ) }
        } {}
        ? | | | | ( __wm_eq name `fd_prestat_get` ) ( __wm_eq name `fd_prestat_dir_name` )
        ( __wm_eq name `fd_readdir` ) ( __wm_eq name `path_filestat_get` ) ( __wm_eq name `path_readlink` ) {
            ? | | ( __wm_has doors `fs.meta` ) ( __wm_has doors `fs.read` ) ( __wm_has doors `fs.write` ) {
                ^ ( string_new )
            } { ^ ( string_from `fs.meta` ) }
        } {}
        ? ( __wm_eq name `path_open` ) {
            ? | ( __wm_has doors `fs.write` ) ( __wm_has doors `fs.read` ) {
                ^ ( string_new )
            } { ^ ( string_from `fs.read/fs.write` ) }
        } {}
        ? | | | | | | ( __wm_eq name `path_create_directory` ) ( __wm_eq name `path_unlink_file` )
        ( __wm_eq name `path_remove_directory` ) ( __wm_eq name `path_rename` )
        ( __wm_eq name `path_link` ) ( __wm_eq name `path_symlink` ) ( __wm_eq name `path_filestat_set_times` ) {
            ? ( __wm_has doors `fs.write` ) { ^ ( string_new ) } { ^ ( string_from `fs.write` ) }
        } {}
        ? ( __wm_eq name `sock_accept` ) {
            ? ( __wm_has doors `net.listen` ) { ^ ( string_new ) } { ^ ( string_from `net.listen` ) }
        } {}
        ? | | ( __wm_eq name `sock_recv` ) ( __wm_eq name `sock_send` ) ( __wm_eq name `sock_shutdown` ) {
            ? ( __wm_has doors `net.io` ) { ^ ( string_new ) } { ^ ( string_from `net.io` ) }
        } {}
        ? ( __wm_has doors `ffi.unknown` ) { ^ ( string_new ) } { ^ ( string_from `ffi.unknown` ) }
    } {}
    ? ( __wm_eq mod `nurl_net` ) {
        ? | | ( __wm_eq name `tcp_listen` ) ( __wm_eq name `tcp_accept` ) ( __wm_eq name `udp_bind` ) {
            ? ( __wm_has doors `net.listen` ) { ^ ( string_new ) } { ^ ( string_from `net.listen` ) }
        } {}
        ? | | ( __wm_eq name `tcp_connect` ) ( __wm_eq name `udp_connect` ) ( __wm_eq name `udp_send_to` ) {
            ? ( __wm_has doors `net.connect` ) { ^ ( string_new ) } { ^ ( string_from `net.connect` ) }
        } {}
        ? | | | | | | | | | | | | | | | | | | | | | | | | | | | | | | |
        ( __wm_eq name `tcp_read` ) ( __wm_eq name `tcp_write` ) ( __wm_eq name `tcp_close` )
        ( __wm_eq name `tcp_shutdown` ) ( __wm_eq name `tcp_err_kind` ) ( __wm_eq name `tcp_set_timeout` )
        ( __wm_eq name `tcp_set_send_buffer` ) ( __wm_eq name `tcp_timeout_ms` )
        ( __wm_eq name `tcp_set_write_deadline` ) ( __wm_eq name `tcp_write_deadline` )
        ( __wm_eq name `tcp_write_wait_ms` ) ( __wm_eq name `tcp_write_nowait` )
        ( __wm_eq name `tcp_wait_io` ) ( __wm_eq name `tcp_read_nowait` )
        ( __wm_eq name `tcp_peer_addr` ) ( __wm_eq name `tcp_local_addr` )
        ( __wm_eq name `tcp_get_fd` ) ( __wm_eq name `tcp_set_nonblock` )
        ( __wm_eq name `tcp_ref` ) ( __wm_eq name `tcp_unref` )
        ( __wm_eq name `udp_send` ) ( __wm_eq name `udp_recv` ) ( __wm_eq name `udp_recv_from` )
        ( __wm_eq name `udp_close` ) ( __wm_eq name `udp_err_kind` )
        ( __wm_eq name `udp_peer_addr` ) ( __wm_eq name `udp_local_addr` )
        ( __wm_eq name `udp_set_timeout` ) ( __wm_eq name `udp_set_nonblock` )
        ( __wm_eq name `udp_family` ) ( __wm_eq name `udp_get_fd` ) ( __wm_eq name `udp_set_broadcast` ) {
            ? ( __wm_has doors `net.io` ) { ^ ( string_new ) } { ^ ( string_from `net.io` ) }
        } {}
        ? ( __wm_has doors `ffi.unknown` ) { ^ ( string_new ) } { ^ ( string_from `ffi.unknown` ) }
    } {}
    ? | ( __wm_eq mod `canvas` ) ( __wm_eq mod `audio` ) {
        ? ( __wm_has doors `device` ) { ^ ( string_new ) } { ^ ( string_from `device` ) }
    } {}
    ? & ( __wm_eq mod `wasi` ) ( __wm_eq name `thread-spawn` ) {
        ? ( __wm_has doors `thread` ) { ^ ( string_new ) } { ^ ( string_from `thread` ) }
    } {}
    ? ( __wm_eq mod `env` ) {
        : String cls ( cert_caps_class_of tab name )
        ? | ( nc_is cls `compute` ) ( nc_is cls `mem` ) { ^ ( string_new ) } {}
        ? ( __wm_has doors ( string_data cls ) ) { ^ ( string_new ) } { ^ cls }
    } {}
    ? ( __wm_has doors `ffi.unknown` ) { ^ ( string_new ) } { ^ ( string_from `ffi.unknown` ) }
}

// Check a wasm binary's import section against the classes `N.cap` names.
// Returns empty string when every function import is covered, else a detail
// string naming the parse error or each unlisted import.
@ cert_wasm_check_caps ( Vec u ) data ( Vec String ) doors ( Vec CapRow ) tab → String {
    : ( Vec WasmImp ) imps ?? ( cert_wasm_imports data ) {
        T v → v
        F e → { ^ e }
    }
    : String bad ( string_new )
    : i n ( vec_len [WasmImp] imps )
    : ~ i k 0
    ~ < k n {
        : WasmImp imp ( vec_at [WasmImp] imps k )
        ? == . imp kind 0 {
            : String miss ( __wm_imp_missing ( string_data . imp mod ) ( string_data . imp name ) doors tab )
            ? > ( string_len miss ) 0 {
                ? > ( string_len bad ) 0 { ( string_push_str bad `, ` ) } { ( string_push_str bad `unlisted import(s): ` ) }
                ( string_push_str bad ( string_data . imp mod ) )
                ( string_push_str bad `.` )
                ( string_push_str bad ( string_data . imp name ) )
                ( string_push_str bad ` (` )
                ( string_push_str bad ( string_data miss ) )
                ( string_push_str bad `)` )
            } {}
        } {}
        = k + k 1
    }
    ^ bad
}
