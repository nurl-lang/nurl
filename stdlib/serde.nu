// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
// ============================================================
//  stdlib/serde.nu — Serde-style Serialize trait + JSON
//                    en/decoder helpers for built-in types.
//
//  Design choices:
//
//  * Format-specific traits over a single multi-method one. A type
//    that wants JSON ships `% JsonSerialize Foo { ... }`; a type
//    that ALSO wants TOML adds `% TomlSerialize Foo { ... }` (when
//    that trait lands). No coupling between formats, no surface for
//    "what do I do if I only care about one direction".
//
//  * Serialize is a TRAIT (first-arg dispatch by T). Deserialize is
//    a NAMING CONVENTION: per-type `from_json_<T>` helpers. NURL's
//    trait dispatch resolves on the first-arg LLVM type, and a
//    Deserialize trait would have `Json` as that first arg — every
//    impl would collide on `Json`. The helper-function convention
//    sidesteps that.
//
//  * Only the JSON side ships today. TOML / MsgPack hooks land
//    alongside their respective decoder rewrites (`stdlib/ext/toml.nu`
//    already has a parser; `stdlib/ext/msgpack.nu` is not in tree).
//    When they land, mirror this file's shape: `% TomlSerialize [T]
//    { @ to_toml T x → TomlValue }`, `from_toml_<T> TomlValue v
//    → !T TomlErr`, and so on.
//
//  Usage shape:
//
//      $ `stdlib/serde.nu`
//
//      : Point { i x  i y }
//      % JsonSerialize Point {
//          @ to_json Point p → Json {
//              : Json j ( json_obj_new )
//              ( json_obj_set j `x` ( to_json . p x ) )
//              ( json_obj_set j `y` ( to_json . p y ) )
//              ^ j
//          }
//      }
//
//      @ point_from_json Json j → !Point ParseErr { ... }
//
//      // Round-trip a value through JSON text:
//      : Point p @ Point { 3 4 }
//      : Json   j ( to_json p )
//      : String s ( json_stringify j )
//      // `s` now holds the canonical JSON encoding of `p`.

$ `stdlib/ext/json.nu`

// ── Serialize trait — convert T → Json ─────────────────────────────
//
// First-arg dispatch: `( to_json x )` resolves to the impl matching
// the LLVM type of `x` (NURL Group F impl dispatch). For composite
// types (slices, options, results) the impl bodies destructure
// recursively, calling `to_json` again on each contained value.

% JsonSerialize [T] {
    @ to_json T x → Json
}

% JsonSerialize i {
    @ to_json i n → Json { ^ ( json_int n ) }
}

% JsonSerialize b {
    @ to_json b v → Json { ^ ( json_bool v ) }
}

% JsonSerialize f {
    @ to_json f x → Json { ^ ( json_float x ) }
}

% JsonSerialize s {
    @ to_json s p → Json { ^ ( json_str_lit p ) }
}

% JsonSerialize String {
    @ to_json String s → Json { ^ ( json_str_lit ( string_data s ) ) }
}

// ── Deserialize helpers — per-type `from_json_<T>` ─────────────────
//
// All return a `!T ParseErr`. `JsonTypeMismatch` covers
// "Json variant did not match the expected one"; numeric parsers
// reuse `string_to_int` / `string_to_float`'s `ParseErr` payloads.
//
// Caller pattern:
//
//   : !i ParseErr r ( from_json_i j )
//   ?? r {
//       T n  → { ... use n ... }
//       F e  → { ... handle ... }
//   }

@ from_json_i Json j → !i ParseErr {
    : ?i o ( json_num_as_i j )
    ^ ?? o {
        T n → @ !i ParseErr { T n }
        F → @ !i ParseErr { F @ ParseErr { BadFormat } }
    }
}

@ from_json_f Json j → !f ParseErr {
    : ?f o ( json_num_as_f j )
    ^ ?? o {
        T x → @ !f ParseErr { T x }
        F → @ !f ParseErr { F @ ParseErr { BadFormat } }
    }
}

@ from_json_b Json j → !b ParseErr {
    ^ ?? j {
        JBool v → @ !b ParseErr { T v }
        _ → @ !b ParseErr { F @ ParseErr { BadFormat } }
    }
}

// Returns a fresh `String` borrowed from the JStr payload's text. The
// JStr stays in the source Json tree; caller owns the returned String
// and must `string_free` it.
@ from_json_string Json j → !String ParseErr {
    ^ ?? j {
        JStr s → @ !String ParseErr { T ( string_from ( string_data s ) ) }
        _ → @ !String ParseErr { F @ ParseErr { BadFormat } }
    }
}

// Raw-pointer flavour for callers that want an `s` (i8*) borrow into
// the JStr payload without copying. The pointer lifetime matches the
// source Json tree — do NOT free it.
@ from_json_str_borrow Json j → !s ParseErr {
    ^ ?? j {
        JStr s → @ !s ParseErr { T ( string_data s ) }
        _ → @ !s ParseErr { F @ ParseErr { BadFormat } }
    }
}
