// stdlib/ext/toolchain.nu — upgrade the installed NURL toolchain in place.
//
//   ( toolchain_upgrade want current check_only force )  → i   exit code
//
// This is the active half of the update story whose passive half is
// stdlib/ext/update_check.nu's once-a-day "a newer toolchain is out"
// notice. Both are reached from the same two front-ends:
//
//   nurl upgrade [--check] [--version vX.Y.Z] [--force]
//   nurlpkg self-update  (same flags; `nurl upgrade` is the canonical name)
//
// Design — it RUNS THE OFFICIAL INSTALLER, it does not reimplement it.
// Unpacking a release involves a checksum gate, a minisign signature gate,
// and a very specific "replace the toolchain's own paths, keep everything
// else" rule (the prefix also holds the registry token, the model cache and
// every program installed with `nurlpkg install`). A second implementation
// of that would be a second thing to keep correct — and the one place this
// project already got bitten was exactly a drifted copy of the installer.
// So the installer is shipped INSIDE the toolchain, at
// <prefix>/libexec/get-nurl.sh (get-nurl.ps1 on Windows), and this module
// resolves a version, decides whether anything needs doing, and spawns it.
//
// Nothing here is downloaded-and-executed: the script that runs is the one
// that came with the toolchain you already trust. It then fetches the new
// archive over HTTPS and verifies it fail-closed, as it always has.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `stdlib/std/process.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/ext/update_check.nu`

// `!b` has no prefix form in the grammar; this keeps the guards readable.
@ __tc_not b x → b {
    ? x { ^ F } {}
    ^ T
}

// Windows host? Windows always exports OS=Windows_NT; nothing else does.
@ __tc_is_windows → b {
    : ~ b w F
    ?? ( env_get `OS` ) {
        T e → { = w ( nurl_str_eq ( string_data e ) `Windows_NT` ) ( string_free e ) }
        F → {}
    }
    ^ w
}

// The install prefix this toolchain lives in. $NURL_HOME wins (the env
// file exports it); the PATH shims always export $NURL_STDLIB, which is
// the same directory; otherwise fall back to the installer's default.
// Empty String when even the home directory is unknown.
@ toolchain_prefix → String {
    ?? ( env_get `NURL_HOME` ) {
        T v → { ? > ( string_len v ) 0 { ^ v } { ( string_free v ) } }
        F → {}
    }
    ?? ( env_get `NURL_STDLIB` ) {
        T v → { ? > ( string_len v ) 0 { ^ v } { ( string_free v ) } }
        F → {}
    }
    : s home_var ? ( __tc_is_windows ) `USERPROFILE` `HOME`
    : String home ( env_var_or home_var `` )
    ? == ( string_len home ) 0 { ( string_free home ) ^ ( string_new ) } {}
    : String p ( path_join ( string_data home ) `.nurl` )
    ( string_free home )
    ^ p
}

// The bundled installer inside `prefix`, or an empty String when this
// toolchain shipped without one (an old release, or a source checkout).
@ toolchain_installer s prefix → String {
    : s name ? ( __tc_is_windows ) `get-nurl.ps1` `get-nurl.sh`
    : String dir ( path_join prefix `libexec` )
    : String f ( path_join ( string_data dir ) name )
    ( string_free dir )
    ? ( file_exists ( string_data f ) ) { ^ f } {}
    ( string_free f )
    ^ ( string_new )
}

// "0.26.0" → "v0.26.0"; "v0.26.0" → unchanged. Release archives are named
// after the tag, so the leading v is not optional downstream.
@ __tc_norm_tag s ver → String {
    ? & > ( nurl_str_len ver ) 0 != ( nurl_str_get ver 0 ) 118 {
        : String out ( string_from `v` )
        ( string_push_str out ver )
        ^ out
    } {}
    ^ ( string_from ver )
}

// Spawn `prog args…`, echoing its stdout line by line as it arrives.
// The child inherits stderr, so the installer's own progress output
// (which it writes there) streams straight to the terminal. Returns the
// child's exit code, or -1 when it could not be launched at all.
@ __tc_stream s prog ( Vec s ) args → i {
    ?? ( process_spawn prog args ) {
        T ch → {
            : ~ i done 0
            ~ == done 0 {
                ?? ( proc_read_line ch 0 ) {
                    T ln → {
                        ( nurl_print ( string_data ln ) )
                        ( nurl_print `\n` )
                        ( string_free ln )
                    }
                    F → { = done 1 }
                }
            }
            : i rc ( proc_wait ch )
            ( proc_free ch )
            ^ rc
        }
        F e → {
            ( nurl_eprint `nurl upgrade: could not run the installer: ` )
            ( nurl_eprintln ( process_err_name e ) )
            ^ -1
        }
    }
}

@ __tc_report_dev s current → v {
    ( nurl_eprint `nurl upgrade: this is a development build (` )
    ( nurl_eprint current )
    ( nurl_eprintln `), not a release.` )
    ( nurl_eprintln `  In a source checkout, update it with:  git pull && ./build.sh` )
    ( nurl_eprintln `  To install a published release over it: nurl upgrade --force` )
}

@ __tc_report_no_installer s prefix → v {
    ( nurl_eprint `nurl upgrade: no bundled installer under ` )
    ( nurl_eprint prefix )
    ( nurl_eprintln `/libexec.` )
    ( nurl_eprintln `  This toolchain predates in-place upgrades — install the current one with:` )
    ( nurl_eprintln `    curl -fsSL https://nurl-lang.org/install.sh | sh` )
}

