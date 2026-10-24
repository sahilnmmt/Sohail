/*
 * Sohail P0 prototype firmware.
 *
 * Tasks:
 *   robot  - owns the robot_t state machine; every other module talks to it
 *            through app_post() and it calls back out for actions.
 *   ui     - animates and draws the face (ui.c)
 *   input  - button + touch gestures (input.c)
 *   audio  - chimes (audio.c)
 *   plus the ESP-IDF Wi-Fi / provisioning / MQTT tasks (net.c, messaging.c)
 */
#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "nvs_flash.h"

#include "app.h"
#include "audio.h"
#include "display.h"
#include "input.h"
#include "messaging.h"
#include "net.h"
#include "ui.h"

static const char *TAG = "app";

#define ROBOT_TICK_MS 50

static QueueHandle_t s_events;
static char s_device_id[SOHAIL_ID_MAX + 1];

static uint32_t now_ms(void)
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

bool app_post(const robot_event_t *ev)
{
    if (xQueueSend(s_events, ev, pdMS_TO_TICKS(100)) != pdTRUE) {
        ESP_LOGW(TAG, "event queue full, dropped event %d", ev->type);
        return false;
    }
    return true;
}

bool app_post_simple(robot_event_type_t type)
{
    robot_event_t ev = {.type = type};
    return app_post(&ev);
}

const char *app_device_id(void)
{
    return s_device_id;
}

static void run_actions(const robot_actions_t *act)
{
    if (act->flags & ACT_CHIME) {
        audio_play((chime_t)act->chime);
    }
    if (act->flags & ACT_SEND) {
        if (!messaging_send(act->send_type, act->send_emoji)) {
            app_post_simple(EV_SEND_FAILED);
        }
    }
    if (act->flags & ACT_FACTORY_RESET) {
        ESP_LOGW(TAG, "factory reset requested");
        net_factory_reset(); /* does not return */
    }
}

static void robot_task(void *arg)
{
    /* robot_t holds the inbox (~2.5 KB); keep it off the task stack. */
    static robot_t robot;
    static robot_event_t ev;
    robot_init(&robot, s_device_id, now_ms());
    robot_state_t last_state = robot.state;

    for (;;) {
        if (xQueueReceive(s_events, &ev, pdMS_TO_TICKS(ROBOT_TICK_MS)) != pdTRUE) {
            ev.type = EV_TICK;
        }
        robot_actions_t act;
        uint32_t now = now_ms();
        robot_handle(&robot, &ev, now, &act);
        if (robot.state != last_state) {
            ESP_LOGI(TAG, "state %s -> %s", robot_state_name(last_state), robot_state_name(robot.state));
            last_state = robot.state;
        }
        run_actions(&act);

        robot_view_t view;
        robot_view(&robot, now, &view);
        ui_set_view(&view);
    }
}

static void init_nvs(void)
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);
}

void app_main(void)
{
    init_nvs();

    uint8_t mac[6];
    ESP_ERROR_CHECK(esp_read_mac(mac, ESP_MAC_WIFI_STA));
    snprintf(s_device_id, sizeof(s_device_id), "sohail-%02x%02x%02x", mac[3], mac[4], mac[5]);
    ESP_LOGI(TAG, "device id %s, group %s", s_device_id, CONFIG_SOHAIL_GROUP_ID);

    s_events = xQueueCreate(8, sizeof(robot_event_t));
    configASSERT(s_events);

    audio_init();
    ESP_ERROR_CHECK(display_init());
    ui_start();
    input_start();
    xTaskCreate(robot_task, "robot", 6144, NULL, 6, NULL);

    ESP_ERROR_CHECK(messaging_init(s_device_id));
    net_start(messaging_start);
}
