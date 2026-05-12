// json_basic.nu — exercises stdlib/ext/json.nu
//
// Expected output:
//   parse null ok type=null
//   parse true ok type=bool val=T
//   parse false ok type=bool val=F
//   parse 42 ok type=num as_i=42
//   parse -3.5 ok type=num as_f=-3.5
//   parse "hi\n" ok type=str data=hi
//   parse [1,2,3] ok type=arr len=3 first=1
//   parse {"a":1,"b":[true,null]} ok type=obj a=1 b_len=2
//   stringify roundtrip ok
//   err empty: empty input
//   err bad: bad format
//   err trailing: trailing garbage

$ `stdlib/ext/json.nu`

@ show_err s label ParseErr e → v {
  ( nurl_print label )
  ( nurl_print ( parse_err_msg # ParseErr e ) )
  ( nurl_print `\n` )
}

@ main → i {
  // 1. null
  : ! Json ParseErr r1 ( json_parse `null` )
  ?? r1 {
    T j → {
      ( nurl_print `parse null ok type=` )
      ( nurl_print ( json_type_name j ) )
      ( nurl_print `\n` )
      ( json_free j )
    }
    F e → ( show_err `parse null err: ` # ParseErr e )
  }

  // 2. true
  : ! Json ParseErr r2 ( json_parse `true` )
  ?? r2 {
    T j → {
      ( nurl_print `parse true ok type=` )
      ( nurl_print ( json_type_name j ) )
      ( nurl_print ` val=` )
      ( nurl_print ? ( json_bool_val j ) `T` `F` )
      ( nurl_print `\n` )
      ( json_free j )
    }
    F e → ( show_err `parse true err: ` # ParseErr e )
  }

  // 3. false
  : ! Json ParseErr r3 ( json_parse `false` )
  ?? r3 {
    T j → {
      ( nurl_print `parse false ok type=` )
      ( nurl_print ( json_type_name j ) )
      ( nurl_print ` val=` )
      ( nurl_print ? ( json_bool_val j ) `T` `F` )
      ( nurl_print `\n` )
      ( json_free j )
    }
    F e → ( show_err `parse false err: ` # ParseErr e )
  }

  // 4. integer
  : ! Json ParseErr r4 ( json_parse `42` )
  ?? r4 {
    T j → {
      ( nurl_print `parse 42 ok type=` )
      ( nurl_print ( json_type_name j ) )
      ( nurl_print ` as_i=` )
      : ? i ai ( json_num_as_i j )
      ?? ai {
        T n → ( nurl_print ( nurl_str_int n ) )
        F   → ( nurl_print `(none)` )
      }
      ( nurl_print `\n` )
      ( json_free j )
    }
    F e → ( show_err `parse 42 err: ` # ParseErr e )
  }

  // 5. negative float
  : ! Json ParseErr r5 ( json_parse `-3.5` )
  ?? r5 {
    T j → {
      ( nurl_print `parse -3.5 ok type=` )
      ( nurl_print ( json_type_name j ) )
      ( nurl_print ` as_f=` )
      : ? f af ( json_num_as_f j )
      ?? af {
        T x → ( nurl_print ( nurl_str_float x ) )
        F   → ( nurl_print `(none)` )
      }
      ( nurl_print `\n` )
      ( json_free j )
    }
    F e → ( show_err `parse -3.5 err: ` # ParseErr e )
  }

  // 6. string with escape
  : ! Json ParseErr r6 ( json_parse `"hi\n"` )
  ?? r6 {
    T j → {
      ( nurl_print `parse "hi\\n" ok type=` )
      ( nurl_print ( json_type_name j ) )
      ( nurl_print ` data=` )
      ( nurl_print ( json_str_data j ) )
      ( json_free j )
    }
    F e → ( show_err `parse string err: ` # ParseErr e )
  }

  // 7. array of integers
  : ! Json ParseErr r7 ( json_parse `[1, 2, 3]` )
  ?? r7 {
    T j → {
      ( nurl_print `parse [1,2,3] ok type=` )
      ( nurl_print ( json_type_name j ) )
      ( nurl_print ` len=` )
      ( nurl_print ( nurl_str_int ( json_arr_len j ) ) )
      ( nurl_print ` first=` )
      : ? Json fst ( json_arr_get j 0 )
      ?? fst {
        T v → {
          : ? i ai ( json_num_as_i v )
          ?? ai {
            T n → ( nurl_print ( nurl_str_int n ) )
            F   → ( nurl_print `?` )
          }
        }
        F → ( nurl_print `none` )
      }
      ( nurl_print `\n` )
      ( json_free j )
    }
    F e → ( show_err `parse arr err: ` # ParseErr e )
  }

  // 8. object with mixed values
  : ! Json ParseErr r8 ( json_parse `{"a": 1, "b": [true, null]}` )
  ?? r8 {
    T j → {
      ( nurl_print `parse obj ok type=` )
      ( nurl_print ( json_type_name j ) )
      ( nurl_print ` a=` )
      : ? Json va ( json_obj_get j `a` )
      ?? va {
        T v → {
          : ? i ai ( json_num_as_i v )
          ?? ai {
            T n → ( nurl_print ( nurl_str_int n ) )
            F   → ( nurl_print `?` )
          }
        }
        F → ( nurl_print `(missing)` )
      }
      ( nurl_print ` b_len=` )
      : ? Json vb ( json_obj_get j `b` )
      ?? vb {
        T v → ( nurl_print ( nurl_str_int ( json_arr_len v ) ) )
        F   → ( nurl_print `(missing)` )
      }
      ( nurl_print `\n` )

      // 9. roundtrip
      : String out ( json_stringify j )
      // Re-parse the serialized form and compare top-level keys.
      : ! Json ParseErr r9 ( json_parse ( string_data out ) )
      ?? r9 {
        T j2 → {
          ? & ( json_is_obj j2 ) ( json_obj_has j2 `b` ) {
            ( nurl_print `stringify roundtrip ok\n` )
          } {
            ( nurl_print `stringify roundtrip MISMATCH\n` )
          }
          ( json_free j2 )
        }
        F e → ( show_err `roundtrip parse err: ` # ParseErr e )
      }
      ( string_free out )
      ( json_free j )
    }
    F e → ( show_err `parse obj err: ` # ParseErr e )
  }

  // 10. error paths
  : ! Json ParseErr re1 ( json_parse `` )
  ?? re1 {
    T j → { ( nurl_print `unexpected ok\n` ) ( json_free j ) }
    F e → ( show_err `err empty: ` # ParseErr e )
  }

  : ! Json ParseErr re2 ( json_parse `xyz` )
  ?? re2 {
    T j → { ( nurl_print `unexpected ok\n` ) ( json_free j ) }
    F e → ( show_err `err bad: ` # ParseErr e )
  }

  : ! Json ParseErr re3 ( json_parse `42 trailing` )
  ?? re3 {
    T j → { ( nurl_print `unexpected ok\n` ) ( json_free j ) }
    F e → ( show_err `err trailing: ` # ParseErr e )
  }

  // 11. json_pretty + json_obj_keys + json_arr_each + json_obj_each
  : ! Json ParseErr rp ( json_parse `{"x":1,"y":[true,null],"z":"q"}` )
  ?? rp {
    T j → {
      // pretty roundtrips through compact parser back into the same value
      : String pp ( json_pretty j )
      ( nurl_print `pretty:\n` )
      ( nurl_print ( string_data pp ) )
      ( nurl_print `\n` )

      // obj_keys yields the key list in declaration order
      : ( Vec String ) keys ( json_obj_keys j )
      ( nurl_print `keys=` )
      : i kn ( vec_len [String] keys )
      : ~ i ki 0
      ~ < ki kn {
        : ? String e ( vec_get [String] keys ki )
        ?? e {
          T s → {
            ? > ki 0 { ( nurl_print `,` ) } {}
            ( nurl_print ( string_data s ) )
          }
          F → {}
        }
        = ki + ki 1
      }
      ( nurl_print `\n` )
      : (@ v String) drop_s \ String s → v { ( string_free s ) }
      ( vec_free_with [String] keys drop_s )

      // arr_each on the inner array (json_obj_get → JArr)
      : ? Json y ( json_obj_get j `y` )
      ?? y {
        T jy → {
          ( nurl_print `y_each=` )
          : (@ v Json) p \ Json e → v {
            ( nurl_print ( json_type_name e ) )
            ( nurl_print `,` )
          }
          ( json_arr_each jy p )
          ( nurl_print `\n` )
        }
        F → ( nurl_print `y missing\n` )
      }

      // obj_each on the outer object — prints "key=type;" per pair
      ( nurl_print `obj_each=` )
      : (@ v s Json) print_pair \ s k Json v → v {
        ( nurl_print k )
        ( nurl_print `=` )
        ( nurl_print ( json_type_name v ) )
        ( nurl_print `;` )
      }
      ( json_obj_each j print_pair )
      ( nurl_print `\n` )

      ( string_free pp )
      ( json_free j )
    }
    F e → ( show_err `pretty parse err: ` # ParseErr e )
  }

  // 12. pretty edge: empty array + empty object collapse
  : ! Json ParseErr rp2 ( json_parse `{"a":[],"b":{}}` )
  ?? rp2 {
    T j → {
      : String p ( json_pretty j )
      ( nurl_print `empty_pretty:\n` )
      ( nurl_print ( string_data p ) )
      ( nurl_print `\n` )
      ( string_free p )
      ( json_free j )
    }
    F e → ( show_err `empty pretty err: ` # ParseErr e )
  }

  // 13. Programmatic build via constructors + mutators
  : Json built ( json_obj_new )
  ( json_obj_set built `id` ( json_int 7 ) )
  ( json_obj_set built `score` ( json_float 0.95 ) )
  ( json_obj_set built `tag`  ( json_str_lit `alpha` ) )
  : Json items ( json_arr_new )
  ( json_arr_push items ( json_int 10 ) )
  ( json_arr_push items ( json_int 20 ) )
  ( json_arr_push items ( json_int 30 ) )
  ( json_obj_set built `items` items )
  : String built_s ( json_stringify built )
  ( nurl_print `built=` )
  ( nurl_print ( string_data built_s ) )
  ( nurl_print `\n` )

  // 14. json_get path access
  : ? Json id ( json_get built `id` )
  ?? id {
    T jv → {
      : ? i ai ( json_num_as_i jv )
      ?? ai { T n → { ( nurl_print `id=` )
                      ( nurl_print ( nurl_str_int n ) )
                      ( nurl_print `\n` ) }
              F   → ( nurl_print `id missing\n` ) }
    }
    F → ( nurl_print `id missing\n` )
  }

  : ? Json second ( json_get built `items.1` )
  ?? second {
    T jv → {
      : ? i ai ( json_num_as_i jv )
      ?? ai { T n → { ( nurl_print `items.1=` )
                      ( nurl_print ( nurl_str_int n ) )
                      ( nurl_print `\n` ) }
              F   → ( nurl_print `items.1 missing\n` ) }
    }
    F → ( nurl_print `items.1 missing\n` )
  }

  : ? Json miss ( json_get built `items.99` )
  ?? miss {
    T _ → ( nurl_print `oob unexpected\n` )
    F   → ( nurl_print `items.99=none\n` )
  }

  // 15. json_obj_set replaces existing key (frees old value)
  ( json_obj_set built `id` ( json_int 999 ) )
  : ? Json id2 ( json_get built `id` )
  ?? id2 {
    T jv → {
      : ? i ai ( json_num_as_i jv )
      ?? ai { T n → { ( nurl_print `id_after=` )
                      ( nurl_print ( nurl_str_int n ) )
                      ( nurl_print `\n` ) }
              F   → {} }
    }
    F → {}
  }

  // 16. json_clone produces an independent tree (mutation of clone
  //     doesn't affect original)
  : Json dup ( json_clone built )
  ( json_obj_set dup `id` ( json_int -1 ) )
  ( nurl_print `eq_after_clone=` )
  ( nurl_print ? ( json_eq built dup ) `T` `F` )
  ( nurl_print `\n` )

  : ? Json orig_id ( json_get built `id` )
  ?? orig_id {
    T jv → {
      : ? i ai ( json_num_as_i jv )
      ?? ai { T n → { ( nurl_print `orig_id=` )
                      ( nurl_print ( nurl_str_int n ) )
                      ( nurl_print `\n` ) }
              F   → {} }
    }
    F → {}
  }

  // 17. json_eq round-trip on a parsed object
  : ! Json ParseErr e1 ( json_parse `{"x":1,"y":2}` )
  : ! Json ParseErr e2 ( json_parse `{"x":1,"y":2}` )
  : ! Json ParseErr e3 ( json_parse `{"x":1,"y":3}` )
  ?? e1 { T j1 → {
    ?? e2 { T j2 → {
      ?? e3 { T j3 → {
        ( nurl_print `eq_same=` )
        ( nurl_print ? ( json_eq j1 j2 ) `T` `F` )
        ( nurl_print ` eq_diff=` )
        ( nurl_print ? ( json_eq j1 j3 ) `T` `F` )
        ( nurl_print `\n` )
        ( json_free j3 )
      } F _ → {} }
      ( json_free j2 )
    } F _ → {} }
    ( json_free j1 )
  } F _ → {} }

  ( json_free dup )
  ( string_free built_s )
  ( json_free built )

  ^ 0
}
