// stdlib/ext/pkg_publish.nu — package + authenticated publish (write side).
//
// `pkg_pack` walks a project directory, packs the source files into a
// `.tar.gz` (the same format the install side fetches), and `pkg_publish`
// uploads it to the registry's write endpoint with a Bearer token:
//
//   POST <registry>/api/v1/publish
//   Authorization: Bearer <token>
//   X-Nurl-Package: <name>
//   X-Nurl-Version: <version>
//   X-Nurl-Deps: [{"name":"bar","req":"^0.3"}]   (registry deps; for the index)
//   Content-Type: application/gzip
//   <body = the .tar.gz bytes>
//
// The token is the caller's concern (CLI reads $NURL_TOKEN). The registry
// recomputes the tarball's SHA-256 server-side — it never trusts a
// client-supplied digest — and is responsible for name ownership +
// immutability (a version may not be overwritten).
//
// Packaging excludes installed deps and VCS/build noise: `deps`, `.git`,
// `nurl.lock`, `target`, `build`, any dotfile/dotdir, and compiler/linker
// output by extension (`.ll`, `.o`, `.obj`, `.a`, `.so`, `.dylib`, `.dll`,
// `.exe`). That last class is what keeps a tarball REPRODUCIBLE: without it
// the bytes depend on whether anyone happened to build in that checkout.
// Note the blacklist is still extension-based, so an extensionless compiled
// binary left in the package root (what `nurlpkg build` emits) would still
// be packed — `build`/`target` are the intended homes for it.
// Member paths use the 100-byte USTAR `name` field (PackTooLong otherwise).
//
// API:
//   ( pkg_pack root )                              → ! ( Vec u ) PackErr
//   ( pkg_publish registry token tarball name ver deps_json ) → ! i PublishErr (0 = ok)
//   ( pack_err_name e ) / ( publish_err_name e )    → s

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/tar.nu`
$ `stdlib/ext/compress.nu`
$ `stdlib/ext/http_cli.nu`

: | PackErr {
    PackReadFailed  // dir_list / read_file failed
    PackEmpty  // no files to pack
    PackTarFailed  // tar_create rejected a path (too long) / failed
    PackGzipFailed  // gzip_compress failed
}

: | PublishErr {
    PubNoToken  // empty auth token
    PubHttp  // transport failure, cause not classified
    // The transport knows *why* it failed (curl's exit code, mapped to
    // HttpcErr). Collapsing that into one PubHttp threw the diagnosis away
    // and left `publish failed (PubHttp)` — indistinguishable between a
    // dead registry, a broken proxy, and a stalled upload. Keep it.
    PubTimeout  // no response within the deadline — request stalled mid-flight
    PubConnect  // could not establish the connection
    PubDns  // registry host does not resolve
    PubTls  // TLS handshake / certificate failure
    PubAuth  // 401 — a real auth/token failure (expired, wrong, or missing)
    PubForbidden  // 403 — reserved name, typosquat lookalike, or the token's
    // package scope. NOT an auth problem, so it must not suggest re-login.
    PubConflict  // 409 — version already published (immutability)
    PubRejected  // any other non-2xx
}

@ pack_err_name PackErr e → s {
    ^ ?? e {
        PackReadFailed → `PackReadFailed`
        PackEmpty → `PackEmpty`
        PackTarFailed → `PackTarFailed`
        PackGzipFailed → `PackGzipFailed`
    }
}

// Carry the transport's own diagnosis through to the caller.
@ __pub_transport_err HttpcErr e → PublishErr {
    ^ ?? e {
        HttpcTimeout → # PublishErr PubTimeout
        HttpcConnect → # PublishErr PubConnect
        HttpcDns → # PublishErr PubDns
        HttpcTls → # PublishErr PubTls
        _ → # PublishErr PubHttp
    }
}

@ publish_err_name PublishErr e → s {
    ^ ?? e {
        PubNoToken → `PubNoToken`
        PubHttp → `PubHttp`
        PubTimeout → `PubTimeout`
        PubConnect → `PubConnect`
        PubDns → `PubDns`
        PubTls → `PubTls`
        PubAuth → `PubAuth`
        PubForbidden → `PubForbidden`
        PubConflict → `PubConflict`
        PubRejected → `PubRejected`
    }
}

// True iff `name` ends with `ext` (an extension, dot included).
@ __pack_has_ext s name s ext → b {
    : String ns ( string_from name )
    : b r ( string_ends_with ns ext )
    ( string_free ns )
    ^ r
}

// Compiler and linker output. These are produced *inside* the package
// directory by `nurlpkg build` / `nurlc` and are never package source, so
// packing them makes the tarball depend on whether someone happened to
// build in that checkout — two clean clones of one commit then publish
// different bytes under different checksums. (Real case: a stray 1.4 MB
// `wasmbuilder.ll` packed to 269 KB in one clone and 36 KB in another.)
@ __pack_build_output s name → b {
    ? ( __pack_has_ext name `.ll` ) { ^ T } {}
    ? ( __pack_has_ext name `.o` ) { ^ T } {}
    ? ( __pack_has_ext name `.obj` ) { ^ T } {}
    ? ( __pack_has_ext name `.a` ) { ^ T } {}
    ? ( __pack_has_ext name `.so` ) { ^ T } {}
    ? ( __pack_has_ext name `.dylib` ) { ^ T } {}
    ? ( __pack_has_ext name `.dll` ) { ^ T } {}
    ? ( __pack_has_ext name `.exe` ) { ^ T } {}
    ^ F
}

// True iff `name` has no extension — no `.` anywhere. A built binary on
// Linux and macOS is named after its package and carries none; a source
// file or a data fixture essentially always does.
@ __pack_extensionless s name → b {
    : i n ( nurl_str_len name )
    : ~ i k 0
    ~ < k n {
        ? == ( nurl_str_get name k ) 46 { ^ F } {}
        = k + k 1
    }
    ^ T
}

// Version control, editor and local-toolchain noise. NOT "every name
// starting with a dot": that rule dropped whole directories a package
// meant to ship — `mermaid-server` keeps its themes in `.templates/`, and
// publishing it silently produced a tarball that installed and then
// refused to start, with `--dry-run` reporting every gate passed. A
// package's own dot-prefixed data is source like any other; only the
// things below are never part of one.
@ __pack_ignored s name → b {
    ? != 0 ( nurl_str_eq name `deps` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `nurl.lock` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `target` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `build` ) { ^ T } {}
    ? ( __pack_build_output name ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `.git` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `.github` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `.gitignore` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `.gitattributes` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `.gitmodules` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `.hg` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `.svn` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `.DS_Store` ) { ^ T } {}
    ? != 0 ( nurl_str_eq name `.nurl-bin` ) { ^ T } {}
    ^ F
}

// An executable image, by its first bytes. The extension list above names
// the build output a Windows or intermediate artefact carries; the binary
// `nurlpkg build` produces on Linux and macOS carries NONE — it is named
// after the package — so it walked straight into the tarball. Publishing
// `mermaid-server` would have shipped a 540 KB Linux ELF to every user,
// and the tarball's checksum would have depended on whether the publisher
// happened to have built in that checkout: the same drift the `.ll` rule
// above was written for, through the door it left open.
//
// Only consulted for an EXTENSIONLESS file, so a `.wasm` fixture or a
// `.so` a package deliberately ships is not caught by a magic number it
// legitimately has.
@ __pack_is_executable_image ( Vec u ) bytes → b {
    ? < ( vec_len [u] bytes ) 4 { ^ F } {}
    : i b0 ( __pack_byte bytes 0 )
    : i b1 ( __pack_byte bytes 1 )
    : i b2 ( __pack_byte bytes 2 )
    : i b3 ( __pack_byte bytes 3 )
    // ELF
    ? & & & == b0 127 == b1 69 == b2 76 == b3 70 { ^ T } {}
    // PE / MZ
    ? & == b0 77 == b1 90 { ^ T } {}
    // Mach-O, both endians and the fat header
    ? & & & == b0 254 == b1 237 == b2 250 | == b3 206 == b3 207 { ^ T } {}
    ? & & & == b0 207 == b1 250 == b2 237 == b3 254 { ^ T } {}
    ? & & & == b0 202 == b1 254 == b2 186 == b3 190 { ^ T } {}
    ^ F
}

@ __pack_byte ( Vec u ) bytes i idx → i {
    ?? ( vec_get [u] bytes idx ) {
        T b → ^ # i b
        F _ → {}
    }
    ^ - 0 1
}

// The package's own `.gitignore`, as a list of patterns. It is the
// author's existing statement of what in this directory is NOT source,
// which is exactly the question the packer has to answer — and it is
// already written, in every package, without a second manifest key to
// keep in sync.
//
// Read per DIRECTORY as the walk descends and merged with what the
// parents said, the way git applies them — `yoloe-demo` keeps the
// `.gitignore` covering its generated 900 KB test frame in `tests/`, not
// at the package root.
//
// Supported: a bare name (`nurl.lock`), a rooted name (`/mermaid-server`)
// and an extension glob (`*.ll`, `*.svg`). Anything else is kept, because
// a pattern the packer misreads must fail towards SHIPPING the file: a
// tarball with one file too many is a nuisance, one missing the templates
// the program loads at startup is a package that installs and then cannot
// run.
@ __pack_read_ignores s dir → ( Vec String ) {
    : ( Vec String ) pats ( vec_new [String] )
    : String path ( string_from dir )
    ( string_push_str path `/.gitignore` )
    ?? ( read_file ( string_data path ) ) {
        T text → {
            : ( Vec String ) lines ( string_split text `\n` )
            : i n ( vec_len [String] lines )
            : ~ i k 0
            ~ < k n {
                ?? ( vec_get [String] lines k ) {
                    T raw → {
                        : String t ( string_trim raw )
                        : i tl ( string_len t )
                        : b keep & > tl 0 & != ( string_get t 0 ) 35 != ( string_get t 0 ) 33
                        ? keep {
                            : ~ i from ? == ( string_get t 0 ) 47 1 0
                            : ~ i to tl
                            ? & > to from == ( string_get t - to 1 ) 47 { = to - to 1 } {}
                            ( vec_push [String] pats ( string_substr t from - to from ) )
                        } {}
                        ( string_free t )
                        ( string_free raw )
                    }
                    F _ → {}
                }
                = k + k 1
            }
            ( vec_free [String] lines )
            ( string_free text )
        }
        F _ → {}
    }
    ( string_free path )
    ^ pats
}

@ __pack_gitignored ( Vec String ) pats s name → b {
    : i n ( vec_len [String] pats )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [String] pats k ) {
            T pat → {
                : s ps ( string_data pat )
                ? != 0 ( nurl_str_eq ps name ) { ^ T } {}
                // `*.ext`
                ? & > ( nurl_str_len ps ) 1 == ( nurl_str_get ps 0 ) 42 {
                    : s ext ( nurl_str_slice ps 1 - ( nurl_str_len ps ) 1 )
                    : b hit ( __pack_has_ext name ext )
                    ? hit { ^ T } {}
                } {}
            }
            F _ → {}
        }
        = k + k 1
    }
    ^ F
}

// Recursively collect files under `root`/`rel` into `out` as TarEntries
// keyed by their path relative to `root`. Returns 0 on success, 1 on I/O
// failure.
@ __pack_collect s root s rel ( Vec TarEntry ) out ( Vec String ) ignores → i {
    : String dir ( string_from root )
    ? > ( nurl_str_len rel ) 0 {
        ( string_push_char dir 47 )
        ( string_push_str dir rel )
    } {}
    // This directory's own `.gitignore`, on top of what the parents said.
    : ( Vec String ) here ( __pack_read_ignores ( string_data dir ) )
    : ( Vec String ) scope ( vec_new [String] )
    : ~ i ci 0
    ~ < ci ( vec_len [String] ignores ) {
        ?? ( vec_get [String] ignores ci ) {
            T pp → ( vec_push [String] scope ( string_clone pp ) )
            F _ → {}
        }
        = ci + ci 1
    }
    ( vec_extend [String] scope here )
    ( vec_free [String] here )
    : !( Vec String ) IoErr lr ( dir_list ( string_data dir ) )
    : ~ i rc 0
    ?? lr {
        F _ → { = rc 1 }
        T entries → {
            : i n ( vec_len [String] entries )
            : ~ i k 0
            ~ < k n {
                : ?String eo ( vec_get [String] entries k )
                ?? eo {
                    T nm → {
                        : s nm_s ( string_data nm )
                        : b skip | ( __pack_ignored nm_s ) ( __pack_gitignored scope nm_s )
                        ? ! skip {
                            : String relpath ( string_new )
                            ? > ( nurl_str_len rel ) 0 {
                                ( string_push_str relpath rel )
                                ( string_push_char relpath 47 )
                            } {}
                            ( string_push_str relpath nm_s )
                            : String full ( string_from root )
                            ( string_push_char full 47 )
                            ( string_push_str full ( string_data relpath ) )
                            : i t ( nurl_path_type ( string_data full ) )
                            ? == t 1 {
                                : !( Vec u ) IoErr fb ( read_file_bytes ( string_data full ) )
                                ?? fb {
                                    T bytes → {
                                        // The extensionless-binary test needs the
                                        // CONTENT, so it runs here rather than in
                                        // __pack_ignored — the bytes are already
                                        // read, so it costs no extra I/O.
                                        ? & ( __pack_extensionless nm_s )
                                        ( __pack_is_executable_image bytes )
                                        { ( vec_free [u] bytes ) }
                                        { ( vec_push [TarEntry] out ( tar_entry_file ( string_data relpath ) bytes ) ) }
                                    }
                                    F _ → { = rc 1 }
                                }
                            } {
                                ? == t 2 {
                                    : i sub ( __pack_collect root ( string_data relpath ) out scope )
                                    ? != sub 0 { = rc 1 } {}
                                } {}
                            }
                            ( string_free relpath )
                            ( string_free full )
                        } {}
                        ( string_free nm )
                    }
                    F → {}
                }
                = k + k 1
            }
            ( vec_free [String] entries )
        }
    }
    ( vec_free_with [String] scope \ String p → v { ( string_free p ) } )
    ( string_free dir )
    ^ rc
}

// The paths `pkg_pack` would put in the tarball, in walk order. What a
// publisher actually needs to see before uploading: the packer's job is
// deciding what is source, and it used to make that decision in total
// silence — a shipped `.templates/` dropped and a 540 KB binary added
// both looked exactly like success.
@ pkg_pack_list s root → !( Vec String ) PackErr {
    : ( Vec TarEntry ) ents ( vec_new [TarEntry] )
    : ( Vec String ) ignores ( __pack_read_ignores root )
    : i cr ( __pack_collect root `` ents ignores )
    ( vec_free_with [String] ignores \ String p → v { ( string_free p ) } )
    ? != cr 0 {
        ( tar_entries_free ents )
        ^ @ !( Vec String ) PackErr { F # PackErr PackReadFailed }
    } {}
    : ( Vec String ) names ( vec_new [String] )
    : i n ( vec_len [TarEntry] ents )
    : ~ i k 0
    ~ < k n {
        ?? ( vec_get [TarEntry] ents k ) {
            T e → ( vec_push [String] names ( string_clone . e path ) )
            F _ → {}
        }
        = k + k 1
    }
    ( tar_entries_free ents )
    ^ @ !( Vec String ) PackErr { T names }
}

@ pkg_pack s root → !( Vec u ) PackErr {
    : ( Vec TarEntry ) ents ( vec_new [TarEntry] )
    : ( Vec String ) ignores ( __pack_read_ignores root )
    : i cr ( __pack_collect root `` ents ignores )
    ( vec_free_with [String] ignores \ String p → v { ( string_free p ) } )
    ? != cr 0 {
        ( tar_entries_free ents )
        ^ @ !( Vec u ) PackErr { F # PackErr PackReadFailed }
    } {}
    ? == ( vec_len [TarEntry] ents ) 0 {
        ( tar_entries_free ents )
        ^ @ !( Vec u ) PackErr { F # PackErr PackEmpty }
    } {}
    : !( Vec u ) TarErr tr ( tar_create ents )
    ( tar_entries_free ents )
    ?? tr {
        F _ → ^ @ !( Vec u ) PackErr { F # PackErr PackTarFailed }
        T arc → {
            : !( Vec u ) CompressErr gr ( gzip_compress arc )
            ( vec_free [u] arc )
            ?? gr {
                F _ → ^ @ !( Vec u ) PackErr { F # PackErr PackGzipFailed }
                T gz → ^ @ !( Vec u ) PackErr { T gz }
            }
        }
    }
}

// <registry>/api/v1/publish  (single '/' separator ensured)
@ __publish_url s registry → String {
    : String out ( string_with_cap 64 )
    ( string_push_str out registry )
    : i rn ( nurl_str_len registry )
    ? > rn 0 { ? != ( nurl_str_get registry - rn 1 ) 47 { ( string_push_char out 47 ) } {} } {}
    ( string_push_str out `api/v1/publish` )
    ^ out
}

// `deps_json` is a JSON array of { name, req } for this package's registry
// dependencies (built by the caller from the manifest), sent as
// X-Nurl-Deps so the registry records them in the index and transitive
// registry resolution works. Pass `[]` (or empty) for none.
@ pkg_publish s registry s token ( Vec u ) tarball s name s version s deps_json → !i PublishErr {
    ? == ( nurl_str_len token ) 0 { ^ @ !i PublishErr { F # PublishErr PubNoToken } } {}
    : String url ( __publish_url registry )
    : String hb ( string_with_cap 256 )
    ( string_push_str hb `Authorization: Bearer ` )
    ( string_push_str hb token )
    ( string_push_str hb `\r\n` )
    ( string_push_str hb `X-Nurl-Package: ` )
    ( string_push_str hb name )
    ( string_push_str hb `\r\n` )
    ( string_push_str hb `X-Nurl-Version: ` )
    ( string_push_str hb version )
    ( string_push_str hb `\r\n` )
    ? > ( nurl_str_len deps_json ) 0 {
        ( string_push_str hb `X-Nurl-Deps: ` )
        ( string_push_str hb deps_json )
        ( string_push_str hb `\r\n` )
    } {}
    ( string_push_str hb `Content-Type: application/gzip\r\n` )
    : !HttpcResp HttpcErr rr ( httpc_request_bytes `POST` ( string_data url ) tarball ( string_data hb ) )
    ( string_free url )
    ( string_free hb )
    ?? rr {
        F he → ^ @ !i PublishErr { F ( __pub_transport_err he ) }
        T resp → {
            : i st ( httpc_status resp )
            ( httpc_resp_free resp )
            ^ ( __pub_status_map st )
        }
    }
}

// ── Yank / unyank / token revoke (authenticated, no body) ─────────────

@ __reg_api_url s registry s path → String {
    : String out ( string_with_cap 64 )
    ( string_push_str out registry )
    : i rn ( nurl_str_len registry )
    ? > rn 0 { ? != ( nurl_str_get registry - rn 1 ) 47 { ( string_push_char out 47 ) } {} } {}
    ( string_push_str out path )
    ^ out
}

// Map an HTTP status to a PublishErr. Only 401 is an auth failure; 403
// (reserved_name / token_scope / name_too_similar) is a distinct, non-auth
// rejection, so a name problem is never mislabelled as an expired token.
@ __pub_status_map i st → !i PublishErr {
    ? & >= st 200 < st 300 { ^ @ !i PublishErr { T 0 } } {}
    ? == st 401 { ^ @ !i PublishErr { F # PublishErr PubAuth } } {}
    ? == st 403 { ^ @ !i PublishErr { F # PublishErr PubForbidden } } {}
    ? == st 409 { ^ @ !i PublishErr { F # PublishErr PubConflict } } {}
    ^ @ !i PublishErr { F # PublishErr PubRejected }
}

// POST <registry>/api/v1/revoke — deletes the presented token server-side.
@ pkg_revoke s registry s token → !i PublishErr {
    ? == ( nurl_str_len token ) 0 { ^ @ !i PublishErr { F # PublishErr PubNoToken } } {}
    : String url ( __reg_api_url registry `api/v1/revoke` )
    : String hb ( string_with_cap 96 )
    ( string_push_str hb `Authorization: Bearer ` )
    ( string_push_str hb token )
    ( string_push_str hb `\r\n` )
    : !HttpcResp HttpcErr rr ( httpc_request `POST` ( string_data url ) `` ( string_data hb ) )
    ( string_free url )
    ( string_free hb )
    ?? rr {
        F he → ^ @ !i PublishErr { F ( __pub_transport_err he ) }
        T resp → {
            : i st ( httpc_status resp )
            ( httpc_resp_free resp )
            ^ ( __pub_status_map st )
        }
    }
}

// POST <registry>/api/v1/{yank,unyank} — owner-only; flips the version's
// yanked flag (the resolver then skips yanked versions). `yank` != 0 to
// yank, 0 to unyank.
@ pkg_yank s registry s token s name s version i yank → !i PublishErr {
    ? == ( nurl_str_len token ) 0 { ^ @ !i PublishErr { F # PublishErr PubNoToken } } {}
    : s ep ? != yank 0 `api/v1/yank` `api/v1/unyank`
    : String url ( __reg_api_url registry ep )
    : String hb ( string_with_cap 160 )
    ( string_push_str hb `Authorization: Bearer ` )
    ( string_push_str hb token )
    ( string_push_str hb `\r\n` )
    ( string_push_str hb `X-Nurl-Package: ` )
    ( string_push_str hb name )
    ( string_push_str hb `\r\n` )
    ( string_push_str hb `X-Nurl-Version: ` )
    ( string_push_str hb version )
    ( string_push_str hb `\r\n` )
    : !HttpcResp HttpcErr rr ( httpc_request `POST` ( string_data url ) `` ( string_data hb ) )
    ( string_free url )
    ( string_free hb )
    ?? rr {
        F he → ^ @ !i PublishErr { F ( __pub_transport_err he ) }
        T resp → {
            : i st ( httpc_status resp )
            ( httpc_resp_free resp )
            ^ ( __pub_status_map st )
        }
    }
}
