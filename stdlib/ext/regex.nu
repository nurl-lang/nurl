// stdlib/ext/regex.nu — NFA-based regular expression engine (pure NURL)
//
// Tier 2 #13. Determinismi tärkeämpi kuin ominaisuusrunsaus —
// matching is O(n*m) (text length × NFA size) via Thompson construction
// + set-based simulation; no backtracking, no catastrophic blow-up.
//
// ── Pattern grammar ─────────────────────────────────────────────────
//
//   re        ::= alt
//   alt       ::= seq ('|' seq)*
//   seq       ::= atom*
//   atom      ::= base quant?
//   base      ::= '.' | char | escape | class | '(' alt ')' | '^' | '$'
//   quant     ::= '*' | '+' | '?'
//   class     ::= '[' '^'? class_item+ ']'
//   class_item::= char | char '-' char | escape
//   escape    ::= '\.' | '\*' | '\+' | '\?' | '\(' | '\)' | '\[' | '\]'
//               | '\|' | '\^' | '\$' | '\\' | '\/' | '\n' | '\t' | '\r'
//               | '\d' (digits 0-9) | '\D' (non-digits)
//               | '\w' (word: [A-Za-z0-9_]) | '\W' (non-word)
//               | '\s' (whitespace: space/tab/cr/lf) | '\S' (non-ws)
//
// `.` matches any byte except `\n`. Anchors `^` and `$` are zero-width
// and match only at text start / end (no multiline mode). All
// quantifiers are greedy; submatch capture is not supported.
//
// ── API ─────────────────────────────────────────────────────────────
//
//   ( regex_compile pattern )       → ! Regex ParseErr
//   ( regex_test    r text )        → b              any match anywhere
//   ( regex_match   r text )        → b              entire text matches
//   ( regex_find    r text )        → ? Match        leftmost match
//   ( regex_find_all r text )       → ( Vec Match )  non-overlapping
//   ( regex_replace  r text repl )  → String         non-overlapping replace
//   ( regex_split    r text )       → ( Vec String ) split on matches
//   ( regex_free     r )            → v
//
// `Match { i start, i len }` is a half-open span over the original text
// (text bytes [start, start+len)). Use `string_substr` on the text to
// project it to a String. Empty matches are skipped in find_all/split/
// replace to avoid infinite loops.
//
// ── Errors ──────────────────────────────────────────────────────────
//
//   ParseErr::Empty           → empty pattern
//   ParseErr::BadFormat       → malformed pattern
//   ParseErr::TrailingGarbage → unmatched `)` or `]`

$ `stdlib/core/errors.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`
$ `stdlib/core/result.nu`

// ── State kinds ─────────────────────────────────────────────────────
// 0 = Match  (accept; out1/out2 unused)
// 1 = Char   (a = byte 0..255; out1 = next on consume)
// 2 = Any    (matches any byte except '\n'; out1 = next)
// 3 = Class  (a = class index; out1 = next on consume)
// 4 = Anchor (a = 0 for '^', 1 for '$'; out1 = next, zero-width)
// 5 = Split  (out1, out2 are both ε-successors)
// 6 = Eps    (out1 = next, zero-width)

// ── Public types ────────────────────────────────────────────────────

: Match { i start i len }

// Regex is an opaque handle to a heap-allocated RegexImpl. Single-field
// struct fits in i64, which is required for `! Regex ParseErr` to take
// the narrow-enum tag-fold path.
: RegexImpl {
  ( Vec i ) states          // 4 ints/state: kind, a, out1, out2
  ( Vec i ) classes         // class store, packed
  ( Vec i ) class_starts    // class_idx → offset in classes
  i start
}

: Regex { s ctl }

// Parser state — heap-owned, freed by regex_compile.
: RxParser {
  s pat
  i len
  i pos
  ( Vec i ) states
  ( Vec i ) classes
  ( Vec i ) class_starts
}

// ── State table helpers ─────────────────────────────────────────────

