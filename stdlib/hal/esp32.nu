// stdlib/hal/esp32.nu — bare-metal register HAL for the classic ESP32 (Xtensa).
//
// Pure NURL over memory-mapped registers (built on stdlib/hal/mmio.nu). No
// ESP-IDF, no FFI — just the physical register addresses from the ESP32 TRM
// (cross-checked against ESP-IDF soc/{gpio,io_mux,uart}_reg.h).
//
// Addresses are written in decimal with the hex in a comment: nurlc accepts
// 0x.. literals, but nurlfmt currently splits them ("0x10" -> "0 x10"), so
// shipped stdlib stays decimal to survive the formatter round-trip gate.
//
// GPIO:
//   ( esp32_gpio_enable_output i mask ) → v   drive these pins as outputs
//   ( esp32_gpio_set           i mask ) → v   set pins high
//   ( esp32_gpio_clear         i mask ) → v   set pins low
//
// UART0 (the chip's USB-serial console):
//   ( esp32_uart_tx_count ) → i   bytes currently queued in the TX FIFO
//   ( esp32_uart_rx_count ) → i   bytes available in the RX FIFO
//   ( esp32_uart_putc  i ch ) → v blocking: wait for room, push one byte
//   ( esp32_uart_getc       ) → i blocking: wait for a byte, return 0..255
//   ( esp32_uart_puts  s str ) → v write a NUL-terminated string
//
// NOTE: esp32_uart_putc/getc spin on an MMIO status read. That is safe at
// any optimization level — stdlib/hal/mmio.nu emits `load volatile` /
// `store volatile`, which LICM will not hoist out of the spin loop. (This
// note used to say NURL had no `volatile` and to build at -O0/-O1; the
// volatile intrinsics have since landed and that restriction is gone.)
// See examples/esp32/idf-uart.

$ `stdlib/hal/mmio.nu`

// ── GPIO (DR_REG_GPIO_BASE = 0x3FF44000) ──────────────────────────────
: i GPIO_OUT_W1TS_REG 1072971784  // 0x3FF44008
: i GPIO_OUT_W1TC_REG 1072971788  // 0x3FF4400C
: i GPIO_ENABLE_W1TS_REG 1072971812  // 0x3FF44024

@ esp32_gpio_enable_output i mask → v { ( mmio_write32 GPIO_ENABLE_W1TS_REG # i32 mask ) }

@ esp32_gpio_set i mask → v { ( mmio_write32 GPIO_OUT_W1TS_REG # i32 mask ) }

@ esp32_gpio_clear i mask → v { ( mmio_write32 GPIO_OUT_W1TC_REG # i32 mask ) }

// ── UART0 (DR_REG_UART_BASE = 0x3FF40000) ─────────────────────────────
//  TX writes go to the APB FIFO; RX reads come from the AHB-mapped FIFO at
//  0x60000000 (reading RX over APB hits an ESP32 silicon erratum).
: i UART0_FIFO_REG 1072955392  // 0x3FF40000  write byte -> TX FIFO
: i UART0_FIFO_AHB_REG 1610612736  // 0x60000000  read byte  <- RX FIFO
: i UART0_STATUS_REG 1072955420  // 0x3FF4001C  [23:16]=TXFIFO_CNT [7:0]=RXFIFO_CNT

@ esp32_uart_tx_count → i { ^ & >> ( mmio_read32 UART0_STATUS_REG ) 16 255 }

@ esp32_uart_rx_count → i { ^ & ( mmio_read32 UART0_STATUS_REG ) 255 }

@ esp32_uart_putc i ch → v {
    ~ >= ( esp32_uart_tx_count ) 126 {}  // wait until the TX FIFO has room
    ( mmio_write32 UART0_FIFO_REG # i32 ch )
}

@ esp32_uart_getc → i {
    ~ == ( esp32_uart_rx_count ) 0 {}  // wait until a byte arrives
    ^ & ( mmio_read32 UART0_FIFO_AHB_REG ) 255
}

@ esp32_uart_puts s str → v {
    : *u p # *u str
    : ~ i i 0
    ~ != # i . p i 0 {
        ( esp32_uart_putc # i . p i )
        = i + i 1
    }
}
