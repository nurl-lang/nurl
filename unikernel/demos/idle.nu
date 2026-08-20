// unikernel/demos/idle.nu — the machine can WAIT without burning the
// host's core.
//
// v1's "fully polling" answer to a sleep was a `pause` spin: an idle
// worker appliance measured at a full host core doing nothing. The
// machine now idles on `hlt`, woken by its own local-APIC timer —
// TSC-deadline mode where the CPU has it, the classic one-shot
// calibrated against the TSC where it does not (TCG) — and this demo
// is the gate: sleep long enough that a spin would be visible, then
// ask the machine whether it actually halted.
//
// Booleans only, so the golden holds on KVM and TCG alike (the two
// report different idle modes, but both must sleep and both must
// halt).

$ `stdlib/core/string.nu`
$ `stdlib/std/time.nu`

& `c` @ nurl_idle_hlt_count → i

@ main → i {
    : i t0 ( monotonic_ns )
    ( sleep_ms 300 )
    : i elapsed_ms / - ( monotonic_ns ) t0 1000000
    ( nurl_print `slept at least 280 ms: ` )
    ( nurl_print ? >= elapsed_ms 280 `yes` `no` )
    ( nurl_print `\n` )
    ( nurl_print `the machine idled on hlt: ` )
    ( nurl_print ? > ( nurl_idle_hlt_count ) 0 `yes` `no` )
    ( nurl_print `\n` )
    ^ 0
}
