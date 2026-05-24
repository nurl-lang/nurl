// stdlib/ext/env.nu — process environment + argv + cwd
//
// CLI tooling primitives. Each owned String must be freed by the caller
// (auto-drop runs at scope exit, vec_free_with for env_args_list).
//
//   ( env_args_count )       → i              like argc
//   ( env_arg i )            → String         argv[i]; empty when out of range
//   ( env_args_list )        → ( Vec String ) all argv copied into owned Strings
//   ( env_get name )         → ? String       None when unset
//   ( env_var_or name def )  → String         convenience: get-or-default
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

& `c` @ getenv   s name                        → s
& `c` @ setenv   s name s value i32 overwrite → i32
& `c` @ unsetenv s name                        → i32
& `c` @ getcwd   s buf  i      size            → s
& `c` @ chdir    s path                        → i32

@ env_args_count → i {
    ^ ( nurl_argv_count )
}

@ env_arg i idx → String {
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
// long cwd — well past any real filesystem's PATH_MAX).
@ env_cwd → !String IoErr {
    : ~ i cap 256
    : ~ s buf ( nurl_alloc cap )
    : ~ b done F
    : ~ b ok F
    ~ ! done {
        : s rc ( getcwd buf cap )
        ? != # i rc 0 {
            = ok T
            = done T
        } {
            : i e ( nurl_errno_get )
            ? != e ( posix_const `ERANGE` ) { = done T } {
                ( nurl_free buf )
                = cap * cap 2
                ? > cap 1048576 { = done T } {
                    = buf ( nurl_alloc cap )
                }
            }
        }
    }
    ? ok {
        : String out ( string_from buf )
        ( nurl_free buf )
        ^ @ !String IoErr { T out }
    } {
        ^ @ !String IoErr { F @ IoErr { Other } }
    }
}

@ env_chdir s path → !v IoErr {
    ? == # i path 0 { ^ @ !v IoErr { F @ IoErr { Other } } } {}
    : i32 rc ( chdir path )
    ? == rc # i32 0 { ^ @ !v IoErr { T 0 } } {}
    : i k ( nurl_errno_kind )
    ? == k 0 { ^ @ !v IoErr { F @ IoErr { NotFound } } } {}
    ? == k 1 { ^ @ !v IoErr { F @ IoErr { PermissionDenied } } } {}
    ^ @ !v IoErr { F @ IoErr { Other } }
}

@ env_exit i code → v {
    ( nurl_exit code )
}
