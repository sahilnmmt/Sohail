/*
 * Capacitive touch detector with a slowly tracking baseline and hysteresis.
 * On the ESP32-S3 the raw reading rises when the pad is touched.
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float baseline;
    uint8_t threshold_pct; /* touched when raw > baseline * (1 + pct/100) */
    bool touched;
    uint16_t samples;
} touch_detect_t;

void touch_detect_init(touch_detect_t *t, uint8_t threshold_pct);
/* Returns true on the transition from released to touched. */
bool touch_detect_update(touch_detect_t *t, uint32_t raw);

#ifdef __cplusplus
}
#endif
