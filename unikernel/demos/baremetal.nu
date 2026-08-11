// unikernel/demos/baremetal.nu — the program on the USB stick.
//
// A NURL program is the whole of this machine. There is no Linux under
// it, no firmware left running beside it, no process next to it: GRUB
// read the Multiboot2 header in boot/boot.S, jumped in, and everything
// that has happened since is this file and the runtime it links.
//
// So what it prints is chosen to be what someone standing in front of
// an unfamiliar PC actually wants to know, in the order they want it:
//
//   1. it booted, and this is what it is
//   2. the machine, in the machine's own words — the RAM the firmware
//      reported, the CPU's name out of CPUID, the clock frequency and
//      WHERE that number came from, which console is being drawn on
//   3. the language still works up here — heap growth past the first
//      allocation, string building, the libm in this image, control
//      flow over a vector — each one CHECKED, because "it printed a
//      banner" and "it runs NURL" are different claims
//   4. a heartbeat, for ever
//
// The heartbeat is the point of the last one. This program never
// exits: on iron there is nothing to exit TO, and a unikernel that
// returns from main has switched the computer off in front of whoever
// just plugged the stick in. A line a second is also the only way to
// tell a machine that is running from one that stopped, which on a
// screen with no cursor is otherwise the same picture.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`
$ `stdlib/std/float.nu`
$ `stdlib/std/time.nu`

// The machine describing itself — see the "what machine is this?"
// block in boot/platform_x86.c. Every one of these reports something
// measured or handed over; none of them has a default.
& `c` @ nurl_boot_cmdline → s

& `c` @ nurl_mem_total → i

& `c` @ nurl_mem_used → i

& `c` @ nurl_cpu_brand → s

& `c` @ nurl_tsc_khz → i

& `c` @ nurl_clock_source → s

& `c` @ nurl_console_kind → s

@ rule → v {
    ( nurl_print `----------------------------------------\n` )
}

@ kv s k s v → v {
    ( nurl_print `  ` ) ( nurl_print k ) ( nurl_print `: ` )
    ( nurl_print v ) ( nurl_print `\n` )
}

// Mebibytes with one decimal, from integer bytes only. Not an
// aesthetic choice: 268435456 is a number the reader has to convert in
// their head at the exact moment they are trying to decide whether the
// firmware just lied to them about how much RAM is in the machine.
@ mb i bytes → String {
    : i whole / bytes 1048576
    : i rest % bytes 1048576
    : i tenth / * rest 10 1048576
    : String out ( string_new )
    ( string_push_int out whole )
    ( string_push_str out `.` )
    ( string_push_int out tenth )
    ( string_push_str out ` MiB` )
    ^ out
}

// ── does the language still work up here? ───────────────────────

// A vector that outgrows its first allocation, so this reaches the
// page allocator in boot/pagealloc.c and not only the bump pointer.
// The sum is 0+1+…+4095, checked rather than printed: a demo that
// prints what it computed proves it computed something, not that the
// answer was right, and on a bare machine the interesting failures are
// the quiet ones.
@ check_heap → b {
    : ( Vec i ) v ( vec_new [i] )
    : ~ i i 0
    ~ < i 4096 { ( vec_push [i] v i ) = i + i 1 }
    : ~ i sum 0
    = i 0
    ~ < i ( vec_len [i] v ) {
        = sum + sum ( opt_unwrap_or [i] ( vec_get [i] v i ) 0 )
        = i + i 1
    }
    ( vec_free [i] v )
    ^ == sum 8386560
}

// 400 bytes appended two at a time, then read back through the index.
@ check_strings → b {
    : String s ( string_new )
    : ~ i i 0
    ~ < i 200 { ( string_push_str s `ab` ) = i + i 1 }
    : b ok && == ( string_len s ) 400 == ( string_get s 399 ) 98
    ( string_free s )
    ^ ok
}

