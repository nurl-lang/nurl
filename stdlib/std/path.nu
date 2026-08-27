// stdlib/std/path.nu — path manipulation (cross-platform separators)
//
// All functions accept either '/' or '\\' as separators on input
// (Windows users routinely mix the two). Output paths are emitted with
// '/' — both Win32 CRT (fopen, mkdir) and POSIX accept this, and using
// a single canonical separator keeps tests deterministic across hosts.
//
// All path inputs are raw `s` (i8*) — pass a literal directly, or use
// `( string_data s )` to feed an owned `String`'s buffer. Returned
// Strings are owned (caller frees / lets auto-drop run).
//
//   ( path_join a b )       → String  drops a trailing sep on `a`, leading sep on `b`
//   ( path_basename p )     → String  segment after the last separator
//   ( path_dirname p )      → String  everything before the last component (POSIX: `.` when there is none)
//   ( path_extension p )    → String  text after the last '.' in the basename, "" if none
//   ( path_is_absolute p )  → b       starts with '/' / '\\' or matches X: drive prefix
//   ( path_normalize p )    → String  collapses '.', '..', and duplicate separators
//
// ── Typed Path ──────────────────────────────────────────────────────
//
// `Path { String inner }` is a typed, owning wrapper over a path string
// — it makes "this value is a path" explicit in a signature and carries
// ownership clearly. The typed layer uses concise Rust-PathBuf-style
// verbs; the `s`-based functions above stay the raw layer underneath.
//
//   ( path_new s )              → Path     wrap a copy of a path string
//   ( path_str p )              → s        borrow the inner buffer (fs interop)
//   ( path_len p )              → i
//   ( path_is_empty p )         → b
//   ( path_clone p )            → Path     deep copy
//   ( path_free p )             → v        free the inner String
//   ( path_eq a b )             → b
//   ( path_push base child )    → Path     base joined with one component
//   ( path_parent p )           → Path     directory containing `p`
//   ( path_name p )             → Path     final component of `p`
//   ( path_is_abs p )           → b
//   ( path_canonical p )        → ? Path   realpath: absolute, symlinks
//                                          resolved; None if `p` is missing
//   ( path_relative_to base p ) → ? Path   lexical relative path from
//                                          `base` to `p`; None if the two
//                                          are not comparable (one
//                                          absolute, one relative, or
//                                          different Windows drives)
//
// path_canonical is the one function here that touches the filesystem
// (it resolves symlinks and requires the path to exist); everything
// else is pure string computation. Both ? -returning functions yield
// None rather than an error code — for a missing path, probe first with
// fs.nu's file_exists when the distinction matters.
//
// A Path owns its String: free it with path_free or let auto-drop run
// at scope exit. The typed functions never consume their arguments —
// each returns a fresh Path — so the caller frees every Path it holds.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ __is_sep i c → b {
    ? == c 47 { ^ T } {}
    ? == c 92 { ^ T } {}
    ^ F
}

// Windows drive-letter prefix: ASCII letter followed by ':'.
@ __has_drive s p → b {
    : i n ( nurl_str_len p )
    ? < n 2 { ^ F } {}
    : i c0 ( nurl_str_at p n 0 )
    : i c1 ( nurl_str_at p n 1 )
    ? != c1 58 { ^ F } {}
    ? & <= 65 c0 <= c0 90 { ^ T } {}
    ? & <= 97 c0 <= c0 122 { ^ T } {}
    ^ F
}

@ path_is_absolute s p → b {
    : i n ( nurl_str_len p )
    ? == n 0 { ^ F } {}
    : i c0 ( nurl_str_at p n 0 )
    ? ( __is_sep c0 ) { ^ T } {}
    ? ( __has_drive p ) { ^ T } {}
    ^ F
}

// Last separator index, or -1 if none.
@ __last_sep_idx s p → i {
    : i n ( nurl_str_len p )
    : ~ i i - n 1
    : ~ i out - 0 1
    : ~ b going T
    ~ going {
        ? < i 0 { = going F } {
            : i c ( nurl_str_at p n i )
            ? ( __is_sep c ) {
                = out i
                = going F
            } {
                = i - i 1
            }
        }
    }
    ^ out
}

