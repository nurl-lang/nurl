// nurlbox/binio.nu — the byte-level tools.
//
// od / hexdump / xxd / cmp / dd / split / strings.
//
// These are the applets people reach for when something is not text
// after all, so every one of them is byte-exact: no line-ending
// rewriting, no NUL truncation, and no assumption that the input fits
// in memory unless the tool's own definition requires it.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/path.nu`
$ `bx.nu`

: s BX_HEX_LOWER `0123456789abcdef`
: s BX_HEX_UPPER `0123456789ABCDEF`

@ bx_push_hex String out i value i digits b upper → v {
    : ~ i sh * - digits 1 4
    ~ >= sh 0 {
        ( string_push_char out ( nurl_str_get ? upper BX_HEX_UPPER BX_HEX_LOWER & 15 >> value sh ) )
        = sh - sh 4
    }
}

@ bx_push_octal String out i value i digits → v {
    : ~ i sh * - digits 1 3
    ~ >= sh 0 {
        ( string_push_char out + 48 & 7 >> value sh )
        = sh - sh 3
    }
}

@ bx_push_right String out s text i width → v {
    : ~ i k - width ( nurl_str_len text )
    ~ > k 0 { ( string_push_char out 32 ) = k - k 1 }
    ( string_push_str out text )
}

// ── od ────────────────────────────────────────────────────────────

// Column width for `-t <kind><size>`, matching coreutils so two dumps
// of different files line up under each other.
@ __od_width i kind i size → i {
    ? == kind 120 { ^ * size 2 } {}
    ? == kind 111 { ^ ? == size 1 3 ? == size 2 6 ? == size 4 11 22 } {}
    ? == kind 117 { ^ ? == size 1 3 ? == size 2 5 ? == size 4 10 20 } {}
    ? == kind 100 { ^ ? == size 1 4 ? == size 2 6 ? == size 4 11 20 } {}
    ^ 3
}

// `size` bytes at `off`, little-endian, as an unsigned value.
@ __od_word * u p i n i off i size → i {
    : ~ i v 0
    : ~ i k - size 1
    ~ >= k 0 {
        : i b ? < + off k n & 255 # i . p + off k 0
        = v | << v 8 b
        = k - k 1
    }
    ^ v
}

// The signed reading of the same word, for `-t d`.
@ __od_signed i v i size → i {
    ? == size 8 { ^ v } {}
    : i bits * size 8
    : i sign << 1 - bits 1
    ? != 0 & v sign { ^ - v << 1 bits } {}
    ^ v
}

@ __od_char String out i c → v {
    ? == c 0 { ( bx_push_right out `\\0` 3 ) ^ } {}
    ? == c 7 { ( bx_push_right out `\\a` 3 ) ^ } {}
    ? == c 8 { ( bx_push_right out `\\b` 3 ) ^ } {}
    ? == c 9 { ( bx_push_right out `\\t` 3 ) ^ } {}
    ? == c 10 { ( bx_push_right out `\\n` 3 ) ^ } {}
    ? == c 11 { ( bx_push_right out `\\v` 3 ) ^ } {}
    ? == c 12 { ( bx_push_right out `\\f` 3 ) ^ } {}
    ? == c 13 { ( bx_push_right out `\\r` 3 ) ^ } {}
    ? & >= c 32 < c 127 {
        ( string_push_str out `  ` )
        ( string_push_char out c )
        ^
    } {}
    ( bx_push_octal out c 3 )
}

@ __od_addr String out i kind i off → v {
    ? == kind 110 { ^ } {}
    ? == kind 120 { ( bx_push_hex out off 6 F ) ^ } {}
    ? == kind 100 {
        : s d ( nurl_str_int off )
        : ~ i pad - 7 ( nurl_str_len d )
        ~ > pad 0 { ( string_push_char out 48 ) = pad - pad 1 }
        ( string_push_str out d )
        ^
    } {}
    ( bx_push_octal out off 7 )
}

