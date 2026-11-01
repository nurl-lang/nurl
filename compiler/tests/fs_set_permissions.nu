// fs_set_permissions.nu — std/fs.nu's chmod(2) wrapper.
//
// write_file creates at 0666 & ~umask, so a program that writes a
// private key leaves it readable by every account on the host until it
// tightens the mode. set_permissions is that step.
//
// What this pins is the API contract and the FFI declaration: that the
// symbol exists exactly once with one signature (a second declaration
// with a different one is a hard compile error, and stdlib carried a
// duplicate `chmod` in ext/credentials.nu until this wrapper replaced
// it), that the call succeeds on a file that exists, and that a missing
// path comes back as an IoErr rather than a silent success.
//
// The resulting mode is deliberately NOT read back here. fs.nu avoids
// stat(2) on purpose — `struct stat`'s field offsets differ per
// platform — and every root-independent way to observe a permission bit
// from inside the process reduces to "try the operation and see", which
// answers differently when the tests run as root. The observation lives
// where a shell is available and the platform is known:
// packages/pki-server/tests/pki_test.sh asserts `stat -c '%a'` is 600
// on the CA key and on every issued device key.

$ `stdlib/std/fs.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/posix.nu`
$ `stdlib/ext/env.nu`

: ~ i g_fail 0

// `name` under the platform's temp directory (env_temp_dir).
@ tmp_path s name → String {
    : String p ( env_temp_dir )
    ( string_push_char p 47 )
    ( string_push_str p name )
    ^ p
}

@ ok b cond s what → v {
    ( nurl_print what )
    ? cond { ( nurl_print `\tok\n` ) } {
        ( nurl_print `\tFAIL\n` )
        = g_fail + g_fail 1
    }
}

@ expect_ok s path i mode s what → v {
    ?? ( set_permissions path mode ) {
        T _ → { ( ok T what ) }
        F _ → { ( ok F what ) }
    }
}

@ main → i {
    // Scratch paths under the platform's temp directory: on Windows /tmp
    // is a directory on the current drive that exists only if something
    // made it first (agora #306).
    : String tp0 ( tmp_path `nurl_fsperm_` )
    : String dir ( string_from ( string_data tp0 ) )
    ( string_push_int dir ( getpid ) )
    : !v IoErr _md ( dir_create_all ( string_data dir ) )

    : String f ( string_clone dir )
    ( string_push_str f `/secret.key` )
    : !v IoErr _w ( write_file ( string_data f ) `-----BEGIN PRIVATE KEY-----\n` )

    ( expect_ok ( string_data f ) 384 `chmod-0600` )
    ( expect_ok ( string_data f ) 420 `chmod-0644` )
    ( expect_ok ( string_data f ) 448 `chmod-0700` )
    // Back to owner-only, and the file must still be readable by us.
    ( expect_ok ( string_data f ) 384 `chmod-0600-again` )
    ?? ( read_file ( string_data f ) ) {
        T s → { ( ok > ( string_len s ) 0 `owner-can-still-read` ) ( string_free s ) }
        F _ → { ( ok F `owner-can-still-read` ) }
    }

    ( expect_ok ( string_data dir ) 448 `chmod-directory` )

    : String missing ( string_clone dir )
    ( string_push_str missing `/not-there` )
    ?? ( set_permissions ( string_data missing ) 384 ) {
        T _ → { ( ok F `missing-path-is-an-error` ) }
        F _ → { ( ok T `missing-path-is-an-error` ) }
    }

    : !v IoErr _rm ( dir_remove_all ( string_data dir ) )
    ( string_free missing )
    ( string_free f )
    ( string_free dir )

    ? == g_fail 0 { ^ 0 } {}
    ^ 1
}