@ __rx_add_state *RxParser p i kind i a i out1 i out2 → i {
  : ( Vec i ) st . p states
  : i n / ( vec_len [i] st ) 4
  ( vec_push [i] st kind )
  ( vec_push [i] st a )
  ( vec_push [i] st out1 )
  ( vec_push [i] st out2 )
  ^ n
}

@ __rx_state_kind ( Vec i ) st i idx → i {
  : *i d ( vec_data [i] st )
  ^ . d * idx 4
}

@ __rx_state_a ( Vec i ) st i idx → i {
  : *i d ( vec_data [i] st )
  ^ . d + * idx 4 1
}

@ __rx_state_out1 ( Vec i ) st i idx → i {
  : *i d ( vec_data [i] st )
  ^ . d + * idx 4 2
}

@ __rx_state_out2 ( Vec i ) st i idx → i {
  : *i d ( vec_data [i] st )
  ^ . d + * idx 4 3
}

@ __rx_set_out1 ( Vec i ) st i idx i v → v {
  : *i d ( vec_data [i] st )
  = . d + * idx 4 2 v
}

@ __rx_set_out2 ( Vec i ) st i idx i v → v {
  : *i d ( vec_data [i] st )
  = . d + * idx 4 3 v
}

// Patch the exit state's out1 (uniform fragment-exit convention).
@ __rx_patch_exit *RxParser p i exit_idx i target → v {
  ( __rx_set_out1 . p states exit_idx target )
}

// ── Class helpers ───────────────────────────────────────────────────
// A class is stored as a header word followed by 2 * n_pairs range
// words. Header layout: (n_pairs << 1) | neg_flag.

@ __rx_class_begin *RxParser p i neg → i {
  : ( Vec i ) cs . p classes
  : ( Vec i ) ofs . p class_starts
  : i idx ( vec_len [i] ofs )
  : i off ( vec_len [i] cs )
  ( vec_push [i] ofs off )
  // Reserve header slot — count filled in by __rx_class_finish.
  ( vec_push [i] cs ? != 0 neg 1 0 )
  ^ idx
}

@ __rx_class_add_range *RxParser p i lo i hi → v {
  : ( Vec i ) cs . p classes
  ( vec_push [i] cs lo )
  ( vec_push [i] cs hi )
}

@ __rx_class_finish *RxParser p i class_idx → v {
  : ( Vec i ) cs . p classes
  : ( Vec i ) ofs . p class_starts
  : i off ( __vi_get ofs class_idx )
  : i header ( __vi_get cs off )
  : i n_pairs / - ( vec_len [i] cs ) + off 1 2
  : i new_header | * n_pairs 2 & header 1
  : *i d ( vec_data [i] cs )
  = . d off new_header
}

@ __rx_class_test ( Vec i ) classes ( Vec i ) class_starts i class_idx i ch → b {
  : i off ( __vi_get class_starts class_idx )
  : i header ( __vi_get classes off )
  : b neg != 0 & header 1
  : i n_pairs / header 2
  : ~ i k 0
  : ~ b found F
  ~ < k n_pairs {
    : i lo ( __vi_get classes + off + 1 * k 2 )
    : i hi ( __vi_get classes + off + 2 * k 2 )
    ? & >= ch lo <= ch hi { = found T } {}
    = k + k 1
  }
  ^ ? neg ! found found
}

// ── Vec[i] direct access (skip Option wrapping for hot paths) ───────

@ __vi_get ( Vec i ) v i idx → i {
  : *i d ( vec_data [i] v )
  ^ . d idx
}

@ __vi_set ( Vec i ) v i idx i x → v {
  : *i d ( vec_data [i] v )
  = . d idx x
}

// ── Character-class helpers (for escapes) ───────────────────────────

@ __is_digit_byte i c → b { ^ & >= c 48 <= c 57 }
@ __is_word_byte i c → b {
  ^ | | | & >= c 65 <= c 90 & >= c 97 <= c 122 & >= c 48 <= c 57 == c 95
}
@ __is_space_byte i c → b {
  ^ | | | == c 32 == c 9 == c 10 == c 13
}

