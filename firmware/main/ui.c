#include "ui.h"

#include <string.h>

#include "display.h"
#include "esp_random.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "sdkconfig.h"
#include "sohail/screen.h"

#define W CONFIG_SOHAIL_LCD_WIDTH
#define H CONFIG_SOHAIL_LCD_HEIGHT
#define FRAME_MS 40 /* 25 fps; a full 240x280 frame takes ~27 ms at 40 MHz SPI */

static SemaphoreHandle_t s_lock;
static robot_view_t s_view;

void ui_set_view(const robot_view_t *view)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_view = *view;
    xSemaphoreGive(s_lock);
}

static void ui_task(void *arg)
{
    static screen_t screen; /* ~1.5 KB: keep it off the task stack */
    screen_init(&screen, W, H, esp_random());
    robot_view_t view;
    TickType_t wake = xTaskGetTickCount();

    for (;;) {
        xSemaphoreTake(s_lock, portMAX_DELAY);
        view = s_view;
        xSemaphoreGive(s_lock);

        screen_begin_frame(&screen, &view, (uint32_t)(esp_timer_get_time() / 1000));
        for (int y = 0; y < H; y += DISPLAY_BAND_ROWS) {
            int rows = H - y < DISPLAY_BAND_ROWS ? H - y : DISPLAY_BAND_ROWS;
            uint16_t *band = display_acquire_band();
            screen_render_band(&screen, band, y, rows, true);
            display_submit_band(band, y, rows);
        }
        xTaskDelayUntil(&wake, pdMS_TO_TICKS(FRAME_MS));
    }
}

void ui_start(void)
{
    s_lock = xSemaphoreCreateMutex();
    configASSERT(s_lock);
    s_view.face = FACE_THINKING;
    strcpy(s_view.title, "Starting...");
    /* Pinned to core 1 so rendering never stalls the Wi-Fi/BLE stacks on core 0. */
    xTaskCreatePinnedToCore(ui_task, "ui", 4096, NULL, 4, NULL, 1);
}
