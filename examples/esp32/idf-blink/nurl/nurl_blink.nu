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
//  LED is GPIO2 on most ESP32 "mini" boards; change PIN_MASK and the
//  IO_MUX address for a different pin.
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
  ( poke 0x3FF49040 # i32 0x2000 )   // IO_MUX_GPIO2_REG:       MCU_SEL=2 -> GPIO function
  ( poke 0x3FF44538 # i32 0x100 )    // GPIO_FUNC2_OUT_SEL_CFG: route pad to GPIO_OUT (idx 256)
  ( poke 0x3FF44024 # i32 0x4 )      // GPIO_ENABLE_W1TS_REG:   bit2 -> drive as output
}

@ nurl_led_on  → v { ( poke 0x3FF44008 # i32 0x4 ) }   // GPIO_OUT_W1TS_REG: GPIO2 high
@ nurl_led_off → v { ( poke 0x3FF4400C # i32 0x4 ) }   // GPIO_OUT_W1TC_REG: GPIO2 low