// Build a built-in class for \d, \D, \w, \W, \s, \S. Returns class_idx.
@ __rx_builtin_class *RxParser p i which → i {
  // which: 0=\d 1=\D 2=\w 3=\W 4=\s 5=\S
  : i neg ? | == which 1 | == which 3 == which 5 1 0
  : i idx ( __rx_class_begin p neg )
  ? | == which 0 == which 1 {
    ( __rx_class_add_range p 48 57 )
  } {}
  ? | == which 2 == which 3 {
    ( __rx_class_add_range p 48 57 )
    ( __rx_class_add_range p 65 90 )
    ( __rx_class_add_range p 97 122 )
    ( __rx_class_add_range p 95 95 )
  } {}
  ? | == which 4 == which 5 {
    ( __rx_class_add_range p 9 10 )
    ( __rx_class_add_range p 13 13 )
    ( __rx_class_add_range p 32 32 )
  } {}
  ( __rx_class_finish p idx )
  ^ idx
}

// ── Parser cursor helpers ───────────────────────────────────────────

@ __rx_eof *RxParser p → b { ^ >= . p pos . p len }
@ __rx_peek *RxParser p → i {
  ? ( __rx_eof p ) { ^ -1 } {}
  ^ ( nurl_str_get . p pat . p pos )
}
@ __rx_bump *RxParser p → i {
  : i c ( __rx_peek p )
  =. p pos + . p pos 1
  ^ c
}

// ── Escape decode ───────────────────────────────────────────────────
// Returns: kind in slot 0 (0=literal 1=class), value in slot 1.
//   For literal: slot1 = byte value.
//   For class:  slot1 = class index.
// Encoded into a single i: (kind << 16) | (value & 0xFFFF).
// The class indices stay well under 65535 in any sane pattern.

@ __rx_decode_escape *RxParser p → i {
  : i c ( __rx_peek p )
  =. p pos + . p pos 1
  // Plain meta-literals: . * + ? ( ) [ ] | ^ $ \ /
  ? | | | | | | | | | | | | == c 46 == c 42 == c 43 == c 63 == c 40 == c 41 == c 91 == c 93 == c 124 == c 94 == c 36 == c 92 == c 47
    { ^ & c 65535 } {}
  // Whitespace literals
  ? == c 110 { ^ 10 } {}    // \n
  ? == c 116 { ^ 9 } {}     // \t
  ? == c 114 { ^ 13 } {}    // \r
  ? == c 102 { ^ 12 } {}    // \f
  ? == c 118 { ^ 11 } {}    // \v
  ? == c 48  { ^ 0 } {}     // \0
  // Built-in classes
  : ~ i which -1
  ? == c 100 { = which 0 } {}    // \d
  ? == c 68  { = which 1 } {}    // \D
  ? == c 119 { = which 2 } {}    // \w
  ? == c 87  { = which 3 } {}    // \W
  ? == c 115 { = which 4 } {}    // \s
  ? == c 83  { = which 5 } {}    // \S
  ? >= which 0 {
    : i ci ( __rx_builtin_class p which )
    ^ | * 1 65536 ci
  } {}
  // Unknown escape: treat as literal of the escaped byte (forgiving).
  ^ & c 65535
}

// ── NFA fragment ─────────────────────────────────────────────────────
// A fragment encodes (entry_state_idx, exit_state_idx) as one i64:
// (entry << 32) | (exit & 0xFFFFFFFF). Both fit in 32 bits — patterns
// with 4-billion states are not a concern.

@ __frag i en i ex → i { ^ | * en 4294967296 & ex 4294967295 }
@ __frag_entry i f → i { ^ / f 4294967296 }
@ __frag_exit  i f → i { ^ & f 4294967295 }

// ── Emit primitives ─────────────────────────────────────────────────
// Convention: every fragment's "exit" is a state whose out1 is unset
// and gets patched by the next concat.