@ __substr_to_string s p i from i len → String {
    : i n ( nurl_str_len p )
    : String out ( string_with_cap len )
    : ~ i i 0
    ~ < i len {
        ( string_push_char out ( nurl_str_at p n + from i ) )
        = i + i 1
    }
    ^ out
}

// Index of the last byte of `p` that is not a trailing separator, or 0
// when `p` is empty or made of separators only. POSIX basename and
// dirname both begin here: `/a/b/` names `b`, not the empty string
// after the final slash.
@ __trimmed_end s p → i {
    : i n ( nurl_str_len p )
    : ~ i e n
    ~ & > e 0 ( __is_sep ( nurl_str_at p n - e 1 ) ) { = e - e 1 }
    ^ e
}

// Last separator strictly before `end`, or -1.
@ __sep_before s p i end → i {
    : i n ( nurl_str_len p )
    : ~ i i - end 1
    : ~ i out -1
    ~ >= i 0 {
        ? ( __is_sep ( nurl_str_at p n i ) ) {
            = out i
            = i -1
        } { = i - i 1 }
    }
    ^ out
}

@ __one_slash → String {
    : String r ( string_with_cap 1 )
    ( string_push_char r 47 )
    ^ r
}

// POSIX basename(3): the final component, with trailing separators
// ignored. `/a/b/` → `b`, `/` → `/`, `foo` → `foo`. The empty path
// stays empty (POSIX says `.`; every shell's `basename ""` prints an
// empty line, and that is what callers here expect).
@ path_basename s p → String {
    : i n ( nurl_str_len p )
    ? == n 0 { ^ ( string_new ) } {}
    : i end ( __trimmed_end p )
    // All separators: the path names the root, and the root's name is
    // the root.
    ? == end 0 { ^ ( __one_slash ) } {}
    : i idx ( __sep_before p end )
    ? < idx 0 {
        ? ( __has_drive p ) { ^ ( __substr_to_string p 2 - end 2 ) } {}
        ^ ( __substr_to_string p 0 end )
    } {}
    : i start + idx 1
    ^ ( __substr_to_string p start - end start )
}

// POSIX dirname(3): everything before the final component, with
// trailing separators ignored and no trailing separator on the result.
// `/a/b/c` → `/a/b`, `/a/b/` → `/a`, `foo` → `.`, `/foo` → `/`.
//
// A path with no separator answers `.`, not the empty string: the
// result is meant to be usable as a path, and `""` is not one — a
// caller that joined it back on would address the filesystem root.
@ path_dirname s p → String {
    : i n ( nurl_str_len p )
    ? == n 0 { ^ ( string_from `.` ) } {}
    : i end ( __trimmed_end p )
    ? == end 0 { ^ ( __one_slash ) } {}
    : i idx ( __sep_before p end )
    ? < idx 0 {
        ? ( __has_drive p ) { ^ ( __substr_to_string p 0 2 ) } {}
        ^ ( string_from `.` )
    } {}
    ? == idx 0 { ^ ( __one_slash ) } {}
    // Collapse the run of separators before the last component.
    : ~ i cut idx
    ~ & > cut 0 ( __is_sep ( nurl_str_at p n - cut 1 ) ) { = cut - cut 1 }
    ? == cut 0 { ^ ( __one_slash ) } {}
    ? & == cut 2 ( __has_drive p ) { ^ ( __substr_to_string p 0 3 ) } {}
    ^ ( __substr_to_string p 0 cut )
}

@ path_extension s p → String {
    : i n ( nurl_str_len p )
    ? == n 0 { ^ ( string_new ) } {}
    : i sep_idx ( __last_sep_idx p )
    : i base_start + sep_idx 1
    : i base_len - n base_start
    ? == base_len 0 { ^ ( string_new ) } {}
    : ~ i i - + base_start base_len 1
    : ~ i found - 0 1
    : ~ b going T
    ~ going {
        ? < i base_start { = going F } {
            : i c ( nurl_str_at p n i )
            ? == c 46 {
                = found i
                = going F
            } { = i - i 1 }
        }
    }
    ? < found 0 { ^ ( string_new ) } {}
    // Leading-dot files ("/x/.bashrc", ".") have no extension.
    ? == found base_start { ^ ( string_new ) } {}
    : i ext_start + found 1
    : i ext_len - + base_start base_len ext_start
    ^ ( __substr_to_string p ext_start ext_len )
}

