// registry/store.nu — input validation + the on-disk tarball store.
//
// Layout under the data dir:
//
//   <data>/registry.db                       SQLite (see db.nu)
//   <data>/pkgs/<name>/<name>-<version>.tar.gz
//
// Tarball paths are BUILT from a validated (name, version) pair — no
// client-supplied path segment is ever joined onto the filesystem, so
// traversal is impossible by construction rather than by filtering.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/semver.nu`

// Package name: ^[a-z0-9][a-z0-9_-]{0,63}$ (the registry convention the
// Worker enforced; nurlpkg lowercases on its side too).
@ reg_name_valid s name → b {
    : i n ( nurl_str_len name )
    ? | == n 0 > n 64 { ^ F } {}
    : ~ i k 0
    : ~ b ok T
    ~ & < k n ok {
        : i c ( nurl_str_get name k )
        : ~ b good F
        ? & >= c 97 <= c 122 { = good T } {}  // a-z
        ? & >= c 48 <= c 57 { = good T } {}  // 0-9
        ? > k 0 {
            ? | == c 45 == c 95 { = good T } {}  // - _ (not leading)
        } {}
        ? ! good { = ok F } {}
        = k + k 1
    }
    ^ ok
}

// Version: full semver incl. pre-release/build metadata — validated by
// actually parsing it with the same engine the resolver uses, not by a
// lookalike regex.
@ reg_version_valid s version → b {
    : !Semver SemverErr pr ( semver_parse version )
    ?? pr {
        T v → { ( semver_free v ) ^ T }
        F _ → ^ F
    }
}

// <data>/pkgs/<name>/<name>-<version>.tar.gz — call only with a
// validated pair.
@ reg_tarball_path s data_dir s name s version → String {
    : String out ( string_from data_dir )
    ( string_push_str out `/pkgs/` )
    ( string_push_str out name )
    ( string_push_char out 47 )
    ( string_push_str out name )
    ( string_push_char out 45 )
    ( string_push_str out version )
    ( string_push_str out `.tar.gz` )
    ^ out
}

// Persist a published tarball; T on success.
@ reg_tarball_write s data_dir s name s version ( Vec u ) bytes → b {
    : String dir ( string_from data_dir )
    ( string_push_str dir `/pkgs/` )
    ( string_push_str dir name )
    ?? ( dir_create_all ( string_data dir ) ) {
        T _ → {}
        F _ → { ( string_free dir ) ^ F }
    }
    ( string_free dir )
    : String path ( reg_tarball_path data_dir name version )
    : ~ b ok F
    ?? ( write_file_bytes ( string_data path ) bytes ) {
        T _ → { = ok T }
        F _ → {}
    }
    ( string_free path )
    ^ ok
}

// Read a published tarball; empty Vec when absent.
@ reg_tarball_read s data_dir s name s version → ( Vec u ) {
    : String path ( reg_tarball_path data_dir name version )
    : ~ ( Vec u ) out ( vec_new [u] )
    ?? ( read_file_bytes ( string_data path ) ) {
        T bytes → {
            ( vec_free [u] out )
            = out bytes
        }
        F _ → {}
    }
    ( string_free path )
    ^ out
}
