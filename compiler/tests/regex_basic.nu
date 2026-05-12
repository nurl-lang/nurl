// regex_basic.nu — coverage of stdlib/ext/regex.nu

$ `stdlib/ext/regex.nu`

@ print_match s prefix Regex r s text → v {
  ( nurl_print prefix )
  : ? Match m ( regex_find r text )
  ?? m {
    T x → {
      ( nurl_print ( nurl_str_int . x start ) )
      ( nurl_print `,` )
      ( nurl_print ( nurl_str_int . x len ) )
    }
    F → ( nurl_print `none` )
  }
  ( nurl_print `\n` )
}

@ main → i {
  // ── Literal match ────────────────────────────────────────────────
  : ! Regex ParseErr r1 ( regex_compile `hello` )
  ?? r1 {
    T rx → {
      ( nurl_print `test_hello=` )
      ( nurl_print ? ( regex_test rx `hello world` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `match_full=` )
      ( nurl_print ? ( regex_match rx `hello` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `match_partial=` )
      ( nurl_print ? ( regex_match rx `hello world` ) `T` `F` )
      ( nurl_print `\n` )
      ( print_match `find_hello=` rx `say hello there` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  // ── Quantifiers ──────────────────────────────────────────────────
  : ! Regex ParseErr r2 ( regex_compile `ab*c` )
  ?? r2 {
    T rx → {
      ( nurl_print `ab*c/ac=` )
      ( nurl_print ? ( regex_match rx `ac` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `ab*c/abc=` )
      ( nurl_print ? ( regex_match rx `abc` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `ab*c/abbbc=` )
      ( nurl_print ? ( regex_match rx `abbbc` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `ab*c/adc=` )
      ( nurl_print ? ( regex_match rx `adc` ) `T` `F` )
      ( nurl_print `\n` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  : ! Regex ParseErr r3 ( regex_compile `ab+c` )
  ?? r3 {
    T rx → {
      ( nurl_print `ab+c/ac=` )
      ( nurl_print ? ( regex_match rx `ac` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `ab+c/abc=` )
      ( nurl_print ? ( regex_match rx `abc` ) `T` `F` )
      ( nurl_print `\n` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  : ! Regex ParseErr r4 ( regex_compile `colou?r` )
  ?? r4 {
    T rx → {
      ( nurl_print `colou?r/color=` )
      ( nurl_print ? ( regex_match rx `color` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `colou?r/colour=` )
      ( nurl_print ? ( regex_match rx `colour` ) `T` `F` )
      ( nurl_print `\n` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  // ── Wildcard ─────────────────────────────────────────────────────
  : ! Regex ParseErr r5 ( regex_compile `a.c` )
  ?? r5 {
    T rx → {
      ( nurl_print `a.c/abc=` )
      ( nurl_print ? ( regex_match rx `abc` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `a.c/a_c=` )
      ( nurl_print ? ( regex_match rx `a c` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `a.c/ac=` )
      ( nurl_print ? ( regex_match rx `ac` ) `T` `F` )
      ( nurl_print `\n` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  // ── Alternation ──────────────────────────────────────────────────
  : ! Regex ParseErr r6 ( regex_compile `cat|dog` )
  ?? r6 {
    T rx → {
      ( nurl_print `cat|dog/cat=` )
      ( nurl_print ? ( regex_test rx `cat` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `cat|dog/dog=` )
      ( nurl_print ? ( regex_test rx `dog` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `cat|dog/bird=` )
      ( nurl_print ? ( regex_test rx `bird` ) `T` `F` )
      ( nurl_print `\n` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  // ── Character class ──────────────────────────────────────────────
  : ! Regex ParseErr r7 ( regex_compile `[aeiou]` )
  ?? r7 {
    T rx → {
      ( nurl_print `[aeiou]/a=` )
      ( nurl_print ? ( regex_test rx `a` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `[aeiou]/z=` )
      ( nurl_print ? ( regex_test rx `z` ) `T` `F` )
      ( nurl_print `\n` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  : ! Regex ParseErr r8 ( regex_compile `[a-z]+` )
  ?? r8 {
    T rx → {
      ( print_match `lower_word=` rx `Hello there` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  : ! Regex ParseErr r9 ( regex_compile `[^0-9]+` )
  ?? r9 {
    T rx → {
      ( print_match `non_digit=` rx `42 apples` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  // ── Built-in classes ─────────────────────────────────────────────
  : ! Regex ParseErr ra ( regex_compile `\d+` )
  ?? ra {
    T rx → {
      ( print_match `digits=` rx `abc 123 xyz` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  : ! Regex ParseErr rb ( regex_compile `\w+` )
  ?? rb {
    T rx → {
      ( print_match `word=` rx `  hello_42!` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  : ! Regex ParseErr rc ( regex_compile `\s+` )
  ?? rc {
    T rx → {
      ( print_match `ws=` rx `ab   cd` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  // ── Anchors ──────────────────────────────────────────────────────
  : ! Regex ParseErr rd ( regex_compile `^foo` )
  ?? rd {
    T rx → {
      ( nurl_print `^foo/foobar=` )
      ( nurl_print ? ( regex_test rx `foobar` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `^foo/barfoo=` )
      ( nurl_print ? ( regex_test rx `barfoo` ) `T` `F` )
      ( nurl_print `\n` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  : ! Regex ParseErr re ( regex_compile `bar$` )
  ?? re {
    T rx → {
      ( nurl_print `bar$/foobar=` )
      ( nurl_print ? ( regex_test rx `foobar` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `bar$/barfoo=` )
      ( nurl_print ? ( regex_test rx `barfoo` ) `T` `F` )
      ( nurl_print `\n` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  // ── Groups ───────────────────────────────────────────────────────
  : ! Regex ParseErr rf ( regex_compile `(ab)+` )
  ?? rf {
    T rx → {
      ( nurl_print `(ab)+/abab=` )
      ( nurl_print ? ( regex_match rx `abab` ) `T` `F` )
      ( nurl_print `\n` )
      ( nurl_print `(ab)+/aab=` )
      ( nurl_print ? ( regex_match rx `aab` ) `T` `F` )
      ( nurl_print `\n` )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  // ── find_all / replace / split ────────────────────────────────────
  : ! Regex ParseErr rg ( regex_compile `\d+` )
  ?? rg {
    T rx → {
      : ( Vec Match ) ms ( regex_find_all rx `12 and 34 and 5` )
      ( nurl_print `find_all_count=` )
      ( nurl_print ( nurl_str_int ( vec_len [Match] ms ) ) )
      ( nurl_print `\n` )
      ( vec_free [Match] ms )

      : String rep ( regex_replace rx `had 12 cats and 34 dogs` `N` )
      ( nurl_print `replaced=` )
      ( nurl_print ( string_data rep ) )
      ( nurl_print `\n` )
      ( string_free rep )

      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  : ! Regex ParseErr rh ( regex_compile `,` )
  ?? rh {
    T rx → {
      : ( Vec String ) parts ( regex_split rx `a,b,c,d` )
      ( nurl_print `split_count=` )
      ( nurl_print ( nurl_str_int ( vec_len [String] parts ) ) )
      ( nurl_print `\n` )
      : (@ v String) drop1 \ String s → v { ( string_free s ) }
      ( vec_free_with [String] parts drop1 )
      ( regex_free rx )
    }
    F _ → ( nurl_print `compile failed\n` )
  }

  // ── Errors ───────────────────────────────────────────────────────
  : ! Regex ParseErr ri ( regex_compile `` )
  ?? ri {
    T rx → { ( nurl_print `empty unexpectedly compiled\n` ) ( regex_free rx ) }
    F e → {
      ( nurl_print `empty_err=` )
      ( nurl_print ( parse_err_msg # ParseErr e ) )
      ( nurl_print `\n` )
    }
  }

  : ! Regex ParseErr rj ( regex_compile `(unclosed` )
  ?? rj {
    T rx → { ( nurl_print `unclosed unexpectedly compiled\n` ) ( regex_free rx ) }
    F e → {
      ( nurl_print `unclosed_err=` )
      ( nurl_print ( parse_err_msg # ParseErr e ) )
      ( nurl_print `\n` )
    }
  }

  ( nurl_print `done\n` )
  ^ 0
}