@ __emit_char *RxParser p i c → i {
  : i s1 ( __rx_add_state p 1 c -1 -1 )
  : i s2 ( __rx_add_state p 6 0 -1 -1 )
  ( __rx_set_out1 . p states s1 s2 )
  ^ ( __frag s1 s2 )
}

@ __emit_any *RxParser p → i {
  : i s1 ( __rx_add_state p 2 0 -1 -1 )
  : i s2 ( __rx_add_state p 6 0 -1 -1 )
  ( __rx_set_out1 . p states s1 s2 )
  ^ ( __frag s1 s2 )
}

@ __emit_class *RxParser p i ci → i {
  : i s1 ( __rx_add_state p 3 ci -1 -1 )
  : i s2 ( __rx_add_state p 6 0 -1 -1 )
  ( __rx_set_out1 . p states s1 s2 )
  ^ ( __frag s1 s2 )
}

@ __emit_anchor *RxParser p i which → i {
  : i s1 ( __rx_add_state p 4 which -1 -1 )
  : i s2 ( __rx_add_state p 6 0 -1 -1 )
  ( __rx_set_out1 . p states s1 s2 )
  ^ ( __frag s1 s2 )
}

@ __emit_concat *RxParser p i fa i fb → i {
  ( __rx_patch_exit p ( __frag_exit fa ) ( __frag_entry fb ) )
  ^ ( __frag ( __frag_entry fa ) ( __frag_exit fb ) )
}

@ __emit_alt *RxParser p i fa i fb → i {
  : i merge ( __rx_add_state p 6 0 -1 -1 )
  ( __rx_patch_exit p ( __frag_exit fa ) merge )
  ( __rx_patch_exit p ( __frag_exit fb ) merge )
  : i split ( __rx_add_state p 5 0 ( __frag_entry fa ) ( __frag_entry fb ) )
  ^ ( __frag split merge )
}

@ __emit_star *RxParser p i fa → i {
  : i merge ( __rx_add_state p 6 0 -1 -1 )
  : i split ( __rx_add_state p 5 0 ( __frag_entry fa ) merge )
  ( __rx_patch_exit p ( __frag_exit fa ) split )
  ^ ( __frag split merge )
}

@ __emit_plus *RxParser p i fa → i {
  : i merge ( __rx_add_state p 6 0 -1 -1 )
  : i split ( __rx_add_state p 5 0 ( __frag_entry fa ) merge )
  ( __rx_patch_exit p ( __frag_exit fa ) split )
  ^ ( __frag ( __frag_entry fa ) merge )
}

@ __emit_optional *RxParser p i fa → i {
  : i merge ( __rx_add_state p 6 0 -1 -1 )
  : i split ( __rx_add_state p 5 0 ( __frag_entry fa ) merge )
  ( __rx_patch_exit p ( __frag_exit fa ) merge )
  ^ ( __frag split merge )
}

// ── Pattern parser (recursive descent) ──────────────────────────────
// Returns a fragment encoded as i, or -1 on parse error. The caller
// translates -1 into ParseErr::BadFormat.

