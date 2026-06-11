// pkg_install_e2e.nu — end-to-end registry install against a loopback
// NURL registry server. The capstone for ROADMAP §4 phase 4b: it proves
// the whole pure-NURL pipeline resolve → download → sha256-verify →
// gunzip → tar_unpack works against a real (loopback) static-HTTP
// registry, exactly the shape an R2+CDN registry serves.
//
// Setup: build a `foo-1.0.0.tar.gz` with tar_create + gzip_compress,
// compute its sha256 hex, bake it into the index JSON. A NURL HTTP server
// (handler captures the fixtures) serves:
//     GET /index/foo.json                 → the index
//     GET /pkgs/foo/foo-1.0.0.tar.gz       → the tarball bytes
// A client pthread resolves `foo ^1.0`, installs it into a temp deps dir,
// checks the unpacked files exist, then exercises a wrong-checksum reject.
// Gated behind NURL_NET_TESTS=1.

$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/ext/http_server.nu`
$ `stdlib/ext/http_response.nu`
$ `stdlib/ext/http_request.nu`
$ `stdlib/ext/compress.nu`
$ `stdlib/ext/tar.nu`
$ `stdlib/ext/manifest.nu`
$ `stdlib/ext/lockfile.nu`
$ `stdlib/ext/resolver.nu`
$ `stdlib/ext/pkg_fetch.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`

@ reg_dep s name s req → Dep {
    ^ @ Dep { ( string_from name ) ( string_new ) ( string_from req ) ( string_new ) }
}

@ deps_free ( Vec Dep ) v → v {
    : i n ( vec_len [Dep] v )
    : ~ i k 0
    ~ < k n { : ?Dep d ( vec_get [Dep] v k ) ?? d { T dv → ( dep_free dv ) F → {} } = k + k 1 }
    ( vec_free [Dep] v )
}

// Build the tarball bytes for the fake `foo` package.
@ build_tarball → ( Vec u ) {
    : ( Vec TarEntry ) ents ( vec_new [TarEntry] )
    ( vec_push [TarEntry] ents ( tar_entry_file `nurl.toml` ( bytes_from_str `[package]
name = "foo"
version = "1.0.0"
` ) ) )
    ( vec_push [TarEntry] ents ( tar_entry_file `lib.nu` ( bytes_from_str `@ answer → i { ^ 42 }
