// ============================================================
//  nurl_blink.nu — GPIO control for the classic ESP32 (Xtensa), in NURL.
//
//  Every line that touches hardware is here, in NURL. The C side
//  (main/app_main.c) only supplies the FreeRTOS-friendly delay and the
//  app_main entry point — a bare busy-loop would starve the idle task and
//  trip the watchdog, so timing comes from vTaskDelay.
//
//  Built for Xtensa with Espressif's esp-clang (see gen_object.sh):
//    nurlc nurl_blink.nu > nurl_blink.ll
//    esp-clang --target=xtensa-esp32-elf -mcpu=esp32 -O2 -c nurl_blink.ll
//
//  No `main` here on purpose: nurlc only emits the main/nurl_init wrapper
//  for a function literally named `main`. Plain functions give clean,
//  self-contained symbols that link straight into an ESP-IDF app.
//
//  Register addresses verified against ESP-IDF soc/{gpio,io_mux}_reg.h.
//  Decimal literals (hex in comments): nurlc takes 0x.. but nurlfmt splits
//  it, so shipped sources stay decimal. LED is GPIO2 on most ESP32 boards.
// ============================================================

// Pure compute, no MMIO — proves the C->NURL windowed cross-call works.
@ nurl_ping → i { ^ 42 }

// 32-bit memory-mapped write: *(volatile u32*)addr = val
@ poke i addr i32 val → v {
    : *i32 p # *i32 addr
    = . p 0 val
}

// Configure GPIO2 as a push-pull output, entirely via raw registers.
@ nurl_led_setup → v {
    ( poke 1072992320 # i32 8192 )  // IO_MUX_GPIO2 (0x3FF49040): MCU_SEL=2 -> GPIO
    ( poke 1072973112 # i32 256 )  // GPIO_FUNC2_OUT_SEL_CFG (0x3FF44538): pad -> GPIO_OUT
    ( poke 1072971812 # i32 4 )  // GPIO_ENABLE_W1TS (0x3FF44024): bit2 -> output
}

@ nurl_led_on → v { ( poke 1072971784 # i32 4 ) }  // GPIO_OUT_W1TS (0x3FF44008): GPIO2 high
@ nurl_led_off → v { ( poke 1072971788 # i32 4 ) }  // GPIO_OUT_W1TC (0x3FF4400C): GPIO2 low