@ __parse_class *RxParser p → i {
  // ASSUMES position past '['. Builds a class and emits a class state
  // fragment. Returns fragment, or -1 on error.
  : i neg 0
  ? == ( __rx_peek p ) 94 {
    =. p pos + . p pos 1
    = neg 1
  } {}
  : i ci ( __rx_class_begin p neg )
  : ~ b done F
  : ~ b error F
  : ~ i n_added 0
  ~ & ! done ! error {
    ? ( __rx_eof p ) { = error T } {
      : i c ( __rx_peek p )
      ? == c 93 {                            // ']'
        =. p pos + . p pos 1
        = done T
      } {
        : ~ i lo 0
        : ~ b is_class_member F
        : ~ i member_class_idx -1
        ? == c 92 {                          // '\'
          =. p pos + . p pos 1
          : i enc ( __rx_decode_escape p )
          : i kind / enc 65536
          : i val & enc 65535
          ? == kind 1 {
            = is_class_member T
            = member_class_idx val
          } {
            = lo val
          }
        } {
          =. p pos + . p pos 1
          = lo c
        }
        ? is_class_member {
          // Inline a class's ranges into the current class.
          : ( Vec i ) cs . p classes
          : ( Vec i ) ofs . p class_starts
          : i moff ( __vi_get ofs member_class_idx )
          : i mhdr ( __vi_get cs moff )
          : i mn / mhdr 2
          : ~ i k 0
          ~ < k mn {
            : i mlo ( __vi_get cs + moff + 1 * k 2 )
            : i mhi ( __vi_get cs + moff + 2 * k 2 )
            ( __rx_class_add_range p mlo mhi )
            = n_added + n_added 1
            = k + k 1
          }
        } {
          // Possibly a range like 'a-z'.
          : ~ i hi lo
          ? & ! ( __rx_eof p ) == ( __rx_peek p ) 45 {
            // Look ahead: '-' must not be ']' otherwise treat as literal '-'.
            : i p2 + . p pos 1
            ? & < p2 . p len != ( nurl_str_get . p pat p2 ) 93 {
              =. p pos + . p pos 1            // consume '-'
              : i nx ( __rx_peek p )
              ? == nx 92 {
                =. p pos + . p pos 1
                : i enc2 ( __rx_decode_escape p )
                : i kind2 / enc2 65536
                ? == kind2 1 { = error T } { = hi & enc2 65535 }
              } {
                =. p pos + . p pos 1
                = hi nx
              }
            } {}
          } {}
          ? ! error {
            ( __rx_class_add_range p lo hi )
            = n_added + n_added 1
          } {}
        }
      }
    }
  }
  ? error { ^ -1 } {}
  ? == n_added 0 { ^ -1 } {}
  ( __rx_class_finish p ci )
  ^ ( __emit_class p ci )
}

// Forward declaration via mutual recursion: __parse_alt and __parse_atom
// reference each other through __parse_seq.

@ __parse_atom *RxParser p → i {
  ? ( __rx_eof p ) { ^ -1 } {}
  : i c ( __rx_peek p )
  : ~ i frag -1
  ? == c 46 {                                // '.'
    =. p pos + . p pos 1
    = frag ( __emit_any p )
  } {
    ? == c 94 {                              // '^'
      =. p pos + . p pos 1
      = frag ( __emit_anchor p 0 )
    } {
      ? == c 36 {                            // '$'
        =. p pos + . p pos 1
        = frag ( __emit_anchor p 1 )
      } {
        ? == c 40 {                          // '('
          =. p pos + . p pos 1
          : i inner ( __parse_alt p )
          ? < inner 0 { ^ -1 } {}
          ? != ( __rx_peek p ) 41 { ^ -1 } {}
          =. p pos + . p pos 1
          = frag inner
        } {
          ? == c 91 {                        // '['
            =. p pos + . p pos 1
            : i fc ( __parse_class p )
            ? < fc 0 { ^ -1 } {}
            = frag fc
          } {
            ? == c 92 {                      // '\\'
              =. p pos + . p pos 1
              : i enc ( __rx_decode_escape p )
              : i kind / enc 65536
              : i val & enc 65535
              ? == kind 1 { = frag ( __emit_class p val ) }
                          { = frag ( __emit_char p val ) }
            } {
              // Reject metachars that should not appear at atom start.
              ? | | | | | == c 42 == c 43 == c 63 == c 41 == c 124 == c 93 { ^ -1 } {}
              =. p pos + . p pos 1
              = frag ( __emit_char p c )
            }
          }
        }
      }
    }
  }
  // Quantifier
  ? < frag 0 { ^ -1 } {}
  ? ! ( __rx_eof p ) {
    : i q ( __rx_peek p )
    ? == q 42 { =. p pos + . p pos 1 = frag ( __emit_star p frag ) } {
      ? == q 43 { =. p pos + . p pos 1 = frag ( __emit_plus p frag ) } {
        ? == q 63 { =. p pos + . p pos 1 = frag ( __emit_optional p frag ) } {}
      }
    }
  } {}
  ^ frag
}