// sqrt comes out of the nolibc libm in this image — no libm on the
// system, no kernel underneath, generated coefficients. 2.0 is the
// value whose root is irrational and famous enough that a wrong answer
// is recognisable on sight.
@ check_float → b {
    : f r ( sqrt 2.0 )
    : f e - * r r 2.0
    ^ && < e 0.000001 > e -0.000001
}

@ check_control → b {
    : ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 5 ) ( vec_push [i] v 7 ) ( vec_push [i] v 9 )
    : ~ i acc 0
    : ~ i i 0
    ~ < i ( vec_len [i] v ) {
        = acc + acc ( opt_unwrap_or [i] ( vec_get [i] v i ) 0 )
        = i + i 1
    }
    ( vec_free [i] v )
    ^ == acc 21
}

@ report s name b ok → i {
    ( nurl_print ? ok `  [ ok ]  ` `  [FAIL]  ` )
    ( nurl_print name )
    ( nurl_print `\n` )
    ^ ? ok 0 1
}

// argv, so the `args="…"` plumbing is VERIFIED rather than assumed.
// Two loaders write that key with the quotes in different places (see
// build_argv in boot/platform_x86.c); this is what says which one the
// program actually received.
@ show_argv → v {
    : i argc ( nurl_argc )
    ( nurl_print `  args: ` )
    ? < argc 2 { ( nurl_print `(none)` ) } {
        : ~ i i 1
        ~ < i argc {
            ? > i 1 { ( nurl_print ` ` ) } {}
            ( nurl_print ( nurl_argv i ) )
            = i + i 1
        }
    }
    ( nurl_print `\n` )
}

@ main → i {
    ( nurl_print `\nNURL unikernel - running on bare metal\n` )
    ( rule )

    ( kv `console` ( nurl_console_kind ) )
    ( kv `cpu` ( nurl_cpu_brand ) )

    : String total ( mb ( nurl_mem_total ) )
    ( kv `memory` ( string_data total ) )
    ( string_free total )

    // The frequency AND its provenance. A clock is exactly as
    // trustworthy as whatever told you its rate, and on this machine
    // that is one of five different answers — see time_init in
    // boot/platform_x86.c.
    : String clk ( string_new )
    ( string_push_int clk ( nurl_tsc_khz ) )
    ( string_push_str clk ` kHz, from ` )
    ( string_push_str clk ( nurl_clock_source ) )
    ( kv `tsc` ( string_data clk ) )
    ( string_free clk )

    : s cl ( nurl_boot_cmdline )
    ( kv `cmdline` ? > ( nurl_str_len cl ) 0 cl `(empty)` )
    ( show_argv )

    ( nurl_print `\nself-check\n` )
    : ~ i failed 0
    = failed + failed ( report `heap - 4096 elements, sum verified` ( check_heap ) )
    = failed + failed ( report `strings - 400 bytes, read back` ( check_strings ) )
    = failed + failed ( report `floats - sqrt(2) squared is 2` ( check_float ) )
    = failed + failed ( report `control flow - fold over a vector` ( check_control ) )

    ( nurl_print `\n` )
    ? > failed 0 {
        ( nurl_print `SELF-CHECK FAILED - ` )
        ( nurl_print ( nurl_str_int failed ) )
        ( nurl_print ` of 4\n` )
    } {
        ( nurl_print `all four passed. this machine is running NURL.\n` )
    }
    ( rule )

    // ── the heartbeat ───────────────────────────────────────────
    ( nurl_print `heartbeat - power off when you have seen enough\n` )
    : ~ i n 0
    : i t0 ( monotonic_ns )
    ~ 1 {
        ( sleep_ms 1000 )
        = n + n 1
        : String line ( string_new )
        ( string_push_str line `  up ` )
        ( string_push_int line / - ( monotonic_ns ) t0 1000000000 )
        ( string_push_str line `s   ticks ` )
        ( string_push_int line n )
        ( string_push_str line `   heap ` )
        : String used ( mb ( nurl_mem_used ) )
        ( string_push_str line ( string_data used ) )
        ( string_push_str line `\n` )
        ( nurl_print ( string_data line ) )
        ( string_free used )
        ( string_free line )
    }
    ^ 0
}
