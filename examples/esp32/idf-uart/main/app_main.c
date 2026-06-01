/* app_main.c — entry for the fully-NURL UART echo.
 *
 * The bootloader already brought UART0 up at 115200 (it's the console), so
 * NURL inherits a working port. We hand control to NURL and never come back:
 * nurl_uart_echo() polls the RX FIFO and writes the TX FIFO directly, in an
 * infinite loop. The task watchdog is disabled (sdkconfig.defaults) because
 * this task intentionally owns the CPU with a tight I/O loop.
 */
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"

extern void nurl_uart_echo(void);   /* nurl/nurl_uart.nu + stdlib hal modules */

void app_main(void)
{
    ESP_LOGI("nurl-uart", "handing UART0 to NURL (stdlib/hal/esp32.nu)...");
    vTaskDelay(pdMS_TO_TICKS(50));  /* let the IDF log flush first */
    nurl_uart_echo();               /* never returns */
}
