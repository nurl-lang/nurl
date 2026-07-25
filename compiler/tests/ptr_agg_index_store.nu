// Storing an AGGREGATE through a pointer index with a COMPUTED index.
//
// The read path always accepted `. p + k 0`; the store path peeked at
// the token after the pointer and, seeing an operator rather than an
// identifier, reported "unknown field or variable: +" — naming the
// operator as if it were a struct field. stdlib/core/vec.nu's
// vec_extend hits this the moment its element type is an aggregate.

$ `stdlib/core/string.nu`

: Pair { i a i b }

@ main → i {
    : *Pair dst # *Pair ( nurl_zalloc * 4 16 )
    : *Pair src # *Pair ( nurl_zalloc * 4 16 )
    : ~ i i0 0
    ~ < i0 4 {
        : Pair v @ Pair { + i0 10 + i0 20 }
        = . src i0 v
        = i0 + i0 1
    }
    : i base 1
    : ~ i j 0
    ~ < j 3 {
        // computed index on BOTH sides, aggregate value
        = . dst + base j . src j
        = j + j 1
    }
    = j 0
    ~ < j 3 {
        : Pair q . dst + base j
        ( nurl_print ( nurl_str_int . q a ) )
        ( nurl_print ` ` )
        ( nurl_print ( nurl_str_int . q b ) )
        ( nurl_print `\n` )
        = j + j 1
    }
    ( nurl_free # s dst ) ( nurl_free # s src )
    ^ 0
}