@ __parse_seq *RxParser p → i {
  // Empty seq → epsilon fragment (one Eps state pointing nowhere; will
  // be patched).
  : ~ i acc -1
  : ~ b done F
  ~ ! done {
    ? ( __rx_eof p ) { = done T } {
      : i c ( __rx_peek p )
      ? | == c 124 == c 41 { = done T } {
        : i atom ( __parse_atom p )
        ? < atom 0 { ^ -1 } {}
        ? < acc 0 { = acc atom } { = acc ( __emit_concat p acc atom ) }
      }
    }
  }
  ? < acc 0 {
    // Empty seq → single Eps state.
    : i s1 ( __rx_add_state p 6 0 -1 -1 )
    = acc ( __frag s1 s1 )
  } {}
  ^ acc
}

@ __parse_alt *RxParser p → i {
  : i first ( __parse_seq p )
  ? < first 0 { ^ -1 } {}
  : ~ i acc first
  : ~ b done F
  ~ ! done {
    ? ( __rx_eof p ) { = done T } {
      ? != ( __rx_peek p ) 124 { = done T } {
        =. p pos + . p pos 1
        : i rhs ( __parse_seq p )
        ? < rhs 0 { ^ -1 } {}
        = acc ( __emit_alt p acc rhs )
      }
    }
  }
  ^ acc
}

// ── Compile entry ───────────────────────────────────────────────────