@ path_join s a s b → String {
    : i la ( nurl_str_len a )
    : i lb ( nurl_str_len b )
    ? == la 0 { ^ ( __substr_to_string b 0 lb ) } {}
    ? == lb 0 { ^ ( __substr_to_string a 0 la ) } {}
    ? ( path_is_absolute b ) { ^ ( __substr_to_string b 0 lb ) } {}
    // Trim trailing separators from `a` (keep at least one byte).
    : ~ i ae la
    : ~ b going T
    ~ going {
        ? <= ae 1 { = going F } {
            : i c ( nurl_str_at a la - ae 1 )
            ? ( __is_sep c ) { = ae - ae 1 } { = going F }
        }
    }
    // Skip leading separators in `b`.
    : ~ i bs 0
    = going T
    ~ going {
        ? >= bs lb { = going F } {
            : i c ( nurl_str_at b lb bs )
            ? ( __is_sep c ) { = bs + bs 1 } { = going F }
        }
    }
    : String out ( string_with_cap + + ae - lb bs 1 )
    : ~ i i 0
    ~ < i ae {
        ( string_push_char out ( nurl_str_at a la i ) )
        = i + i 1
    }
    // The trim keeps at least one byte, so a root `a` — `/` or `C:/` —
    // still ends in a separator. Adding a second one produced `//d`,
    // which is a different path on some systems and an ugly one on all
    // of them.
    ? ! ( __is_sep ( nurl_str_at a la - ae 1 ) ) { ( string_push_char out 47 ) } {}
    : ~ i j bs
    ~ < j lb {
        ( string_push_char out ( nurl_str_at b lb j ) )
        = j + j 1
    }
    ^ out
}

// Internal: split path into stack of owned segment Strings, after the
// optional drive/root prefix. The caller passes `pos` = first byte after
// any leading separators or drive letter that's already been handled.
@ __collect_segments s p i pos → ( Vec String ) {
    : i n ( nurl_str_len p )
    : ( Vec String ) out ( vec_new [String] )
    : ~ i i pos
    : ~ b going T
    ~ going {
        ? > i n { = going F } {
            : i s i
            : ~ b in_seg T
            ~ in_seg {
                ? >= i n { = in_seg F } {
                    : i c ( nurl_str_at p n i )
                    ? ( __is_sep c ) { = in_seg F } { = i + i 1 }
                }
            }
            : i seg_len - i s
            ? > seg_len 0 {
                ( vec_push [String] out ( __substr_to_string p s seg_len ) )
            } {}
            ? >= i n { = going F } {
                : ~ b skip_sep T
                ~ skip_sep {
                    ? >= i n { = skip_sep F } {
                        : i c2 ( nurl_str_at p n i )
                        ? ( __is_sep c2 ) { = i + i 1 } { = skip_sep F }
                    }
                }
            }
        }
    }
    ^ out
}

@ __is_dot String s → b {
    ? != ( string_len s ) 1 { ^ F } {}
    ^ == ( string_get s 0 ) 46
}

@ __is_dotdot String s → b {
    ? != ( string_len s ) 2 { ^ F } {}
    ? != ( string_get s 0 ) 46 { ^ F } {}
    ^ == ( string_get s 1 ) 46
}

