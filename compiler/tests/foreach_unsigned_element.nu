// foreach_unsigned_element.nu — the element binding of `~ x slice { … }` must
// inherit the container's element signedness. An unsigned element used with a
// signed-sensitive operator (`/ % >> < > <= >=`) or widened with `# i` was
// silently treated as SIGNED: gen_foreach bound the element only by its LLVM
// type (i8/i16/i32/i64), which can't carry signedness.
//
// E.g. iterating a `[ u …` byte slice and testing `> by 127` used `icmp sgt`,
// so any byte ≥ 128 (a negative i8) tested false — wrong for every UTF-8 /
// binary parser. Fixed: gen_foreach tags the loop binding unsigned from the
// Vec `%Vec__<slug>` suffix or the bound slice's recorded element flag.
@ pr s l i v → v { ( nurl_print l ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print `\n` ) }

@ main → i {
    // byte slice (u = unsigned i8): high-bit bytes must compare/​widen unsigned
    : [ u bytes [ u | 65 200 130 10 ]
    : ~ i hi 0
    ~ by bytes { ? > by 127 { = hi + hi 1 } {} }
    ( pr `high_bytes` hi )                            // 2  (200,130 > 127)
    : ~ i bsum 0
    ~ by bytes { = bsum + bsum # i by }
    ( pr `byte_sum` bsum )                            // 405 (zext, not sign-extended)

    // u64 slice with the high bit set
    : [ u64 xs [ u64 | 18446744073709551615 200 ]
    : ~ i big 0
    ~ el xs { ? > el 1000 { = big + big 1 } {} }
    ( pr `gt1000` big )                               // 1  (all-ones > 1000 unsigned)
    : ~ i msum 0
    ~ el xs { = msum + msum # i % el 7 }
    ( pr `mod7_sum` msum )                            // 5  (urem: 1 + 4)
    ^ 0
}
