// ============================================================
// test_08_higher_order.nu
// Tarkoitus: Testata 5.2 ominaisuuksia: Geneeriset funktiokutsut (monomorfisaatio),
// ylemmän kertaluvun funktiot (map, filter, fold) ja closurejen syöttäminen niille.
// ============================================================

// 1. FOLD: Kertaa listan alkiot ja tiivistää ne yhteen arvoon.
// Tyyppiparametrit: [A B]. A = listan alkion tyyppi, B = akkumulaattorin tyyppi.
// Closure saa akkumulaattorin (B) ja alkion (A), ja palauttaa uuden akkumulaattorin (B).
@ fold [A B] [A xs B init ( @ B B A ) f → B {
    : ~ B acc init
    ~ x xs {
        = acc ( f acc x )
    }
    ^ acc
}

// 1b. FOLD over the first `n` elements only: `filter_in_place` fills a
// prefix of its output slice, and the rest of it is not part of the answer.
@ fold_n [A B] [A xs i n B init ( @ B B A ) f → B {
    : ~ B acc init
    : ~ i k 0
    ~ x xs {
        ? < k n { = acc ( f acc x ) } {}
        = k + k 1
    }
    ^ acc
}

// 2. MAP (in-place): Muuntaa alkioita ja tallentaa ne valmiiksi varattuun sliceen.
// Palauttaa käsiteltyjen alkioiden määrän.
@ map_in_place [A B] [A in_xs [B out_xs ( @ B A ) f → i {
    : ~ i idx 0
    ~ x in_xs {
        // out_xs[idx] = f(x)
        = . out_xs idx ( f x )
        = idx + idx 1
    }
    ^ idx
}

// 3. FILTER (in-place): Valitsee ehdot täyttävät alkiot toiseen sliceen.
// Palauttaa tallennettujen alkioiden määrän (count).
@ filter_in_place [A] [A in_xs [A out_xs ( @ b A ) pred → i {
    : ~ i count 0
    ~ x in_xs {
        : b matched ( pred x )

        // Jos ehto täyttyy, lisätään out_xs-taulukkoon
        ?? matched {
            T → {
                = . out_xs count x
                = count + count 1
                0  // Block-expression vaatii paluuarvon
            }
            F → 0
        }
    }
    ^ count
}

// Apufunktio: Tulostaa i-tyyppisen slicen (esim. "[ 2 4 6 ]")
@ print_slice_i [i xs → i {
    ( nurl_print `[` )
    ~ x xs {
        ( nurl_print ` ` )
        ( nurl_print ( nurl_str_int x ) )
    }
    ( nurl_print ` ]\n` )
    ^ 0
}

// …and the first `n` elements of one.
@ print_prefix_i [i xs i n → i {
    ( nurl_print `[` )
    : ~ i k 0
    ~ x xs {
        ? < k n {
            ( nurl_print ` ` )
            ( nurl_print ( nurl_str_int x ) )
        } {}
        = k + k 1
    }
    ( nurl_print ` ]
` )
    ^ 0
}

// --- PÄÄOHJELMA ---
@ main → i {
    ( nurl_print `== Higher-Order Functions Test ==\n` )

    // --- ALKUDATA ---
    : [i data [i | 1 2 3 4 5]
    ( nurl_print `Data:            ` )
    ( print_slice_i data )

    // --- MAP: x -> x * 2 ---
    // Varataan 5 alkion nollataulukko tulosta varten
    : [i mapped_data [i | 0 0 0 0 0]
    : ( @ i i ) doubler \ i x → i { ^ * x 2 }

    // Geneerisen funktion kutsu: kerrotaan kääntäjälle, että [A B] = [i i]
    ( map_in_place [i i] data mapped_data doubler )

    ( nurl_print `Mapped (x*2):    ` )
    ( print_slice_i mapped_data )

    // --- FILTER: x -> x > 5 ---
    : [i filtered_data [i | 0 0 0 0 0]
    : ( @ b i ) is_large \ i x → b { ^ > x 5 }

    : i match_count ( filter_in_place [i] mapped_data filtered_data is_large )

    // filtered_data has room for 5; its first match_count elements are the
    // answer. (A slice owns its buffer, so a second slice over the same
    // buffer — `@ [i { pointer length }` — is refused in safe code: the
    // prefix is walked by count instead.)
    ( nurl_print `Filtered (x>5):  ` )
    ( print_prefix_i filtered_data match_count )

    // --- FOLD: summa ---
    : ( @ i i i ) summer \ i acc i x → i { ^ + acc x }
    : i total_sum ( fold_n [i i] filtered_data match_count 0 summer )

    ( nurl_print `Folded (sum):    ` )
    ( nurl_print ( nurl_str_int total_sum ) )
    ( nurl_print `\n` )

    // Pitäisi olla 6 + 8 + 10 = 24
    ^ total_sum
}
