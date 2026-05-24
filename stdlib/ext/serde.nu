// Copyright (c) 2026 The NURL Project Developers
// SPDX-License-Identifier: MIT OR Apache-2.0
// ============================================================
//  stdlib/ext/serde.nu — Serde-style Serialize trait + JSON
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
//  * JSON and TOML sides ship. `% JsonSerialize` / `to_json` /
//    `from_json_<T>` cover JSON; `% TomlSerialize` / `to_toml` /
//    `from_toml_<T>` cover TOML, pairing with `stdlib/ext/toml.nu`'s
//    parser (`toml_parse`) and serializer (`toml_stringify`). The
//    `from_json_<T>` / `from_toml_<T>` helpers return `!T ParseErr`.
//
//  * MsgPack needs no serialize trait of its own: MessagePack and JSON
//    share a data model, so a value is encoded by composing the
//    existing `to_json` with `msgpack_encode` (codec in
//    `stdlib/ext/msgpack.nu`). Decoding gets the `from_msgpack_<T>`
//    helpers below — they return `!T MsgpackErr` (not `ParseErr`):
//    `MsgpackErr` is the richer of the two error types and can carry
//    every msgpack-decode failure plus a `MsgpackTypeMismatch` for a
//    decoded value of the wrong shape, all without loss.
//
//    TomlValue has no float variant (toml.nu's parser excludes
//    floats), so TomlSerialize covers `i` / `b` / `s` / `String` —
//    there is no `to_toml f` or `from_toml_f`.
//
//  Usage shape:
//
//      $ `stdlib/ext/serde.nu`
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
$ `stdlib/ext/toml.nu`
$ `stdlib/ext/msgpack.nu`

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

// ── Serialize trait — convert T → TomlValue ────────────────────────
//
// Mirrors JsonSerialize. A user type ships `% TomlSerialize Foo {
// @ to_toml Foo x → TomlValue { ... } }`, building a TTable with
// `@ TomlEntry { key value }` rows. Pair `to_toml` with
// `toml_stringify` to reach TOML text. There is no `f` impl —
// TomlValue (toml.nu's parser AST) has no float variant.

% TomlSerialize [T] {
    @ to_toml T x → TomlValue
}

% TomlSerialize i {
    @ to_toml i n → TomlValue { ^ @ TomlValue { TInt n } }
}

% TomlSerialize b {
    @ to_toml b v → TomlValue { ^ @ TomlValue { TBool v } }
}

% TomlSerialize s {
    @ to_toml s p → TomlValue { ^ @ TomlValue { TStr ( string_from p ) } }
}

% TomlSerialize String {
    @ to_toml String s → TomlValue { ^ @ TomlValue { TStr ( string_from ( string_data s ) ) } }
}

// ── Deserialize helpers — per-type `from_toml_<T>` ─────────────────
//
// Each returns `!T ParseErr`, `BadFormat` when the TomlValue variant
// is not the expected one — same shape and error type as the JSON
// helpers above.

@ from_toml_i TomlValue v → !i ParseErr {
    ^ ?? v {
        TInt n → @ !i ParseErr { T n }
        _ → @ !i ParseErr { F @ ParseErr { BadFormat } }
    }
}

@ from_toml_b TomlValue v → !b ParseErr {
    ^ ?? v {
        TBool x → @ !b ParseErr { T x }
        _ → @ !b ParseErr { F @ ParseErr { BadFormat } }
    }
}

// Returns a fresh owned `String` copied from the TStr payload; the
// source TomlValue is left intact. Caller frees the result.
@ from_toml_string TomlValue v → !String ParseErr {
    ^ ?? v {
        TStr s → @ !String ParseErr { T ( string_from ( string_data s ) ) }
        _ → @ !String ParseErr { F @ ParseErr { BadFormat } }
    }
}

// ── MsgPack decode helpers — `from_msgpack_<T>` ────────────────────
//
// Decode MessagePack bytes straight to a built-in value. Each runs
// `msgpack_decode` then extracts from the resulting `Json` directly —
// they deliberately do NOT call the `from_json_<T>` helpers above,
// because those return `ParseErr` and that would drag a second error
// type into the result. The value is pulled out via `json_num_as_i` /
// `json_num_as_f` (which return an Option, not a Result) or a direct
// `JBool` / `JStr` match, so `MsgpackErr` stays the only error type.
// `MsgpackTypeMismatch` means the bytes decoded fine but the value is
// not the requested type. The decoded Json is freed before return.
//
// Encoding has no helper: compose `to_json` with `msgpack_encode`.

@ from_msgpack_i ( Vec u ) bytes → !i MsgpackErr {
    ?? ( msgpack_decode bytes ) {
        T j → {
            : ?i o ( json_num_as_i j )
            ( json_free j )
            ^ ?? o {
                T n → @ !i MsgpackErr { T n }
                F → @ !i MsgpackErr { F @ MsgpackErr { MsgpackTypeMismatch } }
            }
        }
        F e → { ^ @ !i MsgpackErr { F e } }
    }
}

@ from_msgpack_f ( Vec u ) bytes → !f MsgpackErr {
    ?? ( msgpack_decode bytes ) {
        T j → {
            : ?f o ( json_num_as_f j )
            ( json_free j )
            ^ ?? o {
                T x → @ !f MsgpackErr { T x }
                F → @ !f MsgpackErr { F @ MsgpackErr { MsgpackTypeMismatch } }
            }
        }
        F e → { ^ @ !f MsgpackErr { F e } }
    }
}

@ from_msgpack_b ( Vec u ) bytes → !b MsgpackErr {
    ?? ( msgpack_decode bytes ) {
        T j → {
            : b isb ( json_is_bool j )
            : b val ( json_bool_val j )
            ( json_free j )
            ? isb { ^ @ !b MsgpackErr { T val } } {}
            ^ @ !b MsgpackErr { F @ MsgpackErr { MsgpackTypeMismatch } }
        }
        F e → { ^ @ !b MsgpackErr { F e } }
    }
}

// Returns a fresh owned `String` copied out of the decoded JStr.
@ from_msgpack_string ( Vec u ) bytes → !String MsgpackErr {
    ?? ( msgpack_decode bytes ) {
        T j → {
            ? ( json_is_str j ) {
                : String s ( string_from ( json_str_data j ) )
                ( json_free j )
                ^ @ !String MsgpackErr { T s }
            } {}
            ( json_free j )
            ^ @ !String MsgpackErr { F @ MsgpackErr { MsgpackTypeMismatch } }
        }
        F e → { ^ @ !String MsgpackErr { F e } }
    }
}
