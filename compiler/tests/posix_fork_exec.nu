// posix_fork_exec.nu — PURIFY Phase 8 scaffolding smoke test.
//
// Exercises the pure-NURL POSIX FFI surface from stdlib/core/posix.nu:
// fork(2), execvp(3), waitpid(2), the wait-status decoders, and
// nurl_native_constant. If this passes the bootstrap and produces the
// expected exit code, Phase 8 batch 2 (port nurl_proc_run's POSIX
// backend to NURL) has the primitives it needs.

$ `stdlib/core/posix.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/cell.nu`

@ main → i {
    // ── 1: nurl_native_constant returns plausible values ─────────
    : i o_nb ( posix_const `O_NONBLOCK` )
    ( nurl_print `O_NONBLOCK>0=` ) ( nurl_print ? > o_nb 0 `T` `F` )
    ( nurl_print `\n` )

    : i pollin ( posix_const `POLLIN` )
    ( nurl_print `POLLIN==1=` ) ( nurl_print ? == pollin 1 `T` `F` )
    ( nurl_print `\n` )

    : i unknown ( posix_const `NO_SUCH_CONST` )
    ( nurl_print `unknown==-1=` ) ( nurl_print ? == unknown -1 `T` `F` )
    ( nurl_print `\n` )

    // ── 2: fork + execvp /bin/true; wait + decode status ─────────
    : i pid ( fork )
    ? == pid 0 {
        // child: build argv[] = { "true", NULL } on a 16-byte buffer
        // (2 × 8-byte slots). argv must be a NULL-terminated pointer
        // array. nurl_poke indexes by SLOT, not byte offset — write
        // pointer to slot 0, sentinel 0 to slot 1.
        : s argv_buf ( nurl_alloc 16 )
        : s prog `true`
        : *u progp # *u prog
        ( nurl_poke argv_buf 0 # i progp )
        ( nurl_poke argv_buf 1 0 )
        ( execvp `/bin/true` # *u argv_buf )
        // If execvp returned, it failed — bail with the documented
        // exit-127 convention nurl_proc_run uses.
        ( _exit 127 )
    } {}
    ? < pid 0 {
        ( nurl_print `fork failed errno=` )
        ( nurl_print ( nurl_str_int ( nurl_errno_get ) ) )
        ( nurl_print `\n` )
        ^ 1
    } {}

    // parent: waitpid on the child.
    : i sz_int ( nurl_native_sizeof `int` )
    : s status_buf ( nurl_alloc sz_int )
    : *u status_p # *u status_buf
    : i wpid ( waitpid pid status_p 0 )
    ? <= wpid 0 {
        ( nurl_print `waitpid failed wpid=` )
        ( nurl_print ( nurl_str_int wpid ) )
        ( nurl_print `\n` )
        ( nurl_free status_buf )
        ^ 1
    } {}

    // Decode status. We expect a clean exit with code 0.
    : i raw_status # i . status_p 0
    : i exited ( nurl_wait_is_exited raw_status )
    : i exit_code ( nurl_wait_exit_status raw_status )

    ( nurl_print `exited=` ) ( nurl_print ? == exited 1 `T` `F` )
    ( nurl_print ` exit_code=` ) ( nurl_print ( nurl_str_int exit_code ) )
    ( nurl_print `\n` )

    ( nurl_free status_buf )
    ^ 0
}
