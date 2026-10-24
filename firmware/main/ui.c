#include "ui.h"

#include <string.h>

#include "display.h"
#include "esp_log.h"
#include "esp_random.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "sdkconfig.h"
#include "sohail/face.h"
#include "sohail/gfx.h"

#define W CONFIG_SOHAIL_LCD_WIDTH
#define H CONFIG_SOHAIL_LCD_HEIGHT
#define FRAME_MS 40 /* 25 fps; a full 240x280 frame takes ~27 ms at 40 MHz SPI */

#define COLOR_TEXT   0xFFFF
#define COLOR_DIM    0x9CF3
#define COLOR_GREEN  0x07E0
#define COLOR_AMBER  0xFD20
#define COLOR_RED    0xF800

#define BODY_SCALE   2
#define BODY_CHARS   ((W - 16) / (GFX_FONT_ADVANCE * BODY_SCALE))
#define BODY_LINES   4

static SemaphoreHandle_t s_lock;
static robot_view_t s_view;

void ui_set_view(const robot_view_t *view)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_view = *view;
    xSemaphoreGive(s_lock);
}

typedef struct {
    char lines[BODY_LINES][BODY_CHARS + 1];
    int count;
    char src[sizeof(((robot_view_t *)0)->body)];
} wrapped_t;

static void draw_overlay(const gfx_band_t *b, const robot_view_t *v, const wrapped_t *body)
{
    if (v->title[0]) {
        gfx_text_centered(b, 14, 2, COLOR_TEXT, v->title);
    }

    uint16_t dot = v->cloud_up ? COLOR_GREEN : v->wifi_up ? COLOR_AMBER : COLOR_RED;
    gfx_fill_circle(b, W - 14, 20, 4, dot);

    int y = (int)(H * 0.70f);
    if (v->show_code && v->code[0]) {
        gfx_text_centered(b, y, 5, COLOR_TEXT, v->code);
        y += GFX_FONT_H * 5 + 10;
        gfx_text_centered(b, y, 1, COLOR_DIM, v->body);
        return;
    }
    for (int i = 0; i < body->count; i++) {
        gfx_text_centered(b, y, BODY_SCALE, i ? COLOR_DIM : COLOR_TEXT, body->lines[i]);
        y += GFX_FONT_H * BODY_SCALE + 4;
    }
}

static void ui_task(void *arg)
{
    face_anim_t anim;
    face_anim_init(&anim, FACE_THINKING, esp_random());
    static wrapped_t body; /* re-wrapped only when the text changes */
    robot_view_t view;
    TickType_t wake = xTaskGetTickCount();

    for (;;) {
        xSemaphoreTake(s_lock, portMAX_DELAY);
        view = s_view;
        xSemaphoreGive(s_lock);

        if (strcmp(body.src, view.body) != 0) {
            strcpy(body.src, view.body);
            body.count = gfx_wrap(view.body, BODY_CHARS, &body.lines[0][0], BODY_LINES);
        }

        face_frame_t frame;
        face_anim_set(&anim, view.face);
        face_anim_step(&anim, (uint32_t)(esp_timer_get_time() / 1000), &frame);

        for (int y = 0; y < H; y += DISPLAY_BAND_ROWS) {
            int rows = H - y < DISPLAY_BAND_ROWS ? H - y : DISPLAY_BAND_ROWS;
            uint16_t *band = display_acquire_band();
            face_render_band(&frame, band, W, H, y, rows, true);
            gfx_band_t b = {.buf = band, .width = W, .y0 = y, .rows = rows, .swap_bytes = true};
            draw_overlay(&b, &view, &body);
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
    xTaskCreatePinnedToCore(ui_task, "ui", 6144, NULL, 4, NULL, 1);
}
