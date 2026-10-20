// nurldoc.nu — ext/nurldoc.nu acceptance: render a fixture module's doc
// surface to Markdown. Exercises: module-header block → prose, doc
// comment above a decl → description, signature trimmed at `{`, FFI / `:`
// const / struct / enum decls, that `:` locals inside a function body
// (brace depth > 0) are NOT picked up, that `__`-private (file-scoped)
// functions are omitted, that a multi-line type declaration renders
// its full field list in a fenced code block, and that an impl block
// renders its method signatures only — never their bodies.

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
    ( string_push_str src `    : i sum + a b\n` )  // local `:` at depth 1 — must be ignored
    ( string_push_str src `    ^ sum\n` )
    ( string_push_str src `}\n` )
    ( string_push_str src `\n` )
    ( string_push_str src `// A point.\n` )
    ( string_push_str src `: Point { i x i y }\n` )
    ( string_push_str src `\n` )
    ( string_push_str src `// Internal helper — file-scoped, must NOT appear in the docs.\n` )
    ( string_push_str src `@ __hidden i a → i {\n` )
    ( string_push_str src `    ^ a\n` )
    ( string_push_str src `}\n` )
    ( string_push_str src `\n` )
    ( string_push_str src `// A rectangle (multi-line: fields must render in a code block).\n` )
    ( string_push_str src `: Rect {\n` )
    ( string_push_str src `    i w  // width\n` )
    ( string_push_str src `    i h\n` )
    ( string_push_str src `}\n` )
    ( string_push_str src `\n` )
    ( string_push_str src `: | Color { Red Green Blue }\n` )  // no doc comment
    ( string_push_str src `\n` )
    ( string_push_str src `// Process id.\n` )
    ( string_push_str src `& ` ) ( string_push_char src 96 )
    ( string_push_str src `c` ) ( string_push_char src 96 )
    ( string_push_str src ` @ getpid → i\n` )
    ( string_push_str src `\n` )
    ( string_push_str src `: i MAX 100\n` )  // const, no doc
    ( string_push_str src `\n` )
    ( string_push_str src `// Rects compare by area.\n` )
    ( string_push_str src `% Eq Rect {\n` )
    ( string_push_str src `    // Same area.\n` )
    ( string_push_str src `    @ eq Rect a Rect b → b {\n` )
    ( string_push_str src `        : i x * . a w . a h\n` )  // body — must NOT render
    ( string_push_str src `        ^ == x * . b w . b h\n` )
    ( string_push_str src `    }\n` )
    ( string_push_str src `    @ ne Rect a Rect b → b { ^ ! ( eq a b ) }\n` )
    ( string_push_str src `}\n` )

    : String md ( nurldoc_render ( string_data src ) `demo` )
    ( nurl_print ( string_data md ) )
    ( string_free md )
    ( string_free src )
    ^ 0
}
