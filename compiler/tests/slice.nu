// --- Apufunktiot ---
@ println_int i n → v {
    ( nurl_print ( nurl_str_int n ) )
    ( nurl_print `\n` )
}

// --- Slice-tyyppi määritelmä (valinnainen) ---
: Slice { * i data  i length }

// --- Slice-logiikka: KAKSI SYNTAKSIA! ---

// Versio 1: Token-optimoitu (4 tokenia)
@ sum_slice_direct * i data i length → i {
    : i total 0
    : i index 0

    ~ < index length {
        // Haetaan arvo: data[index]
        : i val . data index
        = total + total val
        = index + index 1
    }
    ^ total
}

// Versio 2: Struct-versio (8 tokenia, mutta tyyppiturva)
@ sum_slice_struct Slice slice → i {
    : i total 0
    : i index 0
    : i length . slice length
    : * i data . slice data

    ~ < index length {
        // Haetaan arvo: data[index]
        : i val . data index
        = total + total val
        = index + index 1
    }
    ^ total
}

// --- Main ---

@ main → i {
    ( nurl_print `--- NURL v0.3: Slice & Dynamic Array Test ---\n` )

    : i count 5
    // 1. Varataan tilaa 5:lle i64-luvulle (5 * 8 tavua)
    : * i raw_ptr # * i ( nurl_malloc * count Z i )
    
    // 2. Täytetään taulukko (esim. 10, 20, 30, 40, 50)
    = . raw_ptr 0 10
    = . raw_ptr 1 20
    = . raw_ptr 2 30
    = . raw_ptr 3 40
    = . raw_ptr 4 50

    // 3. Demonstroi MOLEMMAT syntaksit!

    // Token-optimoitu versio (4 tokenia)
    : i result1 ( sum_slice_direct raw_ptr count )
    ( nurl_print `Token-optimoitu (4 tokenia): ` )
    ( println_int result1 )

    // Struct-versio (8 tokenia)
    : i result2 ( sum_slice_struct @ Slice { raw_ptr count } )
    ( nurl_print `Struct-versio (8 tokenia):   ` )
    ( println_int result2 )

    // Molemmat antavat saman tuloksen!
    ( nurl_print `Molemmat toimivat - valitse tarpeesi mukaan!\n` )

    // 5. Muistin siivous
    ; { 
        ( nurl_free # * v raw_ptr ) 
        ( nurl_print `Dynaaminen muisti vapautettu.\n` )
    }

    ^ 0
}