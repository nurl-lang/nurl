// packages/zst/src/inspect.nu — what is actually inside a .zst file.
//
// A Zstandard frame is a header, a run of blocks, and an optional
// checksum; each compressed block is a literals section and a sequences
// section, and each of those chose an encoding the encoder thought
// cheapest. All of that is recoverable WITHOUT entropy-decoding
// anything — the choices are announced in bytes and bitfields at the
// front of each section — which is what this file reads out.
//
// It is the view you want when a file compresses worse than you
// expected and you need to know why: whether the literals went Huffman
// or raw, whether the tree was sent or repeated, whether the sequence
// tables were the predefined ones, how many sequences each block
// carries. The reference CLI's `--list` stops at the frame.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/zstd.nu`

: i ZI_MAGIC 0xFD2FB528
: i ZI_SKIP_LO 0x184D2A50
: i ZI_SKIP_HI 0x184D2A5F

@ __zi_u32 * u p i off → i {
    ^ | | | # i . p off
    << # i . p + off 1 8
    << # i . p + off 2 16
    << # i . p + off 3 24
}

// Human sizes: a block report is unreadable in raw bytes.
@ __zi_size String out i n → v {
    ? < n 1024 {
        ( string_push_int out n )
        ( string_push_str out ` B` )
        ^ v
    } {}
    ? < n 1048576 {
        ( string_push_int out / n 1024 )
        ( string_push_char out 46 )
        ( string_push_int out % / * n 10 1024 10 )
        ( string_push_str out ` KiB` )
        ^ v
    } {}
    ( string_push_int out / n 1048576 )
    ( string_push_char out 46 )
    ( string_push_int out % / * n 10 1048576 10 )
    ( string_push_str out ` MiB` )
}

// Pad to `width`, but never to zero spaces: a column that overflows its
// budget must still be separated from the next one, or two numbers run
// together into a third that means nothing.
@ __zi_pad String out i width i used → v {
    : ~ i k used
    ~ < k width { ( string_push_char out 32 ) = k + k 1 }
    ? >= used width { ( string_push_char out 32 ) } {}
}

@ __zi_col String out s text i width → v {
    ( string_push_str out text )
    ( __zi_pad out width ( nurl_str_len text ) )
}

@ __zi_num_col String out i n i width → v {
    : String tmp ( string_with_cap 24 )
    ( string_push_int tmp n )
    ( string_push_str out ( string_data tmp ) )
    ( __zi_pad out width ( string_len tmp ) )
    ( string_free tmp )
}

// The literals section header: type, size format, and the two sizes.
// Returns the number of header bytes, and reports through `slot`:
//   slot 0 = block type, 1 = regenerated size, 2 = compressed size,
//   slot 3 = stream count (0 for raw/RLE).
@ __zi_literals * u p i off i avail ( Vec i ) slot → i {
    ? <= avail 0 { ^ -1 } {}
    : *i sp ( vec_data [i] slot )
    : i b0 # i . p off
    : i btype & b0 3
    : i sfmt & >> b0 2 3
    = . sp 0 btype
    = . sp 3 0
    ? <= btype 1 {
        ? == sfmt 1 {
            ? < avail 2 { ^ -1 } {}
            = . sp 1 >> | b0 << # i . p + off 1 8 4
            = . sp 2 ? == btype 0 . sp 1 1
            ^ 2
        } {}
        ? == sfmt 3 {
            ? < avail 3 { ^ -1 } {}
            : i v | | b0 << # i . p + off 1 8 << # i . p + off 2 16
            = . sp 1 & >> v 4 0xFFFFF
            = . sp 2 ? == btype 0 . sp 1 1
            ^ 3
        } {}
        = . sp 1 >> b0 3
        = . sp 2 ? == btype 0 . sp 1 1
        ^ 1
    } {}
    ? == sfmt 0 {
        ? < avail 3 { ^ -1 } {}
        : i v | | b0 << # i . p + off 1 8 << # i . p + off 2 16
        = . sp 1 & >> v 4 1023
        = . sp 2 & >> v 14 1023
        = . sp 3 1
        ^ 3
    } {}
    ? == sfmt 1 {
        ? < avail 3 { ^ -1 } {}
        : i v | | b0 << # i . p + off 1 8 << # i . p + off 2 16
        = . sp 1 & >> v 4 1023
        = . sp 2 & >> v 14 1023
        = . sp 3 4
        ^ 3
    } {}
    ? == sfmt 2 {
        ? < avail 4 { ^ -1 } {}
        : i v | | | b0 << # i . p + off 1 8 << # i . p + off 2 16
        << # i . p + off 3 24
        = . sp 1 & >> v 4 16383
        = . sp 2 & >> v 18 16383
        = . sp 3 4
        ^ 4
    } {}
    ? < avail 5 { ^ -1 } {}
    : i v | | | b0 << # i . p + off 1 8 << # i . p + off 2 16
    << # i . p + off 3 24
    : i hi # i . p + off 4
    = . sp 1 & >> v 4 0x3FFFF
    = . sp 2 & | >> v 22 << hi 10 0x3FFFF
    = . sp 3 4
    ^ 5
}

