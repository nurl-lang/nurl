// block_scope_drop.nu — a bare `{ … }` statement drops what it binds at
// its `}` (docs/MEMORY.md §1, "Where values are dropped").
//
// Every `Noisy` prints when it is dropped, so the output is the order of
// the drops: a value bound in a bare block goes where the block ends,
// before the statement after it — not when the function returns, which
// is where it used to go (a lock guard bound in a block kept its lock
// until then). Nested blocks drop innermost first; a block left by `^`,
// `break` or `continue` drops once, on that path; a value moved out of a
// block is not dropped there; a block in value position keeps its value.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Noisy { String name }

% Drop Noisy {
    @ drop Noisy n → v { ( nurl_print `  drop ` ) ( nurl_println ( string_data . n name ) ) }
}

@ noisy s name → Noisy { ^ @ Noisy { ( string_from name ) } }

@ early i k → i {
    : Noisy outer ( noisy `outer` )
    {
        : Noisy inner ( noisy `inner` )
        ? == k 1 { ^ 1 } {}
        ( nurl_println `  block end` )
    }
    ( nurl_println `  after block` )
    ^ 0
}

@ moved_out → Noisy {
    : ~ Noisy keep ( noisy `placeholder` )
    {
        : Noisy made ( noisy `made` )
        = keep made
    }
    ( nurl_println `  after block (made moved out)` )
    ^ keep
}

@ main → i {
    ( nurl_println `1. a bare block` )
    {
        : Noisy a ( noisy `a` )
        ( nurl_println `  in block` )
    }
    ( nurl_println `  after block` )

    ( nurl_println `2. nested` )
    {
        : Noisy b ( noisy `b` )
        {
            : Noisy c ( noisy `c` )
            ( nurl_println `  inner` )
        }
        ( nurl_println `  between` )
    }

    ( nurl_println `3. left by return` )
    ( nurl_println_int ( early 1 ) )
    ( nurl_println `4. fall through` )
    ( nurl_println_int ( early 0 ) )

    ( nurl_println `5. loop with break / continue` )
    : ~ i k 0
    ~ < k 3 {
        = k + k 1
        {
            : Noisy d ( noisy `d` )
            ? == k 1 { continue } {}
            ? == k 3 { break } {}
            ( nurl_println `  body` )
        }
    }

    ( nurl_println `6. moved out of a block` )
    : Noisy m ( moved_out )
    ( nurl_println `  got it` )

    ( nurl_println `7. value position keeps its value` )
    : i n {
        : ( Vec i ) xs ( vec_new [i] )
        ( vec_push [i] xs 5 )
        ( vec_at [i] xs 0 )
    }
    ( nurl_println_int n )
    ( nurl_println `end` )
    ^ 0
}
