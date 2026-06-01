// ============================================================
//  blink_xtensa.nu — same blink, classic ESP32 / S2 / S3 (Xtensa LX6/LX7).
//
//  IDENTICAL logic to blink.nu — only the GPIO register addresses change.
//  This is the whole point of NURL's target-agnostic IR: porting the
//  program between an RISC-V ESP32-C3 and an Xtensa ESP32 is a constant
//  table edit, nothing more.
//
//  Compiles to LLVM IR today (`nurlc blink_xtensa.nu`). Final Xtensa
//  machine-code emission needs Espressif's esp-clang — stock LLVM 18's
//  Xtensa backend is registered but cannot emit code yet. See README.md.
// ============================================================

// --- Classic ESP32 GPIO register map (TRM "IO_MUX / GPIO matrix") ---
: i REG_GPIO_OUT_W1TS 1072971784  // 0x3FF4_4008  set output bits
: i REG_GPIO_OUT_W1TC 1072971788  // 0x3FF4_400C  clear output bits
: i REG_GPIO_ENABLE_W1TS 1072971812  // 0x3FF4_4024  enable as output
: i PIN_MASK 4  // 1 << 2       GPIO2 (common LED)

@ poke i addr i32 val → v {
    : *i32 p # *i32 addr
    = . p 0 val
}

@ delay i n → v {
    : ~ i k 0
    ~ < k n { = k + k 1 }
}

@ main → i {
    ( poke REG_GPIO_ENABLE_W1TS # i32 PIN_MASK )

    : ~ i n 0
    ~ < n 1000000 {
        ( poke REG_GPIO_OUT_W1TS # i32 PIN_MASK )  // LED on
        ( delay 200000 )
        ( poke REG_GPIO_OUT_W1TC # i32 PIN_MASK )  // LED off
        ( delay 200000 )
        = n + n 1
    }
    ^ 0
}