@ __od_line String out * u p i n i off i take i kind i size i addr_kind → v {
    ( __od_addr out addr_kind off )
    : ~ i k 0
    ~ < k take {
        ( string_push_char out 32 )
        ? == kind 99 {
            ( __od_char out & 255 # i . p + off k )
            = k + k 1
        } {
            : i w ( __od_word p n + off k size )
            : i width ( __od_width kind size )
            ? == kind 120 {
                : ~ i pad - width * size 2
                ~ > pad 0 { ( string_push_char out 32 ) = pad - pad 1 }
                ( bx_push_hex out w * size 2 F )
            } {
                ? == kind 111 {
                    ( bx_push_octal out w width )
                } {
                    : i v ? == kind 100 ( __od_signed w size ) w
                    ( bx_push_right out ( nurl_str_int v ) width )
                }
            }
            = k + k size
        }
    }
    ( string_push_char out 10 )
}

@ ap_od ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `A:t:N:j:vbcdosxh` `address-radix=A,format=t,read-bytes=N,skip-bytes=j,output-duplicates=v` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : ~ i kind 111
        : ~ i size 2
        : ~ i addr_kind 111
        ? ( bx_has o `A` ) { = addr_kind ( nurl_str_get ( bx_val o `A` ) 0 ) } {}
        // The single-letter shorthands, in the order coreutils lists.
        ? ( bx_has o `b` ) { = kind 111 = size 1 } {}
        ? ( bx_has o `c` ) { = kind 99 = size 1 } {}
        ? ( bx_has o `d` ) { = kind 117 = size 2 } {}
        ? ( bx_has o `o` ) { = kind 111 = size 2 } {}
        ? ( bx_has o `x` ) { = kind 120 = size 2 } {}
        ? ( bx_has o `s` ) { = kind 100 = size 2 } {}
        ? ( bx_has o `h` ) { = kind 120 = size 2 } {}
        ? ( bx_has o `t` ) {
            : s spec ( bx_val o `t` )
            = kind ( nurl_str_get spec 0 )
            = size ? > ( nurl_str_len spec ) 1 ( nurl_str_to_int ( nurl_str_slice spec 1 - ( nurl_str_len spec ) 1 ) ) ? == kind 99 1 ? == kind 120 4 4
            ? <= size 0 { = size 1 } {}
            ? == kind 99 { = size 1 } {}
        } {}
        : i skip ? ( bx_has o `j` ) ( bx_count ( bx_val o `j` ) ) 0
        : i limit ? ( bx_has o `N` ) ( bx_count ( bx_val o `N` ) ) -1
        : b verbose ( bx_has o `v` )
        : s p ? > ( bx_operand_count o ) 0 ( bx_operand o 0 ) `-`
        : ~ b ok T
        : ( Vec u ) data ( bx_slurp p ok )
        ? ! ok { = rc 1 } {
            : i total ( vec_len [u] data )
            : *u pt ( vec_data [u] data )
            : i start ? > skip total total skip
            : i end ? >= limit 0 ? > + start limit total total + start limit total
            : String out ( string_new )
            : String prev ( string_new )
            : ~ b eliding F
            : ~ i off start
            ~ < off end {
                : i take ? < - end off 16 - end off 16
                : String line ( string_new )
                ( __od_line line pt total off take kind size addr_kind )
                // A run of identical lines collapses to `*`, unless -v.
                : b same & ! verbose & > off start ( __od_same line prev )
                ? same {
                    ? ! eliding {
                        ( string_push_str out `*\n` )
                        = eliding T
                    } {}
                } {
                    ( string_push_bytes out # *u ( string_data line ) ( string_len line ) )
                    = eliding F
                }
                ( string_clear prev )
                ( string_push_bytes prev # *u ( string_data line ) ( string_len line ) )
                ( string_free line )
                = off + off take
            }
            ? != addr_kind 110 {
                ( __od_addr out addr_kind end )
                ( string_push_char out 10 )
            } {}
            ( bx_write out )
            ( string_free out )
            ( string_free prev )
        }
        ( vec_free [u] data )
    }
    ( bx_opts_free o )
    ^ rc
}

// Two rendered lines are "the same" when their DATA columns match; the
// address differs by definition, so it is skipped.
@ __od_same String a String b → b {
    : i na ( string_len a )
    : i nb ( string_len b )
    ? != na nb { ^ F } {}
    : ~ i i 0
    ~ & < i na != ( string_get a i ) 32 { = i + i 1 }
    : ~ i k i
    ~ < k na {
        ? != ( string_get a k ) ( string_get b k ) { ^ F } {}
        = k + k 1
    }
    ^ T
}

// ── hexdump ───────────────────────────────────────────────────────

@ ap_hexdump ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `Cn:vs:x` `` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : b canonical ( bx_has o `C` )
        : i skip ? ( bx_has o `s` ) ( bx_count ( bx_val o `s` ) ) 0
        : i limit ? ( bx_has o `n` ) ( bx_count ( bx_val o `n` ) ) -1
        : b verbose ( bx_has o `v` )
        : s p ? > ( bx_operand_count o ) 0 ( bx_operand o 0 ) `-`
        : ~ b ok T
        : ( Vec u ) data ( bx_slurp p ok )
        ? ! ok { = rc 1 } {
            : i total ( vec_len [u] data )
            : *u pt ( vec_data [u] data )
            : i start ? > skip total total skip
            : i end ? >= limit 0 ? > + start limit total total + start limit total
            : String out ( string_new )
            : String prev ( string_new )
            : ~ b eliding F
            : ~ i off start
            ~ < off end {
                : i take ? < - end off 16 - end off 16
                : String line ( string_new )
                ( bx_push_hex line off ? canonical 8 7 F )
                ? canonical {
                    ( string_push_str line `  ` )
                    : ~ i k 0
                    ~ < k 16 {
                        ? == k 8 { ( string_push_char line 32 ) } {}
                        ? < k take {
                            ( bx_push_hex line & 255 # i . pt + off k 2 F )
                            ( string_push_char line 32 )
                        } { ( string_push_str line `   ` ) }
                        = k + k 1
                    }
                    // One more space than the byte columns leave: the
                    // ASCII gutter is two spaces from the last pair.
                    ( string_push_char line 32 )
                    ( string_push_char line 124 )
                    : ~ i q 0
                    ~ < q take {
                        : i c & 255 # i . pt + off q
                        ( string_push_char line ? & >= c 32 < c 127 c 46 )
                        = q + q 1
                    }
                    ( string_push_char line 124 )
                } {
                    // The historical default: 8 little-endian 16-bit
                    // words, padded out so a short last line still
                    // occupies the full width.
                    : ~ i k 0
                    ~ < k 16 {
                        ? < k take {
                            ( string_push_char line 32 )
                            : i lo & 255 # i . pt + off k
                            : i hi ? < + k 1 take & 255 # i . pt + off + k 1 0
                            ( bx_push_hex line | << hi 8 lo 4 F )
                        } { ( string_push_str line `     ` ) }
                        = k + k 2
                    }
                }
                ( string_push_char line 10 )
                : b same & ! verbose & > off start ( __od_same line prev )
                ? same {
                    ? ! eliding {
                        ( string_push_str out `*\n` )
                        = eliding T
                    } {}
                } {
                    ( string_push_bytes out # *u ( string_data line ) ( string_len line ) )
                    = eliding F
                }
                ( string_clear prev )
                ( string_push_bytes prev # *u ( string_data line ) ( string_len line ) )
                ( string_free line )
                = off + off take
            }
            ( bx_push_hex out end ? canonical 8 7 F )
            ( string_push_char out 10 )
            ( bx_write out )
            ( string_free out )
            ( string_free prev )
        }
        ( vec_free [u] data )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── xxd ───────────────────────────────────────────────────────────

@ __xxd_nibble i c → i {
    ? ( bx_is_hex c ) { ^ ( bx_hex_val c ) } {}
    ^ -1
}

@ ap_xxd ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `pruc:g:l:s:` `plain=p,revert=r,upper=u,cols=c,groupsize=g,len=l,seek=s` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : b plain ( bx_has o `p` )
        : b revert ( bx_has o `r` )
        : b upper ( bx_has o `u` )
        : i cols ? ( bx_has o `c` ) ( nurl_str_to_int ( bx_val o `c` ) ) ? plain 30 16
        : i group ? ( bx_has o `g` ) ( nurl_str_to_int ( bx_val o `g` ) ) 2
        : i skip ? ( bx_has o `s` ) ( bx_count ( bx_val o `s` ) ) 0
        : i limit ? ( bx_has o `l` ) ( bx_count ( bx_val o `l` ) ) -1
        : s p ? > ( bx_operand_count o ) 0 ( bx_operand o 0 ) `-`
        : ~ b ok T
        : ( Vec u ) data ( bx_slurp p ok )
        ? ! ok { = rc 1 } {
            ? revert {
                // Read hex back into bytes, ignoring an address prefix
                // and everything after a `  ` ASCII column.
                : String out ( string_new )
                : i n ( vec_len [u] data )
                : *u pt ( vec_data [u] data )
                : ~ i i 0
                : ~ i hi -1
                ~ < i n {
                    : i c & 255 # i . pt i
                    ? == c 10 { = hi -1 = i + i 1 } {
                        ? & == c 58 T {
                            // Drop everything up to and including the
                            // colon: that was the address.
                            ( string_clear out )
                            = i + i 1
                        } {
                            : i v ( __xxd_nibble c )
                            ? >= v 0 {
                                ? < hi 0 { = hi v } {
                                    ( string_push_char out | << hi 4 v )
                                    = hi -1
                                }
                            } {}
                            = i + i 1
                        }
                    }
                }
                ( bx_write out )
                ( string_free out )
            } {
                : i total ( vec_len [u] data )
                : *u pt ( vec_data [u] data )
                : i start ? > skip total total skip
                : i end ? >= limit 0 ? > + start limit total total + start limit total
                : String out ( string_new )
                : ~ i off start
                ~ < off end {
                    : i take ? < - end off cols - end off cols
                    ? plain {
                        : ~ i k 0
                        ~ < k take {
                            ( bx_push_hex out & 255 # i . pt + off k 2 upper )
                            = k + k 1
                        }
                        ( string_push_char out 10 )
                    } {
                        ( bx_push_hex out off 8 F )
                        ( string_push_str out `: ` )
                        : ~ i k 0
                        ~ < k cols {
                            ? < k take {
                                ( bx_push_hex out & 255 # i . pt + off k 2 upper )
                            } { ( string_push_str out `  ` ) }
                            ? == 0 - + k 1 * group / + k 1 group { ( string_push_char out 32 ) } {}
                            = k + k 1
                        }
                        ( string_push_char out 32 )
                        : ~ i q 0
                        ~ < q take {
                            : i c & 255 # i . pt + off q
                            ( string_push_char out ? & >= c 32 < c 127 c 46 )
                            = q + q 1
                        }
                        ( string_push_char out 10 )
                    }
                    = off + off take
                }
                ( bx_write out )
                ( string_free out )
            }
        }
        ( vec_free [u] data )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── cmp ───────────────────────────────────────────────────────────

// `cmp -l` right-ALIGNS its octal bytes rather than zero-padding them:
// ` 40` and `012` are the same byte, and the first is what every cmp
// has printed.
@ __cmp_octal String out i v → v {
    : String tmp ( string_new )
    : ~ i x v
    ? == x 0 { ( string_push_char tmp 48 ) } {}
    ~ != x 0 {
        ( string_push_char tmp + 48 & 7 x )
        = x >> x 3
    }
    : ~ i pad - 3 ( string_len tmp )
    ~ > pad 0 { ( string_push_char out 32 ) = pad - pad 1 }
    : ~ i k ( string_len tmp )
    ~ > k 0 {
        ( string_push_char out ( string_get tmp - k 1 ) )
        = k - k 1
    }
    ( string_free tmp )
}

@ ap_cmp ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `sln:` `silent=s,verbose=l,bytes=n` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 2 } {
        : i nops ( bx_operand_count o )
        ? == nops 0 {
            ( bx_err `missing operand` )
            = rc 2
        } {
            : s p1 ( bx_operand o 0 )
            : s p2 ? > nops 1 ( bx_operand o 1 ) `-`
            : b quiet ( bx_has o `s` )
            : b listall ( bx_has o `l` )
            : ~ b ok1 T
            : ~ b ok2 T
            : ( Vec u ) a ( bx_slurp p1 ok1 )
            : ( Vec u ) b ( bx_slurp p2 ok2 )
            ? & ok1 ok2 {
                : i na ( vec_len [u] a )
                : i nb ( vec_len [u] b )
                : *u pa ( vec_data [u] a )
                : *u pb ( vec_data [u] b )
                : i lim ? < na nb na nb
                : i cap ? ( bx_has o `n` ) ( bx_count ( bx_val o `n` ) ) -1
                : i scan ? & >= cap 0 < cap lim cap lim
                : ~ i line 1
                : ~ b differ F
                : String out ( string_new )
                : ~ i i 0
                ~ < i scan {
                    : i ca & 255 # i . pa i
                    : i cb & 255 # i . pb i
                    ? != ca cb {
                        = differ T
                        ? listall {
                            ( string_push_int out + i 1 )
                            ( string_push_char out 32 )
                            ( __cmp_octal out ca )
                            ( string_push_char out 32 )
                            ( __cmp_octal out cb )
                            ( string_push_char out 10 )
                        } {
                            ? ! quiet {
                                ( nurl_print p1 )
                                ( nurl_print ` ` )
                                ( nurl_print p2 )
                                ( nurl_print ` differ: char ` )
                                ( nurl_print ( nurl_str_int + i 1 ) )
                                ( nurl_print `, line ` )
                                ( nurl_print ( nurl_str_int line ) )
                                ( nurl_print `\n` )
                            } {}
                            = i scan
                        }
                    } {}
                    ? == ca 10 { = line + line 1 } {}
                    = i + i 1
                }
                ( bx_write out )
                ( string_free out )
                ? & ! differ & != na nb < cap 0 {
                    = differ T
                    ? ! quiet {
                        ( nurl_eprint ( bx_name ) )
                        ( nurl_eprint `: EOF on ` )
                        ( nurl_eprint ? < na nb p1 p2 )
                        ( nurl_eprint `\n` )
                    } {}
                } {}
                = rc ? differ 1 0
            } { = rc 2 }
            ( vec_free [u] a )
            ( vec_free [u] b )
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── strings ───────────────────────────────────────────────────────

@ ap_strings ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `n:at:f` `bytes=n,all=a,radix=t,print-file-name=f` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i minlen ? ( bx_has o `n` ) ( nurl_str_to_int ( bx_val o `n` ) ) 4
        : i nops ( bx_operand_count o )
        : ~ i i 0
        ~ < i ? > nops 0 nops 1 {
            : s p ? > nops 0 ( bx_operand o i ) `-`
            : ~ b ok T
            : ( Vec u ) data ( bx_slurp p ok )
            ? ok {
                : i n ( vec_len [u] data )
                : *u pt ( vec_data [u] data )
                : String out ( string_new )
                : String run ( string_new )
                : ~ i start 0
                : ~ i k 0
                ~ <= k n {
                    : i c ? < k n & 255 # i . pt k 0
                    // A tab belongs to the run: `strings` on a config
                    // file that lost its extension should still show the
                    // indented lines whole.
                    : b printable & < k n | == c 9 & >= c 32 < c 127
                    ? printable {
                        ? == ( string_len run ) 0 { = start k } {}
                        ( string_push_char run c )
                    } {
                        ? >= ( string_len run ) minlen {
                            ? ( bx_has o `f` ) {
                                ( string_push_str out p )
                                ( string_push_str out `: ` )
                            } {}
                            ? ( bx_has o `t` ) {
                                : i radix ( nurl_str_get ( bx_val o `t` ) 0 )
                                ? == radix 120 { ( bx_push_hex out start 7 F ) } {
                                    ? == radix 100 { ( bx_push_right out ( nurl_str_int start ) 7 ) } {
                                        ( bx_push_octal out start 7 )
                                    }
                                }
                                ( string_push_char out 32 )
                            } {}
                            ( string_push_bytes out # *u ( string_data run ) ( string_len run ) )
                            ( string_push_char out 10 )
                        } {}
                        ( string_clear run )
                    }
                    = k + k 1
                }
                ( bx_write out )
                ( string_free out )
                ( string_free run )
            } { = rc 1 }
            ( vec_free [u] data )
            = i + i 1
        }
    }
    ( bx_opts_free o )
    ^ rc
}

// ── split ─────────────────────────────────────────────────────────

// `aa`, `ab`, … `zz` for suffix length 2; `00`, `01`, … with -d.
@ __split_suffix String out i index i width b numeric → v {
    : i base ? numeric 10 26
    : ~ i v index
    : String tmp ( string_new )
    : ~ i k 0
    ~ < k width {
        ( string_push_char tmp + ? numeric 48 97 - v * base / v base )
        = v / v base
        = k + k 1
    }
    : ~ i q width
    ~ > q 0 {
        ( string_push_char out ( string_get tmp - q 1 ) )
        = q - q 1
    }
    ( string_free tmp )
}

@ __split_write s prefix i index i width b numeric ( Vec u ) data i from i len → i {
    : String name ( string_from prefix )
    ( __split_suffix name index width numeric )
    : ( Vec u ) piece ( vec_new [u] )
    : *u p ( vec_data [u] data )
    : ~ i k 0
    ~ < k len {
        ( vec_push [u] piece # u & 255 # i . p + from k )
        = k + k 1
    }
    : ~ i rc 0
    ?? ( write_file_bytes ( string_data name ) piece ) {
        T _ → {}
        F e → {
            ( bx_err_at ( string_data name ) ( bx_ioerr e ) )
            = rc 1
        }
    }
    ( vec_free [u] piece )
    ( string_free name )
    ^ rc
}

@ ap_split ( Vec String ) argv → i {
    : BxOpts o ( bx_getopt argv 1 `b:l:a:d` `bytes=b,lines=l,suffix-length=a,numeric-suffixes=d` )
    : ~ i rc 0
    ? ! ( bx_ok o ) { = rc 1 } {
        : i width ? ( bx_has o `a` ) ( nurl_str_to_int ( bx_val o `a` ) ) 2
        : b numeric ( bx_has o `d` )
        : s input ? > ( bx_operand_count o ) 0 ( bx_operand o 0 ) `-`
        : s prefix ? > ( bx_operand_count o ) 1 ( bx_operand o 1 ) `x`
        : ~ b ok T
        : ( Vec u ) data ( bx_slurp input ok )
        ? ! ok { = rc 1 } {
            : i n ( vec_len [u] data )
            : *u p ( vec_data [u] data )
            : ~ i index 0
            ? ( bx_has o `b` ) {
                : i chunk ( bx_count ( bx_val o `b` ) )
                ? <= chunk 0 {
                    ( bx_err_at ( bx_val o `b` ) `invalid number of bytes` )
                    = rc 1
                } {
                    : ~ i off 0
                    ~ < off n {
                        : i take ? < - n off chunk - n off chunk
                        : i one ( __split_write prefix index width numeric data off take )
                        ? != one 0 { = rc 1 = off n } { = off + off take }
                        = index + index 1
                    }
                }
            } {
                : i per ? ( bx_has o `l` ) ( nurl_str_to_int ( bx_val o `l` ) ) 1000
                ? <= per 0 {
                    ( bx_err `invalid number of lines` )
                    = rc 1
                } {
                    : ~ i from 0
                    : ~ i lines 0
                    : ~ i k 0
                    ~ < k n {
                        ? == 10 & 255 # i . p k {
                            = lines + lines 1
                            ? >= lines per {
                                : i one ( __split_write prefix index width numeric data from - + k 1 from )
                                ? != one 0 { = rc 1 = k n } {}
                                = index + index 1
                                = from + k 1
                                = lines 0
                            } {}
                        } {}
                        = k + k 1
                    }
                    ? & < from n == rc 0 {
                        : i one ( __split_write prefix index width numeric data from - n from )
                        ? != one 0 { = rc 1 } {}
                    } {}
                }
            }
        }
        ( vec_free [u] data )
    }
    ( bx_opts_free o )
    ^ rc
}

// ── dd ────────────────────────────────────────────────────────────

// `key=value` operands, the only applet that spells its options that
// way. Fills a caller-owned String rather than returning a raw slice:
// one of the two exits would otherwise hand back a literal and the
// other a fresh allocation, and no caller could tell which to free.
@ __dd_arg ( Vec String ) argv s key String out → v {
    ( string_clear out )
    : i n ( vec_len [String] argv )
    : i kl ( nurl_str_len key )
    : ~ i i 1
    ~ < i n {
        : s a ( bx_at argv i )
        ? & != 0 ( nurl_str_starts a key ) == 61 ( nurl_str_get a kl ) {
            ( string_push_str out ( nurl_str_slice a + kl 1 - ( nurl_str_len a ) + kl 1 ) )
            = i n
        } { = i + i 1 }
    }
}

@ ap_dd ( Vec String ) argv → i {
    : String inf_s ( string_new )
    : String outf_s ( string_new )
    : String bs_str ( string_new )
    : String count_str ( string_new )
    : String skip_str ( string_new )
    : String seek_str ( string_new )
    : String status_s ( string_new )
    : String conv_s ( string_new )
    ( __dd_arg argv `if` inf_s )
    ( __dd_arg argv `of` outf_s )
    ( __dd_arg argv `bs` bs_str )
    ( __dd_arg argv `count` count_str )
    ( __dd_arg argv `skip` skip_str )
    ( __dd_arg argv `seek` seek_str )
    ( __dd_arg argv `status` status_s )
    ( __dd_arg argv `conv` conv_s )
    : s inf ( string_data inf_s )
    : s outf ( string_data outf_s )
    : s bs_s ( string_data bs_str )
    : s count_s ( string_data count_str )
    : s skip_s ( string_data skip_str )
    : s seek_s ( string_data seek_str )
    : s status ( string_data status_s )
    : s conv ( string_data conv_s )
    : i bs ? > ( nurl_str_len bs_s ) 0 ( bx_count bs_s ) 512
    : i count ? > ( nurl_str_len count_s ) 0 ( bx_count count_s ) -1
    : i skip ? > ( nurl_str_len skip_s ) 0 ( bx_count skip_s ) 0
    : i seek ? > ( nurl_str_len seek_s ) 0 ( bx_count seek_s ) 0
    ? <= bs 0 {
        ( bx_err `invalid block size` )
        ( __dd_free inf_s outf_s bs_str count_str skip_str seek_str status_s conv_s )
        ^ 1
    } {}
    : ~ b ok T
    : ( Vec u ) data ( bx_slurp ? > ( nurl_str_len inf ) 0 inf `-` ok )
    ? ! ok {
        ( vec_free [u] data )
        ( __dd_free inf_s outf_s bs_str count_str skip_str seek_str status_s conv_s )
        ^ 1
    } {}
    : i n ( vec_len [u] data )
    : *u p ( vec_data [u] data )
    : i from ? > * skip bs n n * skip bs
    : i avail - n from
    : i want ? >= count 0 * count bs avail
    : i take ? < want avail want avail
    // Whole blocks in, a partial one counted separately — that is what
    // the `N+M records` line means and the only reason dd reports it.
    : i full / take bs
    : i partial ? > - take * full bs 0 1 0
    : ( Vec u ) outbuf ( vec_new [u] )
    : ~ i k 0
    ~ < k take {
        ( vec_push [u] outbuf # u & 255 # i . p + from k )
        = k + k 1
    }
    : ~ i rc 0
    ? > ( nurl_str_len outf ) 0 {
        : b notrunc >= ( nurl_str_find conv `notrunc` ) 0
        : ( Vec u ) final ( vec_new [u] )
        ? > seek 0 {
            // seek= writes at an offset: keep what was there when
            // conv=notrunc says so, otherwise pad with NULs.
            ? notrunc {
                : ~ b ok2 T
                : ( Vec u ) old ( bx_slurp outf ok2 )
                : i on ( vec_len [u] old )
                : *u op ( vec_data [u] old )
                : ~ i q 0
                ~ < q * seek bs {
                    ( vec_push [u] final # u ? < q on & 255 # i . op q 0 )
                    = q + q 1
                }
                ( vec_free [u] old )
            } {
                : ~ i q 0
                ~ < q * seek bs { ( vec_push [u] final # u 0 ) = q + q 1 }
            }
        } {}
        ( vec_extend [u] final outbuf )
        ?? ( write_file_bytes outf final ) {
            T _ → {}
            F e → {
                ( bx_err_at outf ( bx_ioerr e ) )
                = rc 1
            }
        }
        ( vec_free [u] final )
    } { ( bx_write_bytes outbuf ) }
    ? ! ( bx_streq status `none` ) {
        ( flush )
        ( nurl_eprint ( nurl_str_int full ) )
        ( nurl_eprint `+` )
        ( nurl_eprint ( nurl_str_int partial ) )
        ( nurl_eprint ` records in\n` )
        ( nurl_eprint ( nurl_str_int full ) )
        ( nurl_eprint `+` )
        ( nurl_eprint ( nurl_str_int partial ) )
        ( nurl_eprint ` records out\n` )
    } {}
    ( vec_free [u] outbuf )
    ( vec_free [u] data )
    ( __dd_free inf_s outf_s bs_str count_str skip_str seek_str status_s conv_s )
    ^ rc
}

@ __dd_free String a String b String c String d String e String f String g String h → v {
    ( string_free a )
    ( string_free b )
    ( string_free c )
    ( string_free d )
    ( string_free e )
    ( string_free f )
    ( string_free g )
    ( string_free h )
}
