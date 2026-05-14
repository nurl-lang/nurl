// sand.nu — Interaktiivinen Falling Sand -simulaatio

& `libc`

@ rand → i

& `canvas`

@ canvas_open i w i h → *i

& `canvas`

@ canvas_present → v

& `canvas`

@ canvas_sleep i ms → v

& `canvas`

@ canvas_should_close → i

& `canvas`

@ canvas_close → v

// Hiirifunktiot (FFI C-kirjastosta tai WASM shimistä)
& `canvas`

@ canvas_mouse_x → i

& `canvas`

@ canvas_mouse_y → i

& `canvas`

@ canvas_mouse_btn → i

: i W 320
: i H 180
: i FPS 60

@ main → i {
    : i total_px * W H

    // Simulaatioverkko: 0 = tyhjä, 1 = hiekka
    : *i grid # *i ( malloc * total_px 8 )

    // Alustetaan verkko tyhjäksi
    : ~ i i 0
    ~ < i total_px {
        = . grid i 0
        = i + i 1
    }

    // Hiekan väri (Kullanvärinen keltainen, 0xFFEEDD88)
    : i COL_SAND | 4278190080 | * 238 65536 | * 221 256 136
    // Taustan väri (Musta, 0xFF000000)
    : i COL_BG 4278190080

    : *i fb ( canvas_open W H )
    : i frame_ms / 1000 FPS

    ~ == 0 ( canvas_should_close ) {

        // 1. INPUT: Piirretään hiekkaa hiirellä
        : i mx ( canvas_mouse_x )
        : i my ( canvas_mouse_y )
        : i mbtn ( canvas_mouse_btn )

        ? == mbtn 1 {
            // Tehdään pieni "sivellin" (5x5 neliö hiiren ympärille)
            : ~ i dy - 0 2
            ~ <= dy 2 {
                : ~ i dx - 0 2
                ~ <= dx 2 {
                    : i px + mx dx
                    : i py + my dy

                    // Varmistetaan, että pysytään ruudulla
                    ? & & & >= px 0 < px W >= py 0 < py H {
                        // Lisätään hiekkaa satunnaisesti (spray-efekti)
                        ? == % ( rand ) 3 0 {
                            = . grid + * py W px 1
                        } {}
                    } {}
                    = dx + dx 1
                }
                = dy + dy 1
            }
        } {}

        // 2. FYSIIKKA: Päivitetään hiekanjyvät
        // TÄRKEÄÄ: Hiekka pitää käydä läpi ALHAALTA YLÖS, jottei sama 
        // jyvä putoa koko ruudun mitalta yhden framen aikana!
        : ~ i y - H 2
        ~ >= y 0 {
            : ~ i x 0
            ~ < x W {
                : i src_idx + * y W x

                // Jos solussa on hiekkaa...
                ? == . grid src_idx 1 {
                    : i down_idx + * + y 1 W x

                    // Vaihtoehto A: Suoraan alla on tyhjää
                    ? == . grid down_idx 0 {
                        = . grid down_idx 1
                        = . grid src_idx 0
                    } {
                        // Vaihtoehto B: Alla on varattu, kokeillaan viistoon
                        // Tarkistetaan, ollaanko reunalla ja onko tilaa
                        : i can_l & > x 0 == . grid - down_idx 1 0
                        : i can_r & < x - W 1 == . grid + down_idx 1 0

                        ? & can_l can_r {
                            // Molemmat vapaana: valitaan suunta satunnaisesti
                            // ettei hiekka kasaudu luonnottomasti vain toiselle puolelle
                            ? == % ( rand ) 2 0 {
                                = . grid - down_idx 1 1
                            } {
                                = . grid + down_idx 1 1
                            }
                            = . grid src_idx 0
                        } {
                            // Vain toinen vapaana
                            ? can_l {
                                = . grid - down_idx 1 1
                                = . grid src_idx 0
                            } {
                                ? can_r {
                                    = . grid + down_idx 1 1
                                    = . grid src_idx 0
                                } {}
                            }
                        }
                    }
                } {}
                = x + x 1
            }
            = y - y 1
        }

        // 3. PIIRTO: Siirretään grid framebufferiin
        : ~ i idx 0
        ~ < idx total_px {
            = . fb idx ? == . grid idx 1 COL_SAND COL_BG
            = idx + idx 1
        }

        ( canvas_present )
        ( canvas_sleep frame_ms )
    }

    ( canvas_close )
    ^ 0
}
