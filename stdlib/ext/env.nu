// stdlib/ext/env.nu — process environment + argv + cwd
//
// CLI tooling primitives. Each String (and env_args_list's Vec) returned
// is the caller's own, dropped at scope exit.
//
//   ( env_args_count )       → i              like argc
//   ( env_arg i )            → String         argv[i]; empty when out of range
//   ( env_args_list )        → ( Vec String ) all argv copied into owned Strings
//   ( env_get name )         → ? String       None when unset
//   ( env_var_or name def )  → String         convenience: get-or-default
//   ( env_home_dir )         → String         the user's home directory; ""
//                                             when the platform names none
//   ( env_temp_dir )         → String         where temporary files go on
//                                             this platform (never "")
//   ( env_set name value )   → ! v IoErr      Other on failure
//   ( env_unset name )       → ! v IoErr
//   ( env_cwd )              → ! String IoErr current working directory
//   ( env_chdir path )       → ! v IoErr      change cwd
//   ( env_exit code )        → v              terminate process

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/errors.nu`
$ `stdlib/core/posix.nu`  // posix_const + nurl_errno_get

// ── libc FFI surface for env / cwd / chdir ──────────────────────────
//
// PURIFY §13 batch 1 (2026-05-24): the five `nurl_env_*` / `nurl_cwd`
// / `nurl_chdir` thunks moved out of `stdlib/runtime.c`. Both libc
// flavours we target (Linux/macOS primary libc, mingw-w64 libmingwex)
// expose the POSIX names `getenv` / `setenv` / `unsetenv` / `getcwd` /
// `chdir` with the same ABI — no platform gating needed.
//
// `getenv` returns a BORROWED pointer into the environment block;
// callers must NOT free it. `getcwd(buf, cap)` writes into a
// caller-owned buffer and returns the buffer on success or NULL with
// errno = ERANGE when the buffer is too small (the loop below doubles
// the buffer and retries up to a 1 MB ceiling).

// `getenv` is declared globally by the compiler (it is used by nurlc's own
// import-path resolution), so — like fopen/access — it must NOT be
// re-declared here, or the program would emit two `declare @getenv` lines.

& `c` @ setenv s name s value i32 overwrite → i32

& `c` @ unsetenv s name → i32

& `c` @ getcwd *u buf i size → s

& `c` @ chdir s path → i32

@ env_args_count → i {
    ^ ( nurl_argv_count )
}

@ env_arg i idx → String {
    // The raw argv copy is auto-dropped after string_from copies it.
    : s raw ( nurl_argv_get idx )
    : String out ( string_from raw )
    ^ out
}

@ env_args_list → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_argv_count )
    : ~ i i 0
    ~ < i n {
        : s raw ( nurl_argv_get i )
        ( vec_push [String] out ( string_from raw ) )
        = i + i 1
    }
    ^ out
}

// ── Enumerating the environment ─────────────────────────────────────
//
// `env_get` answers about a name you already know. Listing what is
// actually set — which `env` / `printenv` / a shell's `export -p` needs,
// and which a program logging its own configuration wants — needs the
// vector itself, and that is a C *variable* (`environ`, `_environ` on
// Windows), not something NURL can bind through FFI. The runtime
// enumerates it: `nurl_env_count` / `nurl_env_at`.

& `c` @ nurl_env_count → i

& `c` @ nurl_env_at i idx → s

@ env_count → i { ^ ( nurl_env_count ) }

// The `NAME=value` entry at `idx`, as an owned String; the empty string
// past the end.
@ env_entry i idx → String {
    : s raw ( nurl_env_at idx )
    ? == # i raw 0 { ^ ( string_new ) } {}
    ^ ( string_from raw )
}

// Every `NAME=value` currently set, in the process's own order. The
// caller owns the Vec and every String in it (vec_free_with).
@ env_list → ( Vec String ) {
    : ( Vec String ) out ( vec_new [String] )
    : i n ( nurl_env_count )
    : ~ i i 0
    ~ < i n {
        : s raw ( nurl_env_at i )
        ? != # i raw 0 { ( vec_push [String] out ( string_from raw ) ) } {}
        = i + i 1
    }
    ^ out
}

@ env_get s name → ?String {
    ? == # i name 0 { ^ @ ?String { F # String 0 } } {}
    // getenv returns a libc-owned pointer; do not free. `string_from`
    // copies the bytes into an owned String so the result outlives
    // any subsequent setenv that might invalidate the borrow.
    : s raw ( getenv name )
    ? == # i raw 0 { ^ @ ?String { F # String 0 } } {}
    : String out ( string_from raw )
    ^ @ ?String { T out }
}

@ env_var_or s name s default → String {
    : ?String got ( env_get name )
    ^ ?? got {
        T s → s
        F → ( string_from default )
    }
}

// A variable's value, or "" when it is unset or empty.
@ __env_nonempty s name → String {
    ^ ?? ( env_get name ) {
        T v → v
        F → ( string_new )
    }
}

// The user's home directory — the one place in the stdlib that answers
// "where is ~". POSIX: $HOME. Windows: %USERPROFILE%, else %HOMEDRIVE% +
// %HOMEPATH% — the profile Windows itself and its tools use (Go's
// os.UserHomeDir, Rust's home_dir). HOME is NOT read on Windows: it is
// unset in PowerShell and cmd and set only by Unix-flavoured shells, so a
// program that read it kept its files in a different place depending on
// the shell it was started from — or, with a "." fallback, in whatever
// directory it happened to run in (nurlpkg login once wrote a registry
// token into a checkout that way).
//
// "" when the platform names no home. There is deliberately no relative
// fallback: a caller that would store something under the home must
// refuse, not write into the working directory.
@ env_home_dir → String {
    // The target's path-list separator is ';' exactly on Windows — a
    // property of the build, not of the environment, so it cannot be
    // spoofed by setting a variable.
    ? != ( posix_const `PATH_LIST_SEPARATOR` ) 59 { ^ ( __env_nonempty `HOME` ) } {}
    : String prof ( __env_nonempty `USERPROFILE` )
    ? > ( string_len prof ) 0 { ^ prof } {}
    : String drive ( __env_nonempty `HOMEDRIVE` )
    : String hpath ( __env_nonempty `HOMEPATH` )
    ? | == ( string_len drive ) 0 == ( string_len hpath ) 0 { ^ ( string_new ) } {}
    ( string_push_str drive ( string_data hpath ) )
    ^ drive
}

// Where temporary files go, on the platform's own terms: the one place in
// the stdlib that answers it (agora #306). Never "", and no trailing
// separator, so a caller joins a name on with one `/`.
//
// POSIX: $TMPDIR when set and non-empty, else /tmp.
//
// Windows: what GetTempPathW answers. %TMP%, else %TEMP%, else
// %USERPROFILE%, else the Windows directory (%SystemRoot%): the order
// Go's os.TempDir and Rust's env::temp_dir follow there. TMPDIR is NOT
// read on Windows. Git Bash and MSYS export it as a POSIX path
// (`/c/Users/me/AppData/Local/Temp`), which a native program resolves
// against the current drive. /tmp, the old fallback, is a directory on
// the current drive too, one that exists only if something else happened
// to create it first.
@ env_temp_dir → String {
    ? != ( posix_const `PATH_LIST_SEPARATOR` ) 59 {
        : String t ( __env_nonempty `TMPDIR` )
        ? > ( string_len t ) 0 { ^ ( __env_dir_trim t ) } {}
        ^ ( string_from `/tmp` )
    } {}
    : String a ( __env_nonempty `TMP` )
    ? > ( string_len a ) 0 { ^ ( __env_dir_trim a ) } {}
    : String b ( __env_nonempty `TEMP` )
    ? > ( string_len b ) 0 { ^ ( __env_dir_trim b ) } {}
    : String c ( __env_nonempty `USERPROFILE` )
    ? > ( string_len c ) 0 { ^ ( __env_dir_trim c ) } {}
    : String d ( __env_nonempty `SystemRoot` )
    ? > ( string_len d ) 0 { ^ ( __env_dir_trim d ) } {}
    ^ ( string_from `C:/Windows` )
}

// `p` without its trailing `/` or `\` separators; a root (`/`, `C:\`)
// keeps its own.
@ __env_dir_trim String p → String {
    : ~ i n ( string_len p )
    ~ & > n 1 | == ( string_get p - n 1 ) 47 == ( string_get p - n 1 ) 92 {
        ? & == n 3 == ( string_get p 1 ) 58 { ^ ( string_substr p 0 n ) } {}
        = n - n 1
    }
    ^ ( string_substr p 0 n )
}

@ env_set s name s value → !v IoErr {
    ? | == # i name 0 == # i value 0
    { ^ @ !v IoErr { F @ IoErr { Other } } } {}
    : i32 rc ( setenv name value # i32 1 )
    ? == rc # i32 0 { ^ @ !v IoErr { T 0 } } {}
    ^ @ !v IoErr { F @ IoErr { Other } }
}

@ env_unset s name → !v IoErr {
    ? == # i name 0 { ^ @ !v IoErr { F @ IoErr { Other } } } {}
    : i32 rc ( unsetenv name )
    ? == rc # i32 0 { ^ @ !v IoErr { T 0 } } {}
    ^ @ !v IoErr { F @ IoErr { Other } }
}

// Owned-cwd loop: `getcwd(buf, cap)` returns NULL with errno=ERANGE
// when the buffer is too small; we double and retry until we land on
// a fit or hit the 1 MB ceiling (which would mean a pathologically
// long cwd — well past any real filesystem's PATH_MAX). Each attempt's
// buffer is a `( Vec u )` the scope drops, so no path frees anything by
// hand — the raw `nurl_alloc` / `nurl_free` loop this replaced had a
// free on one branch and a reuse on another.
@ env_cwd → !String IoErr {
    : ~ i cap 256
    ~ <= cap 1048576 {
        : ( Vec u ) buf ( vec_zeroed [u] cap )
        : s rc ( getcwd # s ( vec_data [u] buf ) cap )
        ? != # i rc 0 { ^ @ !String IoErr { T ( string_from rc ) } } {}
        ? != ( nurl_errno_get ) ( posix_const `ERANGE` ) { ^ @ !String IoErr { F @ IoErr { Other } } } {}
        = cap * cap 2
    }
    ^ @ !String IoErr { F @ IoErr { Other } }
}

@ env_chdir s path → !v IoErr {
    ? == # i path 0 { ^ @ !v IoErr { F @ IoErr { Other } } } {}
    : i32 rc ( chdir path )
    ? == rc # i32 0 { ^ @ !v IoErr { T 0 } } {}
    : i k ( errno_kind )
    ? == k 0 { ^ @ !v IoErr { F @ IoErr { NotFound } } } {}
    ? == k 1 { ^ @ !v IoErr { F @ IoErr { PermissionDenied } } } {}
    ^ @ !v IoErr { F @ IoErr { Other } }
}

@ env_exit i code → v {
    ( nurl_exit code )
}
