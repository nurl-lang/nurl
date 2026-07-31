// stdout buffering — ordering contract.
//
// `nurl_print` block-buffers when stdout is a pipe or a file (the test
// runner redirects, so that is the mode here) and flushes per call only
// on a terminal. Buffering is what keeps a print-heavy program from
// paying one write(2) per fragment — but it must not reorder anything
// an observer merging stdout and stderr can see. This test pins the
// three rules that make that true:
//
//   1. stdout stays in program order with itself (trivially).
//   2. a stderr write drains stdout first, so `2>&1` sees the two
//      streams in the order the program produced them.
//   3. a raw `write(2)` on fd 1 bypasses stdio entirely, so the
//      program must flush stdout itself before one — same discipline
//      as mixing printf and write(1, …) in C.
//
// The POSIX runner captures `> out 2>&1`, so `outputs/` IS the
// interleaving, and rule 2 is what that golden asserts.
//
// `outputs-windows/` records the same run with the lines in a different
// order, and that is expected rather than a Windows bug: run_tests.ps1
// reads the child's two pipes separately and concatenates them
// (`Out = $o.Result + $e.Result`), so no interleaving survives to be
// compared — every stderr line lands after every stdout line whatever
// the program did. Rules 1 and 3 still hold there and the Windows
// golden still pins them; rule 2 is simply unobservable through that
// harness. Do not "fix" the Windows golden into the POSIX order.

& `libc` @ write i fd s buf i count → i

@ main → i {
    ( nurl_print `1 stdout via nurl_print\n` )
    ( nurl_eprintln `2 stderr via nurl_eprintln` )
    ( nurl_print `3 stdout again\n` )
    ( nurl_eprint `4 stderr via nurl_eprint\n` )
    ( nurl_print `5 stdout before a raw write\n` )
    // Rule 3: raw fd-1 write, so drain stdio's buffer first.
    ( nurl_flush_stdout )
    ( write 1 `6 raw write(2) on fd 1\n` 23 )
    ( nurl_print `7 stdout last\n` )
    ^ 0
}
