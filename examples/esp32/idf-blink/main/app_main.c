/* app_main.c — thin C entry for the NURL-on-ESP32 blink.
 *
 * All GPIO hardware access lives in NURL (nurl/nurl_blink.nu, compiled to a
 * Xtensa object with esp-clang and linked in via main/CMakeLists.txt). C
 * only supplies the FreeRTOS-friendly delay and the app_main entry + a
 * serial log so you can watch the NURL code run even with no LED on GPIO2.
 */
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"

/* Implemented in NURL (nurl/nurl_blink.nu): */
extern int  nurl_ping(void);
extern void nurl_led_setup(void);
extern void nurl_led_on(void);
extern void nurl_led_off(void);

static const char *TAG = "nurl-blink";

void app_main(void)
{
    ESP_LOGI(TAG, "NURL on ESP32 (Xtensa) — GPIO driven by NURL via esp-clang");
    ESP_LOGI(TAG, "nurl_ping() = %d  (C->NURL windowed cross-call OK)", nurl_ping());

    nurl_led_setup();            /* NURL: IO_MUX + GPIO_ENABLE, raw registers */

    bool on = false;
    for (;;) {
        on = !on;
        if (on) nurl_led_on();   /* NURL: GPIO_OUT_W1TS poke */
        else    nurl_led_off();  /* NURL: GPIO_OUT_W1TC poke */
        ESP_LOGI(TAG, "GPIO2 %s  <- poke() from NURL", on ? "HIGH" : "LOW");
        vTaskDelay(pdMS_TO_TICKS(150));   /* ~3 Hz, clearly visible */
    }
}
