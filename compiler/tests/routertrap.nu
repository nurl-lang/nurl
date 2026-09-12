// reaalielämän skenaario: Yksinkertainen datan käsittelijä,
// joka yhdistää kaksi datapistettä toisiinsa.

: Node {
    i id
    i value
}

// Funktio, joka ottaa kaksi Node-structia (ei optionaalista) ja laskee jotain
@ process_nodes Node a Node b → i {
    ^ + . a value . b value
}

// TÄSSÄ ON ANSA KÄÄNTÄJÄLLE:
// Kutsutaan funktiota: ensimmäinen argumentti puretaan try-operaattorilla (\),
// toinen argumentti on normaali muuttuja.
//
// '\' palauttaa epäonnistumisen TÄSTÄ funktiosta, joten funktion paluutyypin
// on oltava '?T' tai '!T E'. '@ main → i' ei ole sellainen: siellä None
// olisi hiljaa muuttunut nollaksi. stdlib/core/result.nu sanoo saman —
// '→ i' main on paikka, joka ei voi '\'-propagoida.
@ combine ? Node opt_node Node fallback_node → ?i {
    : i result ( process_nodes \ opt_node fallback_node )
    ^ @ ?i { T result }
}

@ main → i {
    // Luodaan optionaalinen Node, esim. simuloitu tietokantahaku
    : ?Node opt_node @ ?Node { T @ Node { 1 100 } }

    // Luodaan toinen Node, eli oletusarvo tai uusi syöte
    : Node fallback_node @ Node { 2 50 }

    // main ei voi propagoida, joten se PURKAA tuloksen itse.
    : i result ?? ( combine opt_node fallback_node ) { T v → v F → 0 }

    ( nurl_print `result=` )
    ( nurl_print ( nurl_str_int result ) )
    ( nurl_print `\n` )

    ^ result
}
