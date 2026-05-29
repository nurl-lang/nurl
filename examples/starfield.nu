// starfield.nu — 3D Warp Speed Starfield with Motion Blur
// NURL Canvas demo.

& `libc` @ rand → i

& `canvas` @ canvas_open i w i h → *i

& `canvas` @ canvas_present → v

& `canvas` @ canvas_sleep i ms → v

& `canvas` @ canvas_should_close → i

& `canvas` @ canvas_close → v

// Suurempi resoluutio ja 60 FPS
: i W 640
: i H 360
: i FPS 60
: i NUM_STARS 1000

@ main → i {
    // Varataan taulukot tähtien 3D-koordinaateille
    : *i stars_x # *i ( malloc * NUM_STARS 8 )
    : *i stars_y # *i ( malloc * NUM_STARS 8 )
    : *i stars_z # *i ( malloc * NUM_STARS 8 )

    // Alustetaan tähdet satunnaisiin paikkoihin
    : ~ i init_idx 0
    ~ < init_idx NUM_STARS {
        // Arvotaan X ja Y väliltä -2000 ... 2000
        = . stars_x init_idx - % ( rand ) 4000 2000
        = . stars_y init_idx - % ( rand ) 4000 2000
        // Arvotaan Z (syvyys) väliltä 1 ... 1000
        = . stars_z init_idx + 1 % ( rand ) 1000
        = init_idx + init_idx 1
    }

    : *i fb ( canvas_open W H )
    : i frame_ms / 1000 FPS
    : ~ i t 0

    ~ == 0 ( canvas_should_close ) {
        // 1. MOTION BLUR
        // Koko ruudun mustaamisen sijaan himmennetään kaikkia pikseleitä.
        : ~ i px_idx 0
        : i total_px * W H
        ~ < px_idx total_px {
            : i old . fb px_idx
            // Maskataan 0x00FEFEFE (16711422) jotta kanavat eivät vuoda yli
            // ja jaetaan kahdella (bitti kerrallaan oikealle).
            : i masked & old 16711422
            : i faded / masked 2
            // Palautetaan läpinäkymätön alpha (0xFF000000 = 4278190080)
            = . fb px_idx | 4278190080 faded
            = px_idx + px_idx 1
        }

        // 2. Sykkivä vauhti "warp-moottorille" (kolmioaalto)
        : i cycle % t 100
        : i speed + 5 ? < cycle 50 cycle - 100 cycle

        // 3. Tähtien päivitys ja piirto
        : ~ i i 0
        ~ < i NUM_STARS {
            // Tähti liikkuu kameraa kohti
            = . stars_z i - . stars_z i speed

            // Jos tähti ohittaa kameran, nollataan se kauas taakse
            ? <= . stars_z i 0 {
                = . stars_z i 1000
                = . stars_x i - % ( rand ) 4000 2000
                = . stars_y i - % ( rand ) 4000 2000
            } {}

            // 3D -> 2D projektio (FOV-kerroin 300)
            : i z . stars_z i
            : i sx + / W 2 / * . stars_x i 300 z
            : i sy + / H 2 / * . stars_y i 300 z

            // Piirretään pikseli vain, jos se on ruudun sisällä
            ? & & >= sx 0 < sx W & >= sy 0 < sy H {
                // Mitä lähempänä (pienempi z), sen kirkkaampi (0-255)
                : i intensity - 255 / * z 255 1000

                // Generoidaan tähdille vähän väriä indeksin mukaan
                : i c_mod % i 3
                // Sinertävä
                : i r ? == c_mod 1 / intensity 2 intensity
                // Kellertävä / normaali
                : i g ? == c_mod 1 / intensity 2 intensity
                // Valkoinen
                : i b ? == c_mod 2 / intensity 2 intensity

                // ARGB-pakkaus: 0xFF000000 | (r<<16) | (g<<8) | b
                : i color | 4278190080 | | * r 65536 * g 256 b

                = . fb + * sy W sx color
            } {}

            = i + i 1
        }

        ( canvas_present )
        ( canvas_sleep frame_ms )
        = t + t 1
    }

    ( canvas_close )
    ^ 0
}
