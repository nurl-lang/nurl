// doomfire.nu — Classic Doom Fire Effect

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

: i W 320
: i H 180
: i FPS 60

@ main → i {
    : i total_px * W H
    // Lämpöpuskuri (0 = musta, 36 = valkoinen/kuumin)
    : *i fire # *i ( malloc * total_px 8 )

    // Alustetaan taulukko nollilla
    : ~ i i 0
    ~ < i total_px {
        = . fire i 0
        = i + i 1
    }

    // Luodaan 37 värin paletti (mustasta punaiseen, keltaiseen ja valkoiseen)
    : *i pal # *i ( malloc * 37 8 )
    : ~ i p 0
    ~ < p 37 {
        : ~ i r 0 : ~ i g 0 : ~ i b 0

        ? < p 13 {
            = r * p 21
        } {
            ? < p 25 {
                = r 255
                = g * - p 12 21
            } {
                = r 255
                = g 255
                = b * - p 24 21
            }
        }

        // Estetään ylivuodot varotoimena
        ? > r 255 { = r 255 } {}
        ? > g 255 { = g 255 } {}
        ? > b 255 { = b 255 } {}

        // Pakataan NURLin ARGB-muotoon: 0xFF000000 | R<<16 | G<<8 | B
        : i color | 4278190080 | | * r 65536 * g 256 b
        = . pal p color
        = p + p 1
    }

    : *i fb ( canvas_open W H )
    : i frame_ms / 1000 FPS

    ~ == 0 ( canvas_should_close ) {
        // 1. Asetetaan alimmalle riville aina maksimilämpö (36)
        : i bottom_offset * - H 1 W
        : ~ i bx 0
        ~ < bx W {
            = . fire + bottom_offset bx 36
            = bx + bx 1
        }

        // 2. Liekkialgoritmi: levitetään lämpöä alhaalta ylöspäin
        : ~ i x 0
        ~ < x W {
            : ~ i y 1
            ~ < y H {
                : i src + * y W x
                : i pixel . fire src

                ? == pixel 0 {
                    // Jos pikseli on musta, yläpuolikin pysyy mustana
                    = . fire - src W 0
                } {
                    // Arvotaan tuulen sivuttaissiirtymä (0-2) ja lämmön hiipuminen (0-1)
                    : i r % ( rand ) 3
                    : i heat - pixel & r 1

                    // X-koordinaatti johon liekki siirtyy: x - r + 1
                    : i dst_x + - x r 1

                    // Kohdeindeksi muistissa
                    : i dst + - - src W r 1

                    // Varmistetaan ettei liekki kiedo ruudun reunojen yli
                    ? & >= dst_x 0 < dst_x W {
                        = . fire dst heat
                    } {}
                }
                = y + y 1
            }
            = x + x 1
        }

        // 3. Piirretään liekkipuskuri ruudulle paletin läpi
        : ~ i idx 0
        ~ < idx total_px {
            // luetaan lämpötila -> haetaan väri -> kirjoitetaan ruudulle
            = . fb idx . pal . fire idx
            = idx + idx 1
        }

        ( canvas_present )
        ( canvas_sleep frame_ms )
    }

    ( canvas_close )
    ^ 0
}
