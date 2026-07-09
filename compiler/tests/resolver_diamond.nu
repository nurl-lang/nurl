// resolver_diamond.nu — the resolver must intersect ALL requirements on a
// name, not lock the first-seen requirement's max. Two roots depend on `c`:
//   a 1.0.0 → c ^1.0.0            (allows 1.0.0 .. <2.0.0)
//   b 1.0.0 → c >=1.0.0 <1.5.0    (allows 1.0.0 .. <1.5.0)
//   c: 1.0.0, 1.4.0, 1.9.0
// First-requirement-wins would lock c at 1.9.0 (a's ^1) then spuriously
// ResolveConflict on b. The fixpoint resolver intersects → c 1.4.0.
//
// The second graph is a genuine empty intersection (c ^1 from a vs c ^2 from
// b') → ResolveConflict.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/manifest.nu`
$ `stdlib/ext/lockfile.nu`
$ `stdlib/ext/resolver.nu`

@ idx_for s name → String {
    ? != 0 ( nurl_str_eq name `a` ) {
        ^ ( string_from `{ "name": "a", "versions": [
          { "version": "1.0.0", "checksum": "a100", "deps": [ { "name": "c", "req": "^1.0.0" } ] } ] }` )
    } {}
    ? != 0 ( nurl_str_eq name `b` ) {
        ^ ( string_from `{ "name": "b", "versions": [
          { "version": "1.0.0", "checksum": "b100", "deps": [ { "name": "c", "req": ">=1.0.0 <1.5.0" } ] } ] }` )
    } {}
    ? != 0 ( nurl_str_eq name `bx` ) {
        ^ ( string_from `{ "name": "bx", "versions": [
          { "version": "1.0.0", "checksum": "bx10", "deps": [ { "name": "c", "req": "^2.0.0" } ] } ] }` )
    } {}
    ? != 0 ( nurl_str_eq name `c` ) {
        ^ ( string_from `{ "name": "c", "versions": [
          { "version": "1.0.0", "checksum": "c100", "deps": [] },
          { "version": "1.4.0", "checksum": "c140", "deps": [] },
          { "version": "1.9.0", "checksum": "c190", "deps": [] } ] }` )
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

    // Satisfiable diamond → c 1.4.0.
    ( nurl_print `── diamond ──\n` )
    : ( Vec Dep ) roots ( vec_new [Dep] )
    ( vec_push [Dep] roots ( reg_dep `a` `^1.0` ) )
    ( vec_push [Dep] roots ( reg_dep `b` `^1.0` ) )
    : !( Vec LockPkg ) ResolveErr rr ( resolve_registry roots `https://reg/` fetch )
    ?? rr {
        F e → { ( nurl_print ( resolve_err_name e ) ) ( nurl_print `\n` ) }
        T locked → {
            : String text ( lock_serialize locked )
            ( nurl_print ( string_data text ) )
            ( string_free text )
            ( lockpkgs_free locked )
        }
    }
    ( deps_free roots )

    // Empty intersection (c ^1 vs c ^2) → ResolveConflict.
    ( nurl_print `── conflict ──\n` )
    : ( Vec Dep ) r2 ( vec_new [Dep] )
    ( vec_push [Dep] r2 ( reg_dep `a` `^1.0` ) )
    ( vec_push [Dep] r2 ( reg_dep `bx` `^1.0` ) )
    : !( Vec LockPkg ) ResolveErr rr2 ( resolve_registry r2 `https://reg/` fetch )
    ?? rr2 {
        F e → { ( nurl_print ( resolve_err_name e ) ) ( nurl_print `\n` ) }
        T l → { ( nurl_print `ok(bug)\n` ) ( lockpkgs_free l ) }
    }
    ( deps_free r2 )

    ( nurl_print `done\n` )
    ^ 0
}