` ) ) )
    : ~ ( Vec u ) out ( vec_new [u] )
    : !( Vec u ) TarErr cr ( tar_create ents )
    ?? cr {
        F _ → {}
        T arc → {
            : !( Vec u ) CompressErr gr ( gzip_compress arc )
            ?? gr { T gz → { ( vec_free [u] out ) = out gz } F _ → {} }
            ( vec_free [u] arc )
        }
    }
    ( tar_entries_free ents )
    ^ out
}

// Index JSON for foo 1.0.0 with the tarball's real checksum baked in.
@ build_index ( Vec u ) tarball → String {
    : ( Vec u ) digest ( sha256_pure tarball )
    : String hex ( bytes_to_hex digest )
    ( vec_free [u] digest )
    : String idx ( string_with_cap 160 )
    ( string_push_str idx `{ "name": "foo", "versions": [ { "version": "1.0.0", "checksum": "` )
    ( string_push_str idx ( string_data hex ) )
    ( string_push_str idx `", "deps": [] } ] }` )
    ( string_free hex )
    ^ idx
}

@ run_e2e → v {
    : ( Vec u ) tarball ( build_tarball )
    : String index ( build_index tarball )

    : !v IoErr rm0 ( dir_remove_all `/tmp/nurl_pkg_e2e` )
    ?? rm0 { T _ → {} F _ → {} }

    : !TcpListener NetErr lr ( tcp_listen `127.0.0.1` 18943 )
    ?? lr {
        T listener → {
            // Handler captures the fixtures (immutable by-value handles).
            : ( @ HttpResponse HttpRequest ) h \ HttpRequest req → HttpResponse {
                : s path ( string_data . req path )
                ? != 0 ( nurl_str_eq path `/index/foo.json` ) {
                    ^ ( response_text 200 ( string_data index ) )
                } {}
                ? != 0 ( nurl_str_eq path `/pkgs/foo/foo-1.0.0.tar.gz` ) {
                    : HttpResponse resp ( response_new 200 )
                    ( response_set_body_bytes resp tarball )
                    ^ resp
                } {}
                ^ ( response_text 404 `nope` )
            }
            : HttpServer srv ( server_new listener h )

            // Client makes exactly 3 requests (index, tarball, bad-checksum
            // tarball) — each a fresh libcurl connection. We answer them
            // with 3 blocking server_run_once calls on the main thread, so
            // no async runtime / shutdown handshake is needed.
            : ( @ v ) client \ → v {
                ( sleep_ms 300 )
                : s REG `http://127.0.0.1:18943/`
                : ( Vec Dep ) roots ( vec_new [Dep] )
                ( vec_push [Dep] roots ( reg_dep `foo` `^1.0` ) )
                : ( @ String s ) fetch \ s nm → String { ^ ( pkg_fetch_index `http://127.0.0.1:18943/` nm ) }
                : !( Vec LockPkg ) ResolveErr rr ( resolve_registry roots REG fetch )
                ?? rr {
                    F e → ( nurl_print `resolve_err\n` )
                    T locked → {
                        ( nurl_print `resolved=` ) ( nurl_print_int ( vec_len [LockPkg] locked ) ) ( nurl_print `\n` )
                        : ?LockPkg p0 ( vec_get [LockPkg] locked 0 )
                        ?? p0 {
                            T p → {
                                : s nm ( string_data . p name )
                                : s ver ( string_data . p version )
                                : s chk ( string_data . p checksum )
                                : !i PkgFetchErr ir ( pkg_install_one REG nm ver chk `/tmp/nurl_pkg_e2e` )
                                ?? ir {
                                    T _ → ( nurl_print `install=ok\n` )
                                    F e → { ( nurl_print `install_err=` ) ( nurl_print ( pkg_err_name e ) ) ( nurl_print `\n` ) }
                                }
                                : !i PkgFetchErr bad ( pkg_install_one REG nm ver `deadbeef` `/tmp/nurl_pkg_e2e_bad` )
                                ?? bad {
                                    T _ → ( nurl_print `badcheck=accepted(bug)\n` )
                                    F e → { ( nurl_print `badcheck=` ) ( nurl_print ( pkg_err_name e ) ) ( nurl_print `\n` ) }
                                }
                            }
                            F → {}
                        }
                        ( lockpkgs_free locked )
                    }
                }
                ( deps_free roots )
                ? ( file_exists `/tmp/nurl_pkg_e2e/foo/nurl.toml` ) { ( nurl_print `unpacked=T\n` ) } { ( nurl_print `unpacked=F\n` ) }
                ? ( file_exists `/tmp/nurl_pkg_e2e/foo/lib.nu` ) { ( nurl_print `lib_present=T\n` ) } { ( nurl_print `lib_present=F\n` ) }
            }
            : !Thread ThreadErr ct ( thread_spawn client )

            : ~ i served 0
            ~ < served 3 {
                : !v NetErr sr ( server_run_once srv )
                ?? sr { T _ → {} F _ → {} }
                = served + served 1
            }
            ?? ct { T t → ( thread_join t ) F _ → {} }
        }
        F e → ( nurl_print `listen_fail\n` )
    }
    : !v IoErr rm1 ( dir_remove_all `/tmp/nurl_pkg_e2e` )
    ?? rm1 { T _ → {} F _ → {} }
    : !v IoErr rm2 ( dir_remove_all `/tmp/nurl_pkg_e2e_bad` )
    ?? rm2 { T _ → {} F _ → {} }
    ( vec_free [u] tarball )
    ( string_free index )
}

@ main → i {
    : ?String gate ( env_get `NURL_NET_TESTS` )
    ?? gate {
        T s → { ( string_free s ) ( run_e2e ) ( nurl_print `done\n` ) }
        F → { ( nurl_print `pkg install e2e skipped (set NURL_NET_TESTS=1)\n` ) }
    }
    ^ 0
}
