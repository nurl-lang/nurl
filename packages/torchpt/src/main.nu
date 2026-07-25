// packages/torchpt/src/main.nu — the `torchpt` CLI.
//
//   torchpt info    <file.pt>            summary: tensors, dtypes, bytes
//   torchpt tensors <file.pt> [prefix]   one line per tensor
//   torchpt stats   <file.pt> <name>     min / max / mean of one tensor
//   torchpt head    <file.pt> <name> [n] first n values
//   torchpt dump    <file.pt>            every tensor, every value —
//                                        the oracle-diff format

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/floatbits.nu`
$ `packages/torchpt/src/torchpt.nu`

@ usage → i {
    ( nurl_print `torchpt — read PyTorch .pt/.pth checkpoints\n\n` )
    ( nurl_print `  torchpt info    <file.pt>\n` )
    ( nurl_print `  torchpt tensors <file.pt> [name-prefix]\n` )
    ( nurl_print `  torchpt stats   <file.pt> <tensor>\n` )
    ( nurl_print `  torchpt head    <file.pt> <tensor> [count]\n` )
    ( nurl_print `  torchpt dump    <file.pt>\n` )
    ^ 2
}

@ starts_with s hay s pre → b {
    : i hl ( nurl_str_len hay )
    : i pl ( nurl_str_len pre )
    ? > pl hl { ^ F } {}
    : ~ i j 0
    ~ < j pl {
        ? != ( nurl_str_get hay j ) ( nurl_str_get pre j ) { ^ F } {}
        = j + j 1
    }
    ^ T
}

@ cmd_info * Pt p → i {
    : i n ( pt_n_tensors p )
    ( nurl_print `tensors: ` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` )
    : ~ i total 0
    : ~ i params 0
    : ~ i nviews 0
    : ~ i j 0
    ~ < j n {
        = total + total ( pt_nbytes p j )
        = params + params ( pt_nelems p j )
        ? ! ( pt_is_contiguous p j ) { = nviews + nviews 1 } {}
        = j + j 1
    }
    ( nurl_print `parameters: ` ) ( nurl_print ( nurl_str_int params ) ) ( nurl_print `\n` )
    ( nurl_print `bytes: ` ) ( nurl_print ( nurl_str_int total ) ) ( nurl_print `\n` )
    ( nurl_print `non-contiguous views: ` ) ( nurl_print ( nurl_str_int nviews ) ) ( nurl_print `\n` )
    // dtype histogram
    : ~ i c 0
    ~ <= c PKS_BOOL {
        : ~ i cnt 0
        = j 0
        ~ < j n { ? == ( pt_dtype p j ) c { = cnt + cnt 1 } {} = j + j 1 }
        ? > cnt 0 {
            ( nurl_print `  ` ) ( nurl_print ( pk_storage_name c ) )
            ( nurl_print `: ` ) ( nurl_print ( nurl_str_int cnt ) ) ( nurl_print `\n` )
        } {}
        = c + c 1
    }
    ^ 0
}

@ cmd_tensors * Pt p s prefix → i {
    : i n ( pt_n_tensors p )
    : ~ i j 0
    ~ < j n {
        : s nm ( pt_name p j )
        ? | == 0 ( nurl_str_len prefix ) ( starts_with nm prefix ) {
            ( nurl_print nm )
            ( nurl_print `  ` ) ( nurl_print ( pk_storage_name ( pt_dtype p j ) ) )
            ( nurl_print `  ` )
            : String sh ( pt_shape_str p j )
            ( nurl_print ( string_data sh ) )
            ( string_free sh )
            ( nurl_print `  ` ) ( nurl_print ( nurl_str_int ( pt_nbytes p j ) ) )
            ( nurl_print ` bytes` )
            ? ! ( pt_is_contiguous p j ) { ( nurl_print `  [view]` ) } {}
            ( nurl_print `\n` )
        } {}
        = j + j 1
    }
    ^ 0
}

