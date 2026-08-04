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
// Everything is loopback — no third-party host is contacted, but the
// client half goes through nurlpkg, whose HTTP transport shells out to
// the `curl` BINARY (ext/http_cli.nu: no libcurl link, on purpose). On a
// host without curl the fetch fails at the transport layer and the
// client thread never reaches the registry, so the server thread's join
// never returns — the FreeBSD CI VM, which ships no curl, hung here.
// requires: live curl

$ `stdlib/std/net.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/std/time.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/hash_sha256.nu`
$ `stdlib/std/ed25519.nu`
$ `stdlib/std/encode.nu`
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

// Deterministic 32-byte Ed25519 seed + 8-byte keyid for the test registry
// key. The e2e proves nurlpkg's mandatory signature check against a key it
// controls, via the $NURL_REGISTRY_PUBKEY trust-anchor override.
@ test_seed → ( Vec u ) {
    : ( Vec u ) s ( vec_new [u] )
    : ~ i k 0
    ~ < k 32 { ( vec_push [u] s # u + * k 7 3 ) = k + k 1 }
    ^ s
}

@ test_keyid → ( Vec u ) {
    : ( Vec u ) s ( vec_new [u] )
    : ~ i k 0
    ~ < k 8 { ( vec_push [u] s # u + k 10 ) = k + k 1 }
    ^ s
}

// minisign pubkey payload line: base64( 'Ed' | keyid(8) | pubkey(32) ).
@ build_publine ( Vec u ) keyid ( Vec u ) pubkey → String {
    : ( Vec u ) raw ( vec_new [u] )
    ( vec_push [u] raw # u 69 )
    ( vec_push [u] raw # u 100 )
    ( bytes_extend_bytes raw keyid )
    ( bytes_extend_bytes raw pubkey )
    : String b64 ( b64_encode_vec raw )
    ( vec_free [u] raw )
    ^ b64
}

// A full .minisig text signing `tarball` in legacy 'Ed' mode (raw Ed25519).
@ build_sigtext ( Vec u ) keyid ( Vec u ) sig → String {
    : ( Vec u ) raw ( vec_new [u] )
    ( vec_push [u] raw # u 69 )
    ( vec_push [u] raw # u 100 )
    ( bytes_extend_bytes raw keyid )
    ( bytes_extend_bytes raw sig )
    : String line ( b64_encode_vec raw )
    ( vec_free [u] raw )
    : String out ( string_with_cap 160 )
    ( string_push_str out `untrusted comment: nurl e2e test signature
` )
    ( string_push_str out ( string_data line ) )
    ( string_push_char out 10 )
    ( string_free line )
    ^ out
}

@ run_e2e → v {
    : ( Vec u ) tarball ( build_tarball )
    : String index ( build_index tarball )

    // Sign the tarball with the test key + advertise its pubkey as the pin.
    : ( Vec u ) seed ( test_seed )
    : ( Vec u ) keyid ( test_keyid )
    : ( Vec u ) pubkey ( ed25519_pubkey_pure seed )
    : String publine ( build_publine keyid pubkey )
    : !v IoErr es ( env_set `NURL_REGISTRY_PUBKEY` ( string_data publine ) )
    ?? es { T _ → {} F _ → {} }
    : ( Vec u ) sigbytes ( ed25519_sign_pure seed tarball )
    : String sigtext ( build_sigtext keyid sigbytes )
    ( vec_free [u] seed )
    ( vec_free [u] keyid )
    ( vec_free [u] pubkey )
    ( vec_free [u] sigbytes )
    ( string_free publine )

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
                ? != 0 ( nurl_str_eq path `/pkgs/foo/foo-1.0.0.tar.gz.minisig` ) {
                    ^ ( response_text 200 ( string_data sigtext ) )
                } {}
                ? != 0 ( nurl_str_eq path `/pkgs/foo/foo-1.0.0.tar.gz` ) {
                    : HttpResponse resp ( response_new 200 )
                    ( response_set_body_bytes resp tarball )
                    ^ resp
                } {}
                // foo-2.0.0 exists as a tarball but has NO .minisig — the
                // fail-closed case: verification must reject it.
                ? != 0 ( nurl_str_eq path `/pkgs/foo/foo-2.0.0.tar.gz` ) {
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
                                // Fail-closed: foo-2.0.0 has no signature ⇒ reject
                                // (empty checksum skips the sha step, isolating the
                                // signature gate).
                                : !i PkgFetchErr nosig ( pkg_install_one REG nm `2.0.0` `` `/tmp/nurl_pkg_e2e_nosig` )
                                ?? nosig {
                                    T _ → ( nurl_print `nosig=accepted(bug)\n` )
                                    F e → { ( nurl_print `nosig=` ) ( nurl_print ( pkg_err_name e ) ) ( nurl_print `\n` ) }
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

            // Requests: index(1) + install-ok tarball+minisig(2) +
            // bad-checksum tarball(1) + nosig tarball+minisig-404(2) = 6.
            : ~ i served 0
            ~ < served 6 {
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
    : !v IoErr rm3 ( dir_remove_all `/tmp/nurl_pkg_e2e_nosig` )
    ?? rm3 { T _ → {} F _ → {} }
    ( vec_free [u] tarball )
    ( string_free index )
    ( string_free sigtext )
}

@ main → i {
    ( run_e2e )
    ( nurl_print `done\n` )
    ^ 0
}
