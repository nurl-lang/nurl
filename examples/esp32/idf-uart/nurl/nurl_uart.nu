// nurl_uart.nu — a fully NURL-driven UART echo for the classic ESP32 (Xtensa).
//
// Uses the new hardware HAL: stdlib/hal/esp32.nu (UART0 over MMIO) which in
// turn builds on stdlib/hal/mmio.nu. No ESP-IDF UART driver, no FFI — NURL
// polls the RX FIFO and writes the TX FIFO directly through device registers.
//
// The whole read-echo cycle lives in NURL: C's app_main just calls this once
// and it never returns. The FIFO-status spin loops are now safe at any
// optimization level: stdlib/hal/mmio.nu reads/writes via the compiler's
// `volatile_load` / `volatile_store` intrinsics, so the optimizer never
// hoists an MMIO poll out of its loop (the former -O0 workaround is gone).

$ `stdlib/hal/esp32.nu`

@ nurl_uart_echo → v {
    ( esp32_uart_puts `\r\n=== NURL UART echo on ESP32 (Xtensa) ===\r\n` )
    ( esp32_uart_puts `Type characters - NURL reads RX and echoes TX.\r\n> ` )

    ~ > 1 0 {  // forever
        : i c ( esp32_uart_getc )  // blocking read from RX FIFO
        ? == c 13  // Enter pressed?
        ( esp32_uart_puts `\r\n> ` )  //   yes: newline + fresh prompt
        ( esp32_uart_putc c )  //   no : echo the byte to TX FIFO
    }
}