// Resolve the version to install: the pinned `want`, or the newest
// release. Empty String when the release index could not be reached
// (the caller has already been told why).
@ __tc_resolve_target s want → String {
    ? > ( nurl_str_len want ) 0 { ^ ( __tc_norm_tag want ) } {}
    ( nurl_eprintln `resolving the latest release…` )
    ?? ( update_check_latest ) {
        T v → { ^ v }
        F → {
            ( nurl_eprintln `nurl upgrade: could not reach the release index (offline?).` )
            ( nurl_eprintln `  Retry later, or pin a version:  nurl upgrade --version vX.Y.Z` )
        }
    }
    ^ ( string_new )
}

// --check: report and change NOTHING. Deliberately does not care where
// the toolchain lives or whether it is a release build — a read-only
// probe has no reason to fail in a source checkout.
@ __tc_check s want s current → i {
    : String target ( __tc_resolve_target want )
    ? == ( string_len target ) 0 { ( string_free target ) ^ 1 } {}
    ? ( update_check_is_release current ) {
        ? ( update_check_newer ( string_data target ) current ) {
            ( nurl_print `update available: ` )
            ( nurl_print current )
            ( nurl_print ` → ` )
            ( nurl_print ( string_data target ) )
            ( nurl_print `\n  run:  nurl upgrade\n` )
        } {
            ( nurl_print `up to date (` )
            ( nurl_print current )
            ( nurl_print `)\n` )
        }
    } {
        ( nurl_print `development build ` )
        ( nurl_print current )
        ( nurl_print ` — the newest release is ` )
        ( nurl_print ( string_data target ) )
        ( nurl_print `\n` )
    }
    ( string_free target )
    ^ 0
}

// `want` is a pinned tag ("" = resolve the latest release), `current` the
// running toolchain's version (nurl_version). Returns a process exit code.
@ toolchain_upgrade s want s current b check_only b force → i {
    ? check_only { ^ ( __tc_check want current ) } {}

    : String prefix ( toolchain_prefix )
    ? == ( string_len prefix ) 0 {
        ( nurl_eprintln `nurl upgrade: cannot locate the toolchain — set $NURL_HOME to its install prefix.` )
        ( string_free prefix )
        ^ 1
    } {}

    // A dev build has no release lineage: replacing it with a tarball is
    // almost never what the user meant, so it takes an explicit --force.
    ? | ( update_check_is_release current ) force {} {
        ( __tc_report_dev current )
        ( string_free prefix )
        ^ 1
    }

    : String installer ( toolchain_installer ( string_data prefix ) )
    ? == ( string_len installer ) 0 {
        ( __tc_report_no_installer ( string_data prefix ) )
        ( string_free installer )
        ( string_free prefix )
        ^ 1
    } {}

    : String target ( __tc_resolve_target want )
    ? == ( string_len target ) 0 {
        ( string_free target )
        ( string_free installer )
        ( string_free prefix )
        ^ 1
    } {}

    : b same != 0 ( nurl_str_eq ( string_data target ) current )
    : b newer ( update_check_newer ( string_data target ) current )

    ? & same ( __tc_not force ) {
        ( nurl_print `already on ` )
        ( nurl_print current )
        ( nurl_print ` — nothing to do (use --force to reinstall it).\n` )
        ( string_free target )
        ( string_free installer )
        ( string_free prefix )
        ^ 0
    } {}

    ? newer {
        ( nurl_print `upgrading ` ) ( nurl_print current )
        ( nurl_print ` → ` ) ( nurl_print ( string_data target ) ) ( nurl_print `\n` )
    } {
        ? same {
            ( nurl_print `reinstalling ` ) ( nurl_print ( string_data target ) ) ( nurl_print `\n` )
        } {
            ( nurl_print `installing ` ) ( nurl_print ( string_data target ) )
            ( nurl_print ` over ` ) ( nurl_print current )
            ( nurl_print ` (a downgrade)\n` )
        }
    }

    // ── run the bundled installer, pinned to this prefix + version ────
    // NURL_NO_MODIFY_PATH: the prefix is already on PATH (that is how we
    // got here), so an upgrade must never prompt about shell rc files.
    ?? ( env_set `NURL_NO_MODIFY_PATH` `1` ) { T _ → {} F _ → {} }

    : ( Vec s ) args ( vec_new [s] )
    : ~ s prog `sh`
    ? ( __tc_is_windows ) {
        = prog `powershell`
        ( vec_push [s] args `-NoProfile` )
        ( vec_push [s] args `-ExecutionPolicy` )
        ( vec_push [s] args `Bypass` )
        ( vec_push [s] args `-File` )
        ( vec_push [s] args ( string_data installer ) )
        ( vec_push [s] args `-Version` )
        ( vec_push [s] args ( string_data target ) )
        ( vec_push [s] args `-Prefix` )
        ( vec_push [s] args ( string_data prefix ) )
    } {
        ( vec_push [s] args ( string_data installer ) )
        ( vec_push [s] args `--version` )
        ( vec_push [s] args ( string_data target ) )
        ( vec_push [s] args `--prefix` )
        ( vec_push [s] args ( string_data prefix ) )
    }
    : i rc ( __tc_stream prog args )
    ( vec_free [s] args )

    ? == rc 0 {
        // The cached probe still names the version we just left behind;
        // drop it so the next command does not repeat the notice.
        ( update_check_forget )
        ( nurl_print `\nNURL ` )
        ( nurl_print ( string_data target ) )
        ( nurl_print ` is installed in ` )
        ( nurl_print ( string_data prefix ) )
        ( nurl_print `.\n` )
    } {
        ( nurl_eprintln `nurl upgrade: the installer did not complete — the toolchain is unchanged.` )
    }

    ( string_free target )
    ( string_free installer )
    ( string_free prefix )
    ^ ? == rc 0 0 1
}
