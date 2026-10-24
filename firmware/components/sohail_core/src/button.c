#include "sohail/button.h"

#include <string.h>

void button_init(button_t *b)
{
    memset(b, 0, sizeof(*b));
}

button_event_t button_update(button_t *b, bool pressed, uint32_t now_ms)
{
    if (pressed != b->raw) {
        b->raw = pressed;
        b->raw_since = now_ms;
    }

    if (b->raw != b->stable && now_ms - b->raw_since >= BUTTON_DEBOUNCE_MS) {
        b->stable = b->raw;
        if (b->stable) {
            b->press_ms = now_ms;
            b->hold_sent = b->long_sent = false;
            b->second_press = b->pending_short && now_ms - b->release_ms <= BUTTON_DOUBLE_GAP_MS;
            b->pending_short = false;
        } else {
            b->release_ms = now_ms;
            if (b->long_sent) {
                return BUTTON_NONE;
            }
            if (b->hold_sent) {
                return BUTTON_HOLD_RELEASED;
            }
            if (b->second_press) {
                b->second_press = false;
                return BUTTON_DOUBLE;
            }
            b->pending_short = true;
        }
        return BUTTON_NONE;
    }

    if (b->stable) {
        uint32_t held = now_ms - b->press_ms;
        if (!b->long_sent && held >= BUTTON_LONG_MS) {
            b->long_sent = true;
            return BUTTON_LONG;
        }
        if (!b->hold_sent && held >= BUTTON_HOLD_MS) {
            b->hold_sent = true;
            b->second_press = false;
            return BUTTON_HOLD;
        }
    } else if (b->pending_short && now_ms - b->release_ms > BUTTON_DOUBLE_GAP_MS) {
        b->pending_short = false;
        return BUTTON_SHORT;
    }
    return BUTTON_NONE;
}
