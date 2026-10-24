/*
 * Single-button gesture decoder: short press, double press, hold warning and
 * long (factory-reset) press. Feed it the debounced pin state regularly.
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BUTTON_DEBOUNCE_MS   30
#define BUTTON_DOUBLE_GAP_MS 350  /* max release-to-press gap for a double press */
#define BUTTON_HOLD_MS       3000 /* "keep holding to reset" warning */
#define BUTTON_LONG_MS       10000

typedef enum {
    BUTTON_NONE = 0,
    BUTTON_SHORT,
    BUTTON_DOUBLE,
    BUTTON_HOLD,   /* fired once when a press passes BUTTON_HOLD_MS */
    BUTTON_LONG,   /* fired once when a press passes BUTTON_LONG_MS */
    BUTTON_HOLD_RELEASED, /* released after HOLD but before LONG: cancel */
} button_event_t;

typedef struct {
    bool raw, stable;
    uint32_t raw_since;
    uint32_t press_ms;
    uint32_t release_ms;
    bool hold_sent, long_sent;
    bool pending_short; /* released once, waiting to see if a second press comes */
    bool second_press;
} button_t;

void button_init(button_t *b);
button_event_t button_update(button_t *b, bool pressed, uint32_t now_ms);

#ifdef __cplusplus
}
#endif
