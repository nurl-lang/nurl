// enum_payload_signedness.nu — regression for narrow sized-int enum
// payloads, found by hand-probing while extending the differential fuzzer
// (tools/fuzz) on 2026-06-02.
//
// Before the fix, an enum variant carrying a NARROW sized-int payload
// (`u`/`i8`/`u16`/`i16`/`u32`/`i32`) was accepted by the front-end but
// emitted invalid IR — `gen_agg_lit` only converted i64/i32 payloads to the
// enum's pointer slot, and `gen_match` only un-converted i1/i64, so an i8
// payload hit `insertvalue %E …, i8 …, ptr-field` (clang reject) and the
// match stored a `ptr` into an `i8` binding. Now:
//   * construction widens a narrow payload to i64 (zext for unsigned, sext
//     for signed, per the recorded payload signedness) before inttoptr;
//   * the match ptrtoint's back to i64 and truncs to the payload width, and
//     carries the payload's signedness onto the binding so a later widen
//     zero-extends an unsigned payload.
//
// main returns the number of failed checks (0 = all pass).

: | EU { NoneU  ByteV  u   }   // unsigned byte payload
: | ES { NoneS  ByteS  i8  }   // signed byte payload
: | EW { NoneW  WideV  u16 }   // unsigned 16 payload
: | EH { NoneH  HalfV  i16 }   // signed 16 payload
: | ED { NoneD  DwV    u32 }   // unsigned 32 payload

@ chk i got i want s tag → i {
    ? == got want {
        ( nurl_print tag ) ( nurl_print ` ok\n` ) ^ 0
    } {
        ( nurl_print tag ) ( nurl_print ` FAIL\n` ) ^ 1
    }
}

@ main → i {
    : ~ i f 0
    : EU a @ EU { ByteV # u 200 }
    = f + f ?? a { ByteV b → ( chk # i64 # i b 200 `u8_payload_zext` )  NoneU → 1 }
    : ES c @ ES { ByteS # i8 200 }
    = f + f ?? c { ByteS b → ( chk # i64 # i64 b - 0 56 `i8_payload_sext` )  NoneS → 1 }
    : EW d @ EW { WideV # u16 50000 }
    = f + f ?? d { WideV b → ( chk # i64 # i b 50000 `u16_payload_zext` )  NoneW → 1 }
    : EH e @ EH { HalfV # i16 50000 }
    = f + f ?? e { HalfV b → ( chk # i64 # i64 b - 0 15536 `i16_payload_sext` )  NoneH → 1 }
    : ED g @ ED { DwV # u32 2147483649 }
    = f + f ?? g { DwV b → ( chk # i64 # i b 2147483649 `u32_payload_zext` )  NoneD → 1 }
    ^ f
}
