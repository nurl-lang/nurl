// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
// Reusable formatter entry point. The source is borrowed; the result is owned.

$ `stdlib/core/string.nu`
$ `tools/nurlfmt/tokenize.nu`
$ `tools/nurlfmt/pretty.nu`

// Format NUL-free source `src` to its canonical layout per docs/FORMAT.md.
//
// The token vector owns its source slices until pretty_print has copied
// their bytes into the output. Release it after that borrow ends.
@ format_source String src → String {
    : ( Vec FmtTok ) toks ( tokenize ( string_data src ) )
    : String out ( pretty_print toks )
    ( tokens_free toks )
    ^ out
}
