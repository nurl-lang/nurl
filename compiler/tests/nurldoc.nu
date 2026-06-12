// nurldoc.nu — ext/nurldoc.nu acceptance: render a fixture module's doc
// surface to Markdown. Exercises: module-header block → prose, doc
// comment above a decl → description, signature trimmed at `{`, FFI / `:`
// const / struct / enum decls, and that `:` locals inside a function body
// (brace depth > 0) are NOT picked up.

$ `stdlib/core/string.nu`
$ `stdlib/ext/nurldoc.nu`

@ main → i {
    : String src ( string_with_cap 512 )
    // ── fixture module ──
    ( string_push_str src `// demo.nu — a tiny module.\n` )
    ( string_push_str src `// Second header line.\n` )
    ( string_push_str src `\n` )
    ( string_push_str src `$ ` ) ( string_push_char src 96 )
    ( string_push_str src `stdlib/core/string.nu` ) ( string_push_char src 96 )
    ( string_push_str src `\n` )
    ( string_push_str src `\n` )
    ( string_push_str src `// Add two ints.\n` )
    ( string_push_str src `@ add i a i b → i {\n` )
    ( string_push_str src `    : i sum + a b\n` )       // local `:` at depth 1 — must be ignored
    ( string_push_str src `    ^ sum\n` )
    ( string_push_str src `}\n` )
    ( string_push_str src `\n` )
    ( string_push_str src `// A point.\n` )
    ( string_push_str src `: Point { i x i y }\n` )
    ( string_push_str src `\n` )
    ( string_push_str src `: | Color { Red Green Blue }\n` )   // no doc comment
    ( string_push_str src `\n` )
    ( string_push_str src `// Process id.\n` )
    ( string_push_str src `& ` ) ( string_push_char src 96 )
    ( string_push_str src `c` ) ( string_push_char src 96 )
    ( string_push_str src ` @ getpid → i\n` )
    ( string_push_str src `\n` )
    ( string_push_str src `: i MAX 100\n` )                    // const, no doc

    : String md ( nurldoc_render ( string_data src ) `demo` )
    ( nurl_print ( string_data md ) )
    ( string_free md )
    ( string_free src )
    ^ 0
}