@ path_normalize s p → String {
    : ( @ v String ) drop_str \ String s → v { ( string_free s ) }
    : i n ( nurl_str_len p )
    ? == n 0 {
        : String dot ( string_with_cap 1 )
        ( string_push_char dot 46 )
        ^ dot
    } {}
    : i drive_end ? ( __has_drive p ) 2 0
    : ~ i pos drive_end
    : ~ b absolute F
    ? < pos n {
        : i c ( nurl_str_at p n pos )
        ? ( __is_sep c ) {
            = absolute T
            = pos + pos 1
            : ~ b skip_sep T
            ~ skip_sep {
                ? >= pos n { = skip_sep F } {
                    : i c2 ( nurl_str_at p n pos )
                    ? ( __is_sep c2 ) { = pos + pos 1 } { = skip_sep F }
                }
            }
        } {}
    } {}
    : ( Vec String ) segs ( __collect_segments p pos )
    : ( Vec String ) stk ( vec_new [String] )
    : i count ( vec_len [String] segs )
    : ~ i k 0
    ~ < k count {
        : ?String seg_opt ( vec_get [String] segs k )
        ?? seg_opt {
            T seg → {
                ? ( __is_dot seg ) {
                    // drop "." segment
                } {
                    ? ( __is_dotdot seg ) {
                        : i sn ( vec_len [String] stk )
                        ? > sn 0 {
                            : ?String top_opt ( vec_get [String] stk - sn 1 )
                            ?? top_opt {
                                T t → {
                                    ? ( __is_dotdot t ) {
                                        ( vec_push [String] stk ( __substr_to_string `..` 0 2 ) )
                                    } {
                                        : ?String pop_opt ( vec_pop [String] stk )
                                        ?? pop_opt {
                                            T popped → ( string_free popped )
                                            F → {}
                                        }
                                    }
                                }
                                F → ( vec_push [String] stk ( __substr_to_string `..` 0 2 ) )
                            }
                        } {
                            ? absolute {
                                // ".." past root → drop
                            } {
                                ( vec_push [String] stk ( __substr_to_string `..` 0 2 ) )
                            }
                        }
                    } {
                        : i sl ( string_len seg )
                        : String copy ( string_with_cap sl )
                        : ~ i bi 0
                        ~ < bi sl {
                            ( string_push_char copy ( string_get seg bi ) )
                            = bi + bi 1
                        }
                        ( vec_push [String] stk copy )
                    }
                }
            }
            F → {}
        }
        = k + k 1
    }
    ( vec_free_with [String] segs drop_str )
    : String out ( string_with_cap n )
    : ~ i di 0
    ~ < di drive_end {
        ( string_push_char out ( nurl_str_at p n di ) )
        = di + di 1
    }
    ? absolute { ( string_push_char out 47 ) } {}
    : i sk ( vec_len [String] stk )
    ? == sk 0 {
        ? == ( string_len out ) 0 {
            ( string_push_char out 46 )
        } {}
        ( vec_free_with [String] stk drop_str )
        ^ out
    } {}
    : ~ i j 0
    ~ < j sk {
        ? > j 0 { ( string_push_char out 47 ) } {}
        : ?String s_opt ( vec_get [String] stk j )
        ?? s_opt {
            T s → {
                : i sl ( string_len s )
                : ~ i bi 0
                ~ < bi sl {
                    ( string_push_char out ( string_get s bi ) )
                    = bi + bi 1
                }
            }
            F → {}
        }
        = j + j 1
    }
    ( vec_free_with [String] stk drop_str )
    ^ out
}

// ── Typed Path ──────────────────────────────────────────────────────
//
// Path wraps an owned String. The typed functions below never mutate or
// consume their Path arguments — each produces a fresh Path — so a
// caller frees every Path it holds (path_free, or auto-drop at scope
// exit). path_str hands back a borrow of the inner buffer for interop
// with the `s`-based layer and with fs.nu.

: Path { String inner }

@ path_new s p → Path {
    : String s ( string_from p )
    ^ @ Path { s }
}

@ path_str Path p → s {
    ^ ( string_data . p inner )
}

@ path_len Path p → i {
    ^ ( string_len . p inner )
}

@ path_is_empty Path p → b {
    ^ == 0 ( string_len . p inner )
}

@ path_clone Path p → Path {
    : String c ( string_clone . p inner )
    ^ @ Path { c }
}

@ path_free Path p → v {
    ( string_free . p inner )
}

@ path_eq Path a Path b → b {
    ^ ( string_eq . a inner . b inner )
}

// base joined with one more component (path_join semantics: a trailing
// separator on the base and a leading one on the child are coalesced).
@ path_push Path base s child → Path {
    : String j ( path_join ( path_str base ) child )
    ^ @ Path { j }
}

@ path_parent Path p → Path {
    : String d ( path_dirname ( path_str p ) )
    ^ @ Path { d }
}