@ regex_compile s pattern → ! Regex ParseErr {
  : i n ( nurl_str_len pattern )
  ? == n 0 {
    ^ @ ! Regex ParseErr { F @ ParseErr { Empty } }
  } {}
  : *RxParser p # *RxParser ( nurl_alloc Z RxParser )
  =. p pat pattern
  =. p len n
  =. p pos 0
  =. p states ( vec_new [i] )
  =. p classes ( vec_new [i] )
  =. p class_starts ( vec_new [i] )
  : i frag ( __parse_alt p )
  ? < frag 0 {
    ( vec_free [i] . p states )
    ( vec_free [i] . p classes )
    ( vec_free [i] . p class_starts )
    ( nurl_free #s p )
    ^ @ ! Regex ParseErr { F @ ParseErr { BadFormat } }
  } {}
  ? < . p pos . p len {
    // Trailing `)` or `]` is not consumed by parser → reject.
    ( vec_free [i] . p states )
    ( vec_free [i] . p classes )
    ( vec_free [i] . p class_starts )
    ( nurl_free #s p )
    ^ @ ! Regex ParseErr { F @ ParseErr { TrailingGarbage } }
  } {}
  // Patch the fragment exit to a fresh Match state.
  : i match_state ( __rx_add_state p 0 0 -1 -1 )
  ( __rx_patch_exit p ( __frag_exit frag ) match_state )
  : i start_idx ( __frag_entry frag )
  : *RegexImpl impl # *RegexImpl ( nurl_alloc Z RegexImpl )
  =. impl states . p states
  =. impl classes . p classes
  =. impl class_starts . p class_starts
  =. impl start start_idx
  : Regex r @ Regex { #s impl }
  ( nurl_free #s p )
  ^ @ ! Regex ParseErr { T r }
}

@ regex_free Regex r → v {
  : *RegexImpl impl #*RegexImpl . r ctl
  ( vec_free [i] . impl states )
  ( vec_free [i] . impl classes )
  ( vec_free [i] . impl class_starts )
  ( nurl_free #s impl )
}

// ── Match engine ────────────────────────────────────────────────────
// Two-set NFA simulation. We store active states as a Vec[i] of state
// indices, plus a parallel "marked" buffer (raw bytes via nurl_zalloc)
// to dedupe. Each step advances current → next on consuming one byte,
// then we swap.

// Vec[i]-based active-set machinery — recursive ε-closure walk that
// dedupes via a parallel `marked` vector. Char/Any/Class/Match states
// land on the active list; Eps/Split/Anchor are zero-width and walked
// transitively.

@ __rx_add_active_v ( Vec i ) states ( Vec i ) active ( Vec i ) marked i s_idx i text_pos i text_len → v {
  ? >= s_idx 0 {
    : i was ( __vi_get marked s_idx )
    ? == was 0 {
      ( __vi_set marked s_idx 1 )
      : i kind ( __rx_state_kind states s_idx )
      ? == kind 6 {
        : i o1 ( __rx_state_out1 states s_idx )
        ( __rx_add_active_v states active marked o1 text_pos text_len )
      } {
        ? == kind 5 {
          : i o1 ( __rx_state_out1 states s_idx )
          : i o2 ( __rx_state_out2 states s_idx )
          ( __rx_add_active_v states active marked o1 text_pos text_len )
          ( __rx_add_active_v states active marked o2 text_pos text_len )
        } {
          ? == kind 4 {
            : i a ( __rx_state_a states s_idx )
            : b matches ? == a 0 == text_pos 0 == text_pos text_len
            ? matches {
              : i o1 ( __rx_state_out1 states s_idx )
              ( __rx_add_active_v states active marked o1 text_pos text_len )
            } {}
          } {
            ( vec_push [i] active s_idx )
          }
        }
      }
    } {}
  } {}
}

@ __rx_clear_marked ( Vec i ) marked i n → v {
  : ~ i k 0
  ~ < k n {
    ( __vi_set marked k 0 )
    = k + k 1
  }
}

// Try to match starting at text_pos. Returns the longest match length
// found at this start (≥0), or -1 if no match.
@ __rx_run_at Regex r s text i text_len i text_pos → i {
  : *RegexImpl impl #*RegexImpl . r ctl
  : ( Vec i ) states . impl states
  : ( Vec i ) classes . impl classes
  : ( Vec i ) class_starts . impl class_starts
  : i start . impl start
  : i nstates / ( vec_len [i] states ) 4
  : ( Vec i ) cur ( vec_with_cap [i] nstates )
  : ( Vec i ) nxt ( vec_with_cap [i] nstates )
  : ( Vec i ) marked_cur ( vec_with_cap [i] nstates )
  : ( Vec i ) marked_nxt ( vec_with_cap [i] nstates )
  // Initialize marked vectors to length nstates with 0.
  : ~ i k 0
  ~ < k nstates {
    ( vec_push [i] marked_cur 0 )
    ( vec_push [i] marked_nxt 0 )
    = k + k 1
  }
  ( __rx_add_active_v states cur marked_cur start text_pos text_len )

  : ~ i best -1
  // Check if start state itself is the match (zero-length match).
  : ~ i k2 0
  ~ < k2 ( vec_len [i] cur ) {
    : i sx ( __vi_get cur k2 )
    ? == ( __rx_state_kind states sx ) 0 { = best 0 } {}
    = k2 + k2 1
  }

  : ~ i pos text_pos
  : ~ b done F
  ~ ! done {
    ? >= pos text_len { = done T } {
      : i ch ( nurl_str_get text pos )
      ( __rx_clear_marked marked_nxt nstates )
      ( vec_clear [i] nxt )
      : ~ i ki 0
      ~ < ki ( vec_len [i] cur ) {
        : i si ( __vi_get cur ki )
        : i kind ( __rx_state_kind states si )
        : ~ b consumes F
        ? == kind 1 {                       // Char
          ? == ( __rx_state_a states si ) ch { = consumes T } {}
        } {
          ? == kind 2 {                     // Any (not '\n')
            ? != ch 10 { = consumes T } {}
          } {
            ? == kind 3 {                   // Class
              : i ci ( __rx_state_a states si )
              ? ( __rx_class_test classes class_starts ci ch ) { = consumes T } {}
            } {}
          }
        }
        ? consumes {
          : i nxt_state ( __rx_state_out1 states si )
          ( __rx_add_active_v states nxt marked_nxt nxt_state + pos 1 text_len )
        } {}
        = ki + ki 1
      }
      = pos + pos 1
      // Swap cur/nxt and their marked sets.
      : ( Vec i ) tmp cur
      = cur nxt
      = nxt tmp
      : ( Vec i ) tmpm marked_cur
      = marked_cur marked_nxt
      = marked_nxt tmpm
      // After consuming a byte, check if any state in the new cur is
      // a Match — record longest.
      : ~ i kj 0
      ~ < kj ( vec_len [i] cur ) {
        : i sk ( __vi_get cur kj )
        ? == ( __rx_state_kind states sk ) 0 { = best - pos text_pos } {}
        = kj + kj 1
      }
      ? == ( vec_len [i] cur ) 0 { = done T } {}
    }
  }

  ( vec_free [i] cur )
  ( vec_free [i] nxt )
  ( vec_free [i] marked_cur )
  ( vec_free [i] marked_nxt )
  ^ best
}

// ── Public match API ────────────────────────────────────────────────

@ regex_test Regex r s text → b {
  : i n ( nurl_str_len text )
  : ~ i pos 0
  ~ <= pos n {
    : i m ( __rx_run_at r text n pos )
    ? >= m 0 { ^ T } {}
    = pos + pos 1
  }
  ^ F
}

@ regex_match Regex r s text → b {
  : i n ( nurl_str_len text )
  : i m ( __rx_run_at r text n 0 )
  ^ == m n
}

@ regex_find Regex r s text → ? Match {
  : i n ( nurl_str_len text )
  : ~ i pos 0
  ~ <= pos n {
    : i m ( __rx_run_at r text n pos )
    ? >= m 0 {
      ^ @ ? Match { T @ Match { pos m } }
    } {}
    = pos + pos 1
  }
  ^ @ ? Match { F @ Match { 0 0 } }
}

@ regex_find_all Regex r s text → ( Vec Match ) {
  : ( Vec Match ) out ( vec_new [Match] )
  : i n ( nurl_str_len text )
  : ~ i pos 0
  ~ <= pos n {
    : i m ( __rx_run_at r text n pos )
    ? >= m 0 {
      ( vec_push [Match] out @ Match { pos m } )
      ? == m 0 { = pos + pos 1 } { = pos + pos m }
    } {
      = pos + pos 1
    }
  }
  ^ out
}

@ regex_replace Regex r s text s repl → String {
  : String out ( string_with_cap ( nurl_str_len text ) )
  : i n ( nurl_str_len text )
  : ~ i pos 0
  ~ <= pos n {
    : i m ( __rx_run_at r text n pos )
    ? >= m 0 {
      ( string_push_str out repl )
      ? == m 0 {
        ? < pos n {
          ( string_push_char out ( nurl_str_get text pos ) )
          = pos + pos 1
        } { = pos + pos 1 }
      } { = pos + pos m }
    } {
      ? < pos n {
        ( string_push_char out ( nurl_str_get text pos ) )
      } {}
      = pos + pos 1
    }
  }
  ^ out
}

@ regex_split Regex r s text → ( Vec String ) {
  : ( Vec String ) out ( vec_new [String] )
  : i n ( nurl_str_len text )
  : ~ i seg_start 0
  : ~ i pos 0
  ~ <= pos n {
    : i m ( __rx_run_at r text n pos )
    ? & >= m 0 > m 0 {
      // Emit segment [seg_start..pos)
      : i seg_len - pos seg_start
      : String s1 ( string_with_cap seg_len )
      : ~ i k seg_start
      ~ < k pos {
        ( string_push_char s1 ( nurl_str_get text k ) )
        = k + k 1
      }
      ( vec_push [String] out s1 )
      = pos + pos m
      = seg_start pos
    } { = pos + pos 1 }
  }
  // Emit final segment [seg_start..n)
  : i tail_len - n seg_start
  : String tail ( string_with_cap tail_len )
  : ~ i k seg_start
  ~ < k n {
    ( string_push_char tail ( nurl_str_get text k ) )
    = k + k 1
  }
  ( vec_push [String] out tail )
  ^ out
}