@ cmd_stats * Pt p s name → i {
    : i idx ( pt_find p name )
    ? < idx 0 { ( nurl_print `no such tensor\n` ) ^ 1 } {}
    : i n ( pt_nelems p idx )
    ? == n 0 { ( nurl_print `empty tensor\n` ) ^ 1 } {}
    : *f buf # *f ( nurl_zalloc * n 8 )
    ? ! ( pt_read_f64 p idx 0 n buf ) {
        ( nurl_free # s buf )
        ( nurl_print `cannot read tensor (non-contiguous or unsupported dtype)\n` )
        ^ 1
    } {}
    : ~ f lo . buf 0
    : ~ f hi . buf 0
    : ~ f sum 0.0
    : ~ i j 0
    ~ < j n {
        : f x . buf j
        ? < x lo { = lo x } {}
        ? > x hi { = hi x } {}
        = sum + sum x
        = j + j 1
    }
    ( nurl_print `count=` ) ( nurl_print ( nurl_str_int n ) )
    ( nurl_print ` min=` ) ( nurl_print ( nurl_str_float lo ) )
    ( nurl_print ` max=` ) ( nurl_print ( nurl_str_float hi ) )
    ( nurl_print ` mean=` ) ( nurl_print ( nurl_str_float / sum # f n ) )
    ( nurl_print `\n` )
    ( nurl_free # s buf )
    ^ 0
}

@ cmd_head * Pt p s name i count → i {
    : i idx ( pt_find p name )
    ? < idx 0 { ( nurl_print `no such tensor\n` ) ^ 1 } {}
    : i n ( pt_nelems p idx )
    : i want ? > count n n count
    ? <= want 0 { ( nurl_print `\n` ) ^ 0 } {}
    : *f buf # *f ( nurl_zalloc * want 8 )
    ? ! ( pt_read_f64 p idx 0 want buf ) {
        ( nurl_free # s buf )
        ( nurl_print `cannot read tensor\n` )
        ^ 1
    } {}
    : ~ i j 0
    ~ < j want {
        ? > j 0 { ( nurl_print ` ` ) } {}
        ( nurl_print ( nurl_str_float . buf j ) )
        = j + j 1
    }
    ( nurl_print `\n` )
    ( nurl_free # s buf )
    ^ 0
}

// "<name> <dtype> <shape> <v0> <v1> …" per tensor. Values print through
// nurl_str_float, which round-trips — so a diff against torch is a diff
// of numbers, not of formatting.
@ cmd_dump * Pt p → i {
    : i n ( pt_n_tensors p )
    : ~ i j 0
    ~ < j n {
        ( nurl_print ( pt_name p j ) )
        ( nurl_print ` ` ) ( nurl_print ( pk_storage_name ( pt_dtype p j ) ) )
        ( nurl_print ` ` )
        : String sh ( pt_shape_str p j )
        ( nurl_print ( string_data sh ) )
        ( string_free sh )
        : i cnt ( pt_nelems p j )
        ? > cnt 0 {
            : *f buf # *f ( nurl_zalloc * cnt 8 )
            ? ( pt_read_f64 p j 0 cnt buf ) {
                : ~ i e 0
                ~ < e cnt {
                    ( nurl_print ` ` ) ( nurl_print ( nurl_str_float . buf e ) )
                    = e + e 1
                }
            } { ( nurl_print ` READ-FAILED` ) }
            ( nurl_free # s buf )
        } {}
        ( nurl_print `\n` )
        = j + j 1
    }
    ^ 0
}

@ main → i {
    : i argc ( nurl_argc )
    ? < argc 3 { ^ ( usage ) } {}
    : s cmd ( nurl_argv 1 )
    : s path ( nurl_argv 2 )
    : !*Pt String o ( pt_open path )
    ?? o {
        F e → {
            ( nurl_print ( string_data e ) ) ( nurl_print `\n` )
            ( string_free e )
            ^ 1
        }
        T p → {
            : ~ i rc 0
            ? ( nurl_str_eq cmd `info` ) { = rc ( cmd_info p ) } {
                ? ( nurl_str_eq cmd `dump` ) { = rc ( cmd_dump p ) } {
                    ? ( nurl_str_eq cmd `tensors` ) {
                        = rc ( cmd_tensors p ? > argc 3 ( nurl_argv 3 ) `` )
                    } {
                        ? ( nurl_str_eq cmd `stats` ) {
                            ? < argc 4 { = rc ( usage ) } { = rc ( cmd_stats p ( nurl_argv 3 ) ) }
                        } {
                            ? ( nurl_str_eq cmd `head` ) {
                                ? < argc 4 { = rc ( usage ) }
                                { = rc ( cmd_head p ( nurl_argv 3 ) ? > argc 4 ( nurl_str_to_int ( nurl_argv 4 ) ) 8 ) }
                            } { = rc ( usage ) } } } } }
            ( pt_close p )
            ^ rc
        }
    }
}
