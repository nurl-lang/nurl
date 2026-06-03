// resolver_basic.nu — registry dependency resolution with a mock index.
//
// roots: a path dep (ignored) + registry dep foo ^1.0.
//   foo: 1.0.0, 1.2.0 (deps bar ^0.3), 2.0.0  → picks 1.2.0
//   bar: 0.3.0, 0.3.5, 0.4.0                   → picks 0.3.5 (^0.3)
// Expected lock: bar 0.3.5 + foo 1.2.0 (sorted), each with source+checksum.
// Also: ResolveNoMatch and ResolveNotFound.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/manifest.nu`
$ `stdlib/ext/lockfile.nu`
$ `stdlib/ext/resolver.nu`

@ idx_for s name → String {
    ? != 0 ( nurl_str_eq name `foo` ) {
        ^ ( string_from `{ "name": "foo", "versions": [
          { "version": "1.0.0", "checksum": "f100", "deps": [] },
          { "version": "1.2.0", "checksum": "f120", "deps": [ { "name": "bar", "req": "^0.3" } ] },
          { "version": "2.0.0", "checksum": "f200", "deps": [] } ] }` )
    } {}
    ? != 0 ( nurl_str_eq name `bar` ) {
        ^ ( string_from `{ "name": "bar", "versions": [
          { "version": "0.3.0", "checksum": "b030", "deps": [] },
          { "version": "0.3.5", "checksum": "b035", "deps": [] },
          { "version": "0.4.0", "checksum": "b040", "deps": [] } ] }` )
    } {}
    ^ ( string_new )
}

@ reg_dep s name s req → Dep {
    ^ @ Dep { ( string_from name ) ( string_new ) ( string_from req ) ( string_new ) }
}

@ deps_free ( Vec Dep ) v → v {
    : i n ( vec_len [Dep] v )
    : ~ i k 0
    ~ < k n {
        : ?Dep d ( vec_get [Dep] v k )
        ?? d { T dv → ( dep_free dv ) F → {} }
        = k + k 1
    }
    ( vec_free [Dep] v )
}

@ main → i {
    : ( @ String s ) fetch \ s name → String { ^ ( idx_for name ) }

    // ── happy path ───────────────────────────────────────────────
    ( nurl_print `── resolve ──\n` )
    : ( Vec Dep ) roots ( vec_new [Dep] )
    ( vec_push [Dep] roots @ Dep { ( string_from `local` ) ( string_from `../local` ) ( string_from `0.1.0` ) ( string_new ) } )
    ( vec_push [Dep] roots ( reg_dep `foo` `^1.0` ) )
    : !( Vec LockPkg ) ResolveErr rr ( resolve_registry roots `https://reg.nurl-lang.org/` fetch )
    ?? rr {
        F e → ( nurl_print ( resolve_err_name e ) )
        T locked → {
            : String text ( lock_serialize locked )
            ( nurl_print ( string_data text ) )
            ( string_free text )
            ( lockpkgs_free locked )
        }
    }
    ( deps_free roots )

    // ── ResolveNoMatch ───────────────────────────────────────────
    ( nurl_print `── no match ──\n` )
    : ( Vec Dep ) r2 ( vec_new [Dep] )
    ( vec_push [Dep] r2 ( reg_dep `foo` `^9.0` ) )
    : !( Vec LockPkg ) ResolveErr rr2 ( resolve_registry r2 `https://reg/` fetch )
    ?? rr2 { F e → { ( nurl_print ( resolve_err_name e ) ) ( nurl_print `\n` ) } T l → { ( nurl_print `ok(bug)\n` ) ( lockpkgs_free l ) } }
    ( deps_free r2 )

    // ── ResolveNotFound ──────────────────────────────────────────
    ( nurl_print `── not found ──\n` )
    : ( Vec Dep ) r3 ( vec_new [Dep] )
    ( vec_push [Dep] r3 ( reg_dep `nope` `^1.0` ) )
    : !( Vec LockPkg ) ResolveErr rr3 ( resolve_registry r3 `https://reg/` fetch )
    ?? rr3 { F e → { ( nurl_print ( resolve_err_name e ) ) ( nurl_print `\n` ) } T l → { ( nurl_print `ok(bug)\n` ) ( lockpkgs_free l ) } }
    ( deps_free r3 )

    ( nurl_print `done\n` )
    ^ 0
}
