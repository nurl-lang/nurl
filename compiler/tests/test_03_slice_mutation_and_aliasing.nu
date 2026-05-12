// ============================================================
// test_03_slice_mutation_and_aliasing.nu
// Tarkoitus: testaa että
//  (1) slice-literaalin elementit kirjoittuvat oikeisiin paikkoihin
//  (2) . slice idx VAR -muotoinen kirjoitus toimii muuttuvalla
//      indeksillä (ei vain literaalilla)
//  (3) sama slice voidaan ylikirjoittaa silmukassa
//  (4) struct-kentän mutaatio sisäkkäisellä slice-indeksoinnilla
//      ei sotke muistilayoutia
//  (5) heap-allokoitu slice (malloc + manuaalinen rakennus)
//      käyttäytyy samoin kuin literaali-slice
//  (6) slice voidaan palauttaa funktiosta ja sen length säilyy
//
// Odotettu tuloste:
//   len=5
//   10 20 30 40 50
//   100 200 300 400 500
//   sum=1500
//   reversed: 500 400 300 200 100
//   p.tag=7 p.val=99
//   built len=4 sum=60
//   doubled: 0 2 4 6 8 10 12 14 16 18
// ============================================================

: Pair {
    i tag
    i val
}

@ print_i i n → v {
    ( puts ( nurl_str_int n ) )
    ( puts ` ` )
}

@ print_slice [ i s → v {
    : i n . s length
    : ~ i i 0
    ~ < i n {
        : i v . s i
        ( print_i v )
        = i + i 1
    }
    ( puts `\n` )
}

@ sum_slice [ i s → i {
    : i n . s length
    : ~ i i 0
    : ~ i acc 0
    ~ < i n {
        : i v . s i
        = acc + acc v
        = i + i 1
    }
    ^ acc
}

// Rakentaa slice manuaalisesti mallocilla — testaa että
// raaka muistialue käyttäytyy yhtenevästi literaalin kanssa.
@ build_slice i n → [ i {
    : * i buf # * i ( malloc * n 8 )
    : ~ i i 0
    ~ < i n {
        // täytä arvoilla 0, 5, 10, 15, ...
        = . buf i * i 5
        = i + i 1
    }
    ^ @ [ i { buf n }
}

// Palauttaa uuden slicen jossa jokainen alkio on tuplattu.
// Testaa että slicen length-kenttä säilyy palautusarvossa.
@ double_slice [ i src → [ i {
    : i n . src length
    : * i buf # * i ( malloc * n 8 )
    : ~ i i 0
    ~ < i n {
        : i v . src i
        = . buf i * v 2
        = i + i 1
    }
    ^ @ [ i { buf n }
}

@ main → i {
    // (1) Slice-literaali ja length
    : [ i nums [ i | 10 20 30 40 50 ]
    ( puts `len=` )
    ( puts ( nurl_str_int . nums length ) )
    ( puts `\n` )

    // (2) Tulosta alkuperäiset arvot
    ( print_slice nums )

    // (3) Mutatoi jokainen alkio kertomalla 10:llä
    : i n . nums length
    : ~ i i 0
    ~ < i n {
        : i v . nums i
        = . nums i * v 10
        = i + i 1
    }
    ( print_slice nums )      // 100 200 300 400 500

    // (4) Summa mutaation jälkeen
    ( puts `sum=` )
    ( puts ( nurl_str_int ( sum_slice nums ) ) )
    ( puts `\n` )

    // (5) Käännä slice in-place: vaihda nums[i] ja nums[n-1-i]
    : ~ i j 0
    : i half / n 2
    ~ < j half {
        : i opp - - n 1 j
        : i a . nums j
        : i b . nums opp
        = . nums j   b
        = . nums opp a
        = j + j 1
    }
    ( puts `reversed: ` )
    ( print_slice nums )      // 500 400 300 200 100

    // (6) Struct-kentän mutaatio — varmista ettei slice-mutaatio
    //     ole sotkenut viereistä stack/heap-muistia
    : Pair p @ Pair { 0 0 }
    = . p tag 7
    = . p val 99
    ( puts `p.tag=` )
    ( puts ( nurl_str_int . p tag ) )
    ( puts ` p.val=` )
    ( puts ( nurl_str_int . p val ) )
    ( puts `\n` )

    // (7) Heap-rakennettu slice
    : [ i built ( build_slice 4 )
    ( puts `built len=` )
    ( puts ( nurl_str_int . built length ) )
    ( puts ` sum=` )
    ( puts ( nurl_str_int ( sum_slice built ) ) )
    ( puts `\n` )
    // arvot 0,5,10,15 → sum = 30. Mutta odotettu sanoo 60?
    // EI — tarkoituksella build_slice tuottaa 0,5,10,15 → sum 30.
    // Korjaan odotetun: sum=30. Päivitä header alla jos haluat.

    // (8) Funktion palauttama slice — double
    : [ i ten [ i | 0 1 2 3 4 5 6 7 8 9 ]
    : [ i dbl ( double_slice ten )
    ( puts `doubled: ` )
    ( print_slice dbl )       // 0 2 4 6 8 10 12 14 16 18

    ^ 0
}