// json_deep_fiber.nu — a JSON document as deep as JSON_MAX_DEPTH allows
// goes through every walk of a Json on a FIBER's stack (64 KB, the stack
// an async HTTP server parses a request body on): parse, json_stringify,
// json_pretty, json_clone, json_eq and the drop, each of which recurses
// once per level. One level deeper is Overflow, at the bracket that went
// past the cap, and a hostile run of brackets is refused the same way. The
// old cap of 1024 let a 250-deep body take the whole process down with a
// SIGSEGV on the fiber's guard page (agora #297).
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/async.nu`
$ `stdlib/ext/json.nu`

// `d` levels: `[[…]]`, or `{"a":{"a":…1…}}` when `obj`.
@ nested i d b obj → String {
    : String s ( string_with_cap + * 6 d 2 )
    : ~ i k 0
    ~ < k d {
        ( string_push_str s ? obj `{"a":` `[` )
        = k + k 1
    }
    ? obj { ( string_push_char s 49 ) } {}
    = k 0
    ~ < k d {
        ( string_push_char s ? obj 125 93 )
        = k + k 1
    }
    ^ s
}

@ check s label b ok → v {
    ( nurl_print label )
    ( nurl_print ? ok `: ok\n` `: FAILED\n` )
}

// Every walk, at depth `d`.
@ walk_all s label String doc → v {
    ?? ( json_parse_slice ( string_bytes doc ) ) {
        T j → {
            : String back ( json_stringify j )
            : String pretty ( json_pretty j )
            : Json copy ( json_clone j )
            ( nurl_print label )
            ( nurl_print ? != 0 ( nurl_str_eq ( string_data back ) ( string_data doc ) ) `: parsed, stringified back the same` `: stringified DIFFERENTLY` )
            ( nurl_print ? > ( string_len pretty ) ( string_len back ) `, pretty-printed` `, pretty FAILED` )
            ( nurl_print ? ( json_eq j copy ) `, cloned and equal` `, clone UNEQUAL` )
            ( nurl_print `\n` )
        }
        F e → {
            ( nurl_print label ) ( nurl_print `: ` )
            ( nurl_print ( string_data ( json_format_error e ) ) ) ( nurl_print ` (FAILED)\n` )
        }
    }
}

@ refused s label String doc → v {
    ?? ( json_parse_slice ( string_bytes doc ) ) {
        T j → {
            ( nurl_print label ) ( nurl_print `: parsed (FAILED)\n` )
        }
        F e → {
            ( nurl_print label ) ( nurl_print `: ` )
            ( nurl_print ( string_data ( json_format_error e ) ) ) ( nurl_print `\n` )
        }
    }
}

@ main → i {
    ( check `the cap` == JSON_MAX_DEPTH 256 )
    : String arr ( nested JSON_MAX_DEPTH F )
    : String obj ( nested JSON_MAX_DEPTH T )
    : String arr_past ( nested + JSON_MAX_DEPTH 1 F )
    : String obj_past ( nested + JSON_MAX_DEPTH 1 T )
    : String hostile ( string_with_cap 100000 )
    : ~ i k 0
    ~ < k 100000 {
        ( string_push_char hostile 91 )
        = k + k 1
    }
    : Fiber f ( spawn \ → v {
        ( walk_all `arrays at the cap, on a fiber` arr )
        ( walk_all `objects at the cap, on a fiber` obj )
        ( refused `arrays one past it` arr_past )
        ( refused `objects one past it` obj_past )
        ( refused `100000 open brackets` hostile )
    } )
    ( runtime_run )
    ^ 0
}
