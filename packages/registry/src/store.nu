// registry/store.nu — input validation + the on-disk tarball store.
//
// Layout under the data dir:
//
//   <data>/registry.db                       SQLite (see db.nu)
//   <data>/pkgs/<name>/<name>-<version>.tar.gz
//   <data>/pkgs/<name>/<name>-<version>.tar.gz.minisig
//
// Tarball paths are BUILT from a validated (name, version) pair — no
// client-supplied path segment is ever joined onto the filesystem, so
// traversal is impossible by construction rather than by filtering.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/ext/semver.nu`
$ `stdlib/ext/registry_id.nu`

// Share the published-name grammar with the resolver and installer.
@ reg_name_valid s name → b { ^ ( registry_name_valid name ) }

// Version: full semver incl. pre-release/build metadata — validated by
// actually parsing it with the same engine the resolver uses, not by a
// lookalike regex.
@ reg_version_valid s version → b {
    : !Semver SemverErr pr ( semver_parse version )
    ?? pr {
        T v → { ^ T }
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

// The detached signature lives beside the exact immutable tarball it covers.
@ reg_minisig_path s data_dir s name s version → String {
    : String out ( reg_tarball_path data_dir name version )
    ( string_push_str out `.minisig` )
    ^ out
}

// Persist a published tarball; T on success.
@ reg_tarball_write s data_dir s name s version ( Vec u ) bytes → b {
    : String dir ( string_from data_dir )
    ( string_push_str dir `/pkgs/` )
    ( string_push_str dir name )
    ?? ( dir_create_all ( string_data dir ) ) {
        T _ → {}
        F _ → { ^ F }
    }
    : String path ( reg_tarball_path data_dir name version )
    : ~ b ok F
    ?? ( write_file_bytes ( string_data path ) bytes ) {
        T _ → { = ok T }
        F _ → {}
    }
    ^ ok
}

// Read a published tarball; empty Vec when absent.
@ reg_tarball_read s data_dir s name s version → ( Vec u ) {
    : String path ( reg_tarball_path data_dir name version )
    : ~ ( Vec u ) out ( vec_new [u] )
    ?? ( read_file_bytes ( string_data path ) ) {
        T bytes → {
            = out bytes
        }
        F _ → {}
    }
    ^ out
}

// Persist a detached minisign file; T on success. The package directory is
// created here as well so this primitive is independently usable in tests and
// by a signer that prepares the sidecar before committing publish metadata.
@ reg_minisig_write s data_dir s name s version s signature → b {
    : String dir ( string_from data_dir )
    ( string_push_str dir `/pkgs/` )
    ( string_push_str dir name )
    ?? ( dir_create_all ( string_data dir ) ) {
        T _ → {}
        F _ → { ^ F }
    }
    : String path ( reg_minisig_path data_dir name version )
    ^ ?? ( write_file ( string_data path ) signature ) { T _ → T F _ → F }
}

// Read a detached minisign file; empty String when absent or unreadable.
@ reg_minisig_read s data_dir s name s version → String {
    : String path ( reg_minisig_path data_dir name version )
    ^ ?? ( read_file ( string_data path ) ) { T text → text F _ → ( string_new ) }
}
