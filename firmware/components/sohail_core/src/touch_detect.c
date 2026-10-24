#include "sohail/touch_detect.h"

#include <string.h>

#define TOUCH_WARMUP_SAMPLES 16

void touch_detect_init(touch_detect_t *t, uint8_t threshold_pct)
{
    memset(t, 0, sizeof(*t));
    t->threshold_pct = threshold_pct ? threshold_pct : 1;
}

bool touch_detect_update(touch_detect_t *t, uint32_t raw)
{
    float v = (float)raw;
    if (t->samples < TOUCH_WARMUP_SAMPLES) {
        /* Average the first samples to get a starting baseline. */
        t->baseline = (t->baseline * t->samples + v) / (float)(t->samples + 1);
        t->samples++;
        return false;
    }

    float on = t->baseline * (1.0f + t->threshold_pct / 100.0f);
    float off = t->baseline * (1.0f + t->threshold_pct / 200.0f);
    bool was = t->touched;
    if (!t->touched && v > on) {
        t->touched = true;
    } else if (t->touched && v < off) {
        t->touched = false;
    }
    if (!t->touched) {
        /* Track slow drift (temperature, humidity) only while untouched. */
        t->baseline += (v - t->baseline) * 0.01f;
    }
    return t->touched && !was;
}
