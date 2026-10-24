/* Host stub: security events are reported on stderr instead of an event loop. */
#pragma once
#include <stdio.h>
#include "esp_err.h"
typedef const char *esp_event_base_t;
#define ESP_EVENT_DECLARE_BASE(id) extern esp_event_base_t const id
#define ESP_EVENT_DEFINE_BASE(id) esp_event_base_t const id = #id
#define portMAX_DELAY 0xffffffffu
static inline esp_err_t esp_event_post(esp_event_base_t base, int32_t id, const void *data, size_t size,
                                       unsigned ticks)
{
    (void)data; (void)size; (void)ticks;
    fprintf(stderr, "event %s %d\n", base, (int)id);
    return ESP_OK;
}
