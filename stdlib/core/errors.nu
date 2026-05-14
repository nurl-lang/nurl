// stdlib/core/errors.nu — standard error enums
//
// These are the canonical error types used by the standard library.
// Each is a plain enum with descriptive variants. Callers use ?? match
// to inspect the specific variant and render a message.
//
//   ParseErr   → parsing failures (string→int, JSON, etc.)
//   IoErr      → I/O failures (file, stdin/stdout, path ops)
//   BoundsErr  → out-of-range access (slice/string/vec index)
//
// Example:
//   : ! i ParseErr r ( string_to_int s )
//   ? . r 0 { ( nurl_print_int . r 1 ) }
//           { ( nurl_print ( parse_err_msg # ParseErr . r 1 ) ) }

: | ParseErr { BadFormat Overflow Underflow Empty TrailingGarbage }

: | IoErr { NotFound PermissionDenied AlreadyExists Interrupted UnexpectedEof WriteFailed ReadFailed Other }

: | BoundsErr { IndexOutOfRange NegativeIndex EmptyCollection }

// ── Rendering helpers ───────────────────────────────────────────────

@ parse_err_msg ParseErr e → s {
    ^ ?? e {
        BadFormat → `bad format`
        Overflow → `overflow`
        Underflow → `underflow`
        Empty → `empty input`
        TrailingGarbage → `trailing garbage`
    }
}

@ io_err_msg IoErr e → s {
    ^ ?? e {
        NotFound → `not found`
        PermissionDenied → `permission denied`
        AlreadyExists → `already exists`
        Interrupted → `interrupted`
        UnexpectedEof → `unexpected eof`
        WriteFailed → `write failed`
        ReadFailed → `read failed`
        Other → `i/o error`
    }
}

@ bounds_err_msg BoundsErr e → s {
    ^ ?? e {
        IndexOutOfRange → `index out of range`
        NegativeIndex → `negative index`
        EmptyCollection → `empty collection`
    }
}
