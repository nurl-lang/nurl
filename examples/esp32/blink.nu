// ============================================================
//  blink.nu — bare-metal GPIO blink for ESP32-C3 (RISC-V), in NURL
//
//  Toggles GPIO8 (the on-board LED on most ESP32-C3 dev boards) by
//  writing directly to the GPIO peripheral's memory-mapped registers.
//  No ESP-IDF, no HAL — just `*i32` pointers at fixed addresses, which
//  is exactly what a register poke is.
//
//  Pipeline:  nurlc blink.nu > blink.ll          (portable LLVM IR)
//             llc -march=riscv32 ...  blink.ll    (real RV32 machine code)
//             riscv32-esp-elf-gcc ... -> blink.elf
//  See build.sh and README.md.
//
//  NOTE on the classic Xtensa ESP32 / S2 / S3: the same source compiles
//  to IR unchanged — only the register addresses differ (see README).
//  Xtensa machine-code emission needs Espressif's esp-clang; stock
//  LLVM 18's Xtensa backend cannot emit object code yet.
// ============================================================

// --- ESP32-C3 GPIO register map (TRM ch. "IO MUX and GPIO Matrix") ---
//     addresses are `i` (i64) because in this nurlc `u` lowers to i8;
//     the MMIO access itself is a 32-bit store via a `*i32` pointer.
: i REG_GPIO_OUT_W1TS 0x60004008  // set output bits
: i REG_GPIO_OUT_W1TC 0x6000400C  // clear output bits
: i REG_GPIO_ENABLE_W1TS 0x60004024  // enable as output
: i PIN_MASK 256  // 1 << 8       GPIO8

// 32-bit memory-mapped write: *(volatile u32*)addr = val
@ poke i addr i32 val → v {
    : *i32 p # *i32 addr
    = . p 0 val
}

// crude busy-wait — at -O0 the loop survives; see README on volatile.
@ delay i n → v {
    : ~ i k 0
    ~ < k n { = k + k 1 }
}

@ main → i {
    // configure GPIO8 as a push-pull output
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
