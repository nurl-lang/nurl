$ `stdlib/core/string.nu`
$ `stdlib/core/slice.nu`
// A function whose result is a call handing a LOCAL to an `inout`
// parameter (`^ ( score c )`) must not mark that call `tail`: LLVM's
// marker promises the callee reads no alloca of the caller, and the
// optimiser kept the promise by dropping the stores that initialised the
// local — the callee read a cursor and a view that were never written
// (both counts came out 0). Expected: 50 and 82.
: Cursor { ( Slice u ) text i pos }

// Large enough that it stays a call of its own.
@ score inout Cursor c → i {
    : ~ i acc 0
    ~ < . c pos ( slice_len [u] . c text ) {
        : i ch # i ( slice_byte . c text . c pos )
        ? == ch 33 { = acc + acc 1 } {}
        ? == ch 34 { = acc + acc 2 } {}
        ? == ch 35 { = acc + acc 3 } {}
        ? == ch 36 { = acc + acc 4 } {}
        ? == ch 37 { = acc + acc 5 } {}
        ? == ch 38 { = acc + acc 6 } {}
        ? == ch 39 { = acc + acc 7 } {}
        ? == ch 40 { = acc + acc 8 } {}
        ? == ch 41 { = acc + acc 9 } {}
        ? == ch 42 { = acc + acc 10 } {}
        ? == ch 43 { = acc + acc 11 } {}
        ? == ch 44 { = acc + acc 12 } {}
        ? == ch 45 { = acc + acc 13 } {}
        ? == ch 46 { = acc + acc 14 } {}
        ? == ch 47 { = acc + acc 15 } {}
        ? == ch 48 { = acc + acc 16 } {}
        ? == ch 49 { = acc + acc 17 } {}
        ? == ch 50 { = acc + acc 18 } {}
        ? == ch 51 { = acc + acc 19 } {}
        ? == ch 52 { = acc + acc 20 } {}
        ? == ch 53 { = acc + acc 21 } {}
        ? == ch 54 { = acc + acc 22 } {}
        ? == ch 55 { = acc + acc 23 } {}
        ? == ch 56 { = acc + acc 24 } {}
        ? == ch 57 { = acc + acc 25 } {}
        ? == ch 58 { = acc + acc 26 } {}
        ? == ch 59 { = acc + acc 27 } {}
        ? == ch 60 { = acc + acc 28 } {}
        ? == ch 61 { = acc + acc 29 } {}
        ? == ch 62 { = acc + acc 30 } {}
        ? == ch 63 { = acc + acc 31 } {}
        ? == ch 64 { = acc + acc 32 } {}
        ? == ch 65 { = acc + acc 33 } {}
        ? == ch 66 { = acc + acc 34 } {}
        ? == ch 67 { = acc + acc 35 } {}
        ? == ch 68 { = acc + acc 36 } {}
        ? == ch 69 { = acc + acc 37 } {}
        ? == ch 70 { = acc + acc 38 } {}
        ? == ch 71 { = acc + acc 39 } {}
        ? == ch 72 { = acc + acc 40 } {}
        = . c pos + . c pos 1
    }
    ^ acc
}

@ score_of s src → i {
    : ~ Cursor c @ Cursor { ( slice_of_str src ) 0 }
    ^ ( score c )
}

@ main → i {
    ( nurl_println_int ( score_of `hello, world! (#1)` ) )
    ( nurl_println_int ( score_of `a+b=c; d/e` ) )
    ^ 0
}