@ __zi_lit_name i btype i streams → s {
    ? == btype 0 { ^ `raw` } {}
    ? == btype 1 { ^ `rle` } {}
    ? == btype 2 { ^ ? == streams 1 `huffman/1` `huffman/4` } {}
    ^ ? == streams 1 `treeless/1` `treeless/4`
}

@ __zi_mode_name i m → s {
    ? == m 0 { ^ `predef` } {}
    ? == m 1 { ^ `rle` } {}
    ? == m 2 { ^ `fse` } {}
    ^ `repeat`
}

// One frame, from `at`. Returns the offset just past it, or -1.
@ __zi_frame ( Vec u ) src i at String out i idx → i {
    : *u p ( vec_data [u] src )
    : i n ( vec_len [u] src )
    : i magic ( __zi_u32 p at )
    ? & >= magic ZI_SKIP_LO <= magic ZI_SKIP_HI {
        : i sz ( __zi_u32 p + at 4 )
        ( string_push_str out `frame ` )
        ( string_push_int out idx )
        ( string_push_str out `  SKIPPABLE  payload ` )
        ( __zi_size out sz )
        ( string_push_str out `  (magic ` )
        ( string_push_int out - magic ZI_SKIP_LO )
        ( string_push_str out `)\n\n` )
        ^ + + at 8 sz
    } {}
    ? != magic ZI_MAGIC { ^ -1 } {}
    : ~ i off + at 4
    ? >= off n { ^ -1 } {}
    : i desc # i . p off
    = off + off 1
    : i fcs_flag >> desc 6
    : i single & >> desc 5 1
    : i checksum & >> desc 2 1
    : i did_flag & desc 3
    : ~ i window 0
    ? == single 0 {
        : i wd # i . p off
        = off + off 1
        : i base << 1 + 10 >> wd 3
        = window + base * >> base 3 & wd 7
    } {}
    : ~ i dictid 0
    ? != did_flag 0 {
        : i nb ? == did_flag 1 1 ? == did_flag 2 2 4
        : ~ i k 0
        ~ < k nb { = dictid | dictid << # i . p + off k * k 8 = k + k 1 }
        = off + off nb
    } {}
    : ~ i fcs -1
    ? | != single 0 != fcs_flag 0 {
        : i nb ? == fcs_flag 0 1 ? == fcs_flag 1 2 ? == fcs_flag 2 4 8
        = fcs 0
        : ~ i k 0
        ~ < k nb { = fcs | fcs << # i . p + off k * k 8 = k + k 1 }
        ? == nb 2 { = fcs + fcs 256 } {}
        = off + off nb
    } {}
    ? != single 0 { = window fcs } {}

    ( string_push_str out `frame ` )
    ( string_push_int out idx )
    ( string_push_str out `  window ` )
    ( __zi_size out window )
    ( string_push_str out `  content ` )
    ? >= fcs 0 { ( __zi_size out fcs ) } { ( string_push_str out `unknown` ) }
    ( string_push_str out `  checksum ` )
    ( string_push_str out ? != checksum 0 `yes` `no` )
    ? != dictid 0 {
        ( string_push_str out `  dict ` )
        ( string_push_int out dictid )
    } {}
    ( string_push_char out 10 )
    ( string_push_str out `  block  type         size       literals                   seqs   tables (ll/of/ml)\n` )

    : ( Vec i ) slot ( vec_new [i] )
    ( vec_push [i] slot 0 ) ( vec_push [i] slot 0 )
    ( vec_push [i] slot 0 ) ( vec_push [i] slot 0 )
    : *i sp ( vec_data [i] slot )
    : ~ i bno 0
    : ~ b last F
    : ~ b bad F
    ~ & ! last ! bad {
        ? > + off 3 n { = bad T } {
            : i hdr | | # i . p off << # i . p + off 1 8 << # i . p + off 2 16
            = off + off 3
            = last != & hdr 1 0
            : i btype & >> hdr 1 3
            : i blen >> hdr 3
            = bno + bno 1
            ( string_push_str out `  ` )
            ( __zi_num_col out bno 7 )
            ( __zi_col out ? == btype 0 `raw` ? == btype 1 `rle` ? == btype 2 `compressed` `RESERVED` 12 )
            : String sz ( string_with_cap 16 )
            ( __zi_size sz blen )
            ( __zi_col out ( string_data sz ) 10 )
            ( string_free sz )
            ? == btype 2 {
                : i used ( __zi_literals p off blen slot )
                ? < used 0 { = bad T } {
                    : String lit ( string_with_cap 32 )
                    ( string_push_str lit ( __zi_lit_name # i . sp 0 # i . sp 3 ) )
                    ( string_push_char lit 32 )
                    ( __zi_size lit # i . sp 1 )
                    ? >= # i . sp 0 2 {
                        ( string_push_str lit `→` )
                        ( __zi_size lit # i . sp 2 )
                    } {}
                    ( __zi_col out ( string_data lit ) 26 )
                    ( string_free lit )
                    // Sequences: the count, then the three table modes.
                    : i so + off ? >= # i . sp 0 2 + used # i . sp 2
                    + used ? == # i . sp 0 1 1 # i . sp 1
                    ? > + so 1 + off blen { = bad T } {
                        : i b0 # i . p so
                        : ~ i nseq 0
                        : ~ i after + so 1
                        ? < b0 128 { = nseq b0 } {
                            ? == b0 255 {
                                = nseq + | # i . p + so 1 << # i . p + so 2 8 0x7F00
                                = after + so 3
                            } {
                                = nseq + << - b0 128 8 # i . p + so 1
                                = after + so 2
                            }
                        }
                        ( __zi_num_col out nseq 6 )
                        ? > nseq 0 {
                            : i modes # i . p after
                            ( string_push_str out ( __zi_mode_name & >> modes 6 3 ) )
                            ( string_push_char out 47 )
                            ( string_push_str out ( __zi_mode_name & >> modes 4 3 ) )
                            ( string_push_char out 47 )
                            ( string_push_str out ( __zi_mode_name & >> modes 2 3 ) )
                        } { ( string_push_char out 45 ) }
                    }
                }
            } {
                ( __zi_col out `—` 26 )
                ( string_push_char out 45 )
            }
            ( string_push_char out 10 )
            = off + off ? == btype 1 1 blen
            ? > off n { = bad T } {}
        }
    }
    ? bad {
        ( string_push_str out `  (truncated or malformed past this point)\n` )
        ( vec_free [i] slot )
        ^ -1
    } {}
    ( vec_free [i] slot )
    ( string_push_str out `  ` )
    ( string_push_int out bno )
    ( string_push_str out ? == bno 1 ` block` ` blocks` )
    ? != checksum 0 {
        ? > + off 4 n {
            ( string_push_str out `, checksum MISSING` )
            ( string_push_char out 10 )
            ^ -1
        } {}
        ( string_push_str out `, checksum 0x` )
        : i ck ( __zi_u32 p off )
        : ~ i sh 28
        ~ >= sh 0 {
            : i nib & >> ck sh 15
            ( string_push_char out ? < nib 10 + 48 nib + 87 nib )
            = sh - sh 4
        }
        = off + off 4
    } {}
    ( string_push_str out `\n\n` )
    ^ off
}

// Print the anatomy of every frame in `src`. Returns 0, or 1 when the
// file stops making sense partway through.
@ zst_inspect ( Vec u ) src s name → i {
    : i n ( vec_len [u] src )
    : String out ( string_with_cap 4096 )
    ( string_push_str out name )
    ( string_push_str out ` — ` )
    ( __zi_size out n )
    ?? ( zstd_content_size src ) {
        T sz → {
            ( string_push_str out ` → ` )
            ( __zi_size out sz )
            ? > n 0 {
                : i x / * sz 100 n
                ( string_push_str out `  (` )
                ( string_push_int out / x 100 )
                ( string_push_char out 46 )
                : i frac % x 100
                ? < frac 10 { ( string_push_char out 48 ) } {}
                ( string_push_int out frac )
                ( string_push_str out `x)` )
            } {}
        }
        F → {}
    }
    ( string_push_str out `\n\n` )
    : ~ i at 0
    : ~ i idx 0
    : ~ i rc 0
    ~ & < at n == rc 0 {
        ? > + at 4 n { = rc 1 } {
            = idx + idx 1
            : i next ( __zi_frame src at out idx )
            ? < next 0 { = rc 1 } { = at next }
        }
    }
    ( nurl_print ( string_data out ) )
    ( string_free out )
    ? != rc 0 { ( nurl_eprint `zst: not a well-formed Zstandard file\n` ) } {}
    ^ rc
}