@ path_name Path p → Path {
    : String b ( path_basename ( path_str p ) )
    ^ @ Path { b }
}

@ path_is_abs Path p → b {
    ^ ( path_is_absolute ( path_str p ) )
}

// realpath(3): canonical, absolute, all symlinks resolved. The one
// filesystem-touching function here — None when the path does not
// exist or is not accessible.
//
// Pure libc FFI: passing NULL as the second argument tells `realpath`
// to malloc the result buffer itself (POSIX.1-2008 behaviour, also
// honoured by mingw-w64's `realpath` since v8.0). Win32 callers route
// through libmingwex's `realpath` wrapper, which delegates to
// `_fullpath` plus an `access(2)` existence probe — slightly stricter
// than the previous bare `_fullpath` path (returns NULL for missing
// paths, matching POSIX), which matches what `path_canonical` callers
// want.
& `c` @ realpath s path s resolved → s

@ path_canonical Path p → ?Path {
    : s raw ( realpath ( path_str p ) # s 0 )
    ? == 0 # i raw { ^ @ ?Path { F # Path 0 } } {}
    : String s ( string_from raw )
    ( nurl_free raw )
    : Path rp @ Path { s }
    ^ @ ?Path { T rp }
}

// Lexical relative path from `base` to `target`: the result, appended
// to `base` and normalized, names the same location as `target`. Both
// paths are normalized first, then split into segments; the answer is
// one ".." per base segment past the common prefix, followed by the
// target's remaining segments. Purely lexical — no filesystem access,
// no symlink awareness. None when the two are not comparable: one
// absolute and one relative, or rooted on different Windows drives.
@ path_relative_to Path base Path target → ?Path {
    : ( @ v String ) drop_str \ String s → v { ( string_free s ) }
    : s bs ( path_str base )
    : s ts ( path_str target )
    ? != ( path_is_absolute bs ) ( path_is_absolute ts ) {
        ^ @ ?Path { F # Path 0 }
    } {}
    ? != ( __has_drive bs ) ( __has_drive ts ) {
        ^ @ ?Path { F # Path 0 }
    } {}
    ? ( __has_drive bs ) {
        ? != ( nurl_str_get bs 0 ) ( nurl_str_get ts 0 ) {
            ^ @ ?Path { F # Path 0 }
        } {}
    } {}
    : String bn ( path_normalize bs )
    : String tn ( path_normalize ts )
    : ( Vec String ) bsegs ( __collect_segments ( string_data bn ) 0 )
    : ( Vec String ) tsegs ( __collect_segments ( string_data tn ) 0 )
    ( string_free bn )
    ( string_free tn )
    : i bc ( vec_len [String] bsegs )
    : i tc ( vec_len [String] tsegs )
    // Length of the common leading run of equal segments.
    : ~ i common 0
    : ~ b matching T
    ~ & < common bc & < common tc matching {
        : ~ b same F
        ?? ( vec_get [String] bsegs common ) {
            T bseg → {
                ?? ( vec_get [String] tsegs common ) {
                    T tseg → { ? ( string_eq bseg tseg ) { = same T } {} }
                    F → {}
                }
            }
            F → {}
        }
        ? same { = common + common 1 } { = matching F }
    }
    : String out ( string_new )
    // base → common ancestor: one ".." per base segment past the prefix.
    : i ups - bc common
    : ~ i u 0
    ~ < u ups {
        ? > ( string_len out ) 0 { ( string_push_char out 47 ) } {}
        ( string_push_char out 46 )
        ( string_push_char out 46 )
        = u + u 1
    }
    // common ancestor → target: the target's remaining segments.
    : ~ i d common
    ~ < d tc {
        ?? ( vec_get [String] tsegs d ) {
            T seg → {
                ? > ( string_len out ) 0 { ( string_push_char out 47 ) } {}
                ( string_push_str out ( string_data seg ) )
            }
            F → {}
        }
        = d + d 1
    }
    // Same location → empty result → ".".
    ? == 0 ( string_len out ) { ( string_push_char out 46 ) } {}
    ( vec_free_with [String] bsegs drop_str )
    ( vec_free_with [String] tsegs drop_str )
    : Path rp @ Path { out }
    ^ @ ?Path { T rp }
}
