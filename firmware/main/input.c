#include "input.h"

#include "app.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "sdkconfig.h"
#include "sohail/button.h"

#if CONFIG_SOHAIL_TOUCH_ENABLE
#include "driver/touch_pad.h"
#include "sohail/touch_detect.h"
#endif

static const char *TAG = "input";

#define POLL_MS 10

#if CONFIG_SOHAIL_TOUCH_ENABLE
#define TOUCH_EVERY 2 /* read the pad every 20 ms */

static void touch_init(void)
{
    ESP_ERROR_CHECK(touch_pad_init());
    ESP_ERROR_CHECK(touch_pad_config(CONFIG_SOHAIL_TOUCH_PAD));
    touch_pad_denoise_t denoise = {
        .grade = TOUCH_PAD_DENOISE_BIT4,
        .cap_level = TOUCH_PAD_DENOISE_CAP_L4,
    };
    touch_pad_denoise_set_config(&denoise);
    touch_pad_denoise_enable();
    ESP_ERROR_CHECK(touch_pad_set_fsm_mode(TOUCH_FSM_MODE_TIMER));
    ESP_ERROR_CHECK(touch_pad_fsm_start());
}
#endif

static void input_task(void *arg)
{
    button_t btn;
    button_init(&btn);
#if CONFIG_SOHAIL_TOUCH_ENABLE
    touch_detect_t touch;
    touch_detect_init(&touch, CONFIG_SOHAIL_TOUCH_THRESHOLD_PCT);
    vTaskDelay(pdMS_TO_TICKS(100)); /* let the first measurements land */
    unsigned tick = 0;
#endif

    TickType_t wake = xTaskGetTickCount();
    for (;;) {
        uint32_t now = (uint32_t)(esp_timer_get_time() / 1000);
        bool pressed = gpio_get_level(CONFIG_SOHAIL_PIN_BUTTON) == 0;

        static const robot_event_type_t MAP[] = {
            [BUTTON_SHORT] = EV_BTN_SHORT,
            [BUTTON_DOUBLE] = EV_BTN_DOUBLE,
            [BUTTON_HOLD] = EV_BTN_HOLD,
            [BUTTON_LONG] = EV_BTN_LONG,
            [BUTTON_HOLD_RELEASED] = EV_BTN_HOLD_RELEASED,
        };
        button_event_t be = button_update(&btn, pressed, now);
        if (be != BUTTON_NONE) {
            app_post_simple(MAP[be]);
        }

#if CONFIG_SOHAIL_TOUCH_ENABLE
        if (++tick % TOUCH_EVERY == 0) {
            uint32_t raw = 0;
            if (touch_pad_read_raw_data(CONFIG_SOHAIL_TOUCH_PAD, &raw) == ESP_OK &&
                touch_detect_update(&touch, raw)) {
                app_post_simple(EV_TOUCH);
            }
        }
#endif
        xTaskDelayUntil(&wake, pdMS_TO_TICKS(POLL_MS));
    }
}

void input_start(void)
{
    gpio_config_t io = {
        .pin_bit_mask = 1ULL << CONFIG_SOHAIL_PIN_BUTTON,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    ESP_ERROR_CHECK(gpio_config(&io));
#if CONFIG_SOHAIL_TOUCH_ENABLE
    touch_init();
    ESP_LOGI(TAG, "touch pad %d enabled", CONFIG_SOHAIL_TOUCH_PAD);
#endif
    ESP_LOGI(TAG, "button on GPIO%d", CONFIG_SOHAIL_PIN_BUTTON);
    xTaskCreate(input_task, "input", 3072, NULL, 5, NULL);
}
