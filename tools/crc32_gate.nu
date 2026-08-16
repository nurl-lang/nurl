// tools/crc32_gate.nu — emit CRC-32 values for a deterministic byte
// sequence so tools/crc32_gate.sh can check them against an independent
// implementation (python3's zlib.crc32).
//
// std/deflate's crc32_update has two code paths — a bitwise loop for
// short inputs and a table-driven one from 512 bytes up — and they must
// agree with each other and with the world for every length. So the
// lengths below deliberately bracket that threshold byte by byte, and
// the chained cases prove that splitting an input across several
// crc32_update calls (what a streaming gzip reader does) produces the
// same answer as one call over the whole thing.
//
// Output, one record per line:
//   one <len> <crc>
//   chain <len> <split> <crc>

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/deflate.nu`

// A cheap deterministic byte sequence the shell side can reproduce.
@ __vec_of i n → ( Vec u ) {
    : ( Vec u ) v ( vec_with_cap [u] ? > n 0 n 1 )
    : ~ i i 0
    ~ < i n {
        ( vec_push [u] v # u & 255 + * i 37 11 )
        = i + i 1
    }
    ^ v
}

@ __emit_one i n → v {
    : ( Vec u ) v ( __vec_of n )
    : String out ( string_with_cap 32 )
    ( string_push_str out `one ` )
    ( string_push_int out n )
    ( string_push_char out 32 )
    ( string_push_int out ( crc32 v ) )
    ( string_push_char out 10 )
    ( nurl_print ( string_data out ) )
    ( string_free out )
    ( vec_free [u] v )
}

// crc32_update fed in two pieces must equal crc32 of the whole.
@ __emit_chain i n i split → v {
    : ( Vec u ) whole ( __vec_of n )
    : ( Vec u ) head ( vec_with_cap [u] ? > split 0 split 1 )
    : ( Vec u ) tail ( vec_with_cap [u] ? > - n split 0 - n split 1 )
    : ~ i i 0
    ~ < i n {
        : i byte ?? ( vec_get [u] whole i ) { T x → # i x F _ → 0 }
        ? < i split { ( vec_push [u] head # u byte ) } { ( vec_push [u] tail # u byte ) }
        = i + i 1
    }
    : i c ( crc32_update ( crc32_update 0 head ) tail )
    : String out ( string_with_cap 40 )
    ( string_push_str out `chain ` )
    ( string_push_int out n )
    ( string_push_char out 32 )
    ( string_push_int out split )
    ( string_push_char out 32 )
    ( string_push_int out c )
    ( string_push_char out 10 )
    ( nurl_print ( string_data out ) )
    ( string_free out )
    ( vec_free [u] whole ) ( vec_free [u] head ) ( vec_free [u] tail )
}

@ main → i {
    // Every length from 0 to 600 walks the small path, the threshold and
    // the table path, including all the block-boundary neighbours.
    : ~ i n 0
    ~ <= n 600 { ( __emit_one n ) = n + n 1 }
    ( __emit_one 1000 )
    ( __emit_one 4096 )
    ( __emit_one 65536 )

    ( __emit_chain 600 1 )
    ( __emit_chain 600 511 )
    ( __emit_chain 600 512 )
    ( __emit_chain 1024 512 )
    ( __emit_chain 4096 3 )
    ( __emit_chain 65536 32768 )
    ^ 0
}
