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

@ main → i {
    // Luodaan optionaalinen Node, esim. simuloitu tietokantahaku
    : ? Node opt_node @ ? Node { T @ Node { 1 100 } }
    
    // Luodaan toinen Node, eli oletusarvo tai uusi syöte
    : Node fallback_node @ Node { 2 50 }

    // TÄSSÄ ON ANSA KÄÄNTÄJÄLLE:
    // Kutsutaan funktiota: ensimmäinen argumentti puretaan try-operaattorilla (\),
    // toinen argumentti on normaali muuttuja.
    : i result ( process_nodes \ opt_node fallback_node )

    ( nurl_print `result=` )
    ( nurl_print ( nurl_str_int result ) )
    ( nurl_print `\n` )

    ^ result
}