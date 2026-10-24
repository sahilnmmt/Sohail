/* Short synthesised notification sounds (no audio assets needed). */
#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    CHIME_MESSAGE = 0, /* rising two-note "ding-dong" */
    CHIME_SENT,        /* quick high blip */
    CHIME_ERROR,       /* low falling tone */
    CHIME_HAPPY,       /* little arpeggio when petted */
    CHIME_BOOT,
    CHIME_COUNT,
} chime_t;

/* Number of samples the chime needs at sample_rate. */
size_t chime_length(chime_t chime, uint32_t sample_rate);

/*
 * Render up to max_samples mono 16-bit samples, starting at sample offset
 * start (so long chimes can be rendered in chunks). volume is 0..100.
 * Returns the number of samples written.
 */
size_t chime_render(chime_t chime, uint32_t sample_rate, uint8_t volume,
                    size_t start, int16_t *out, size_t max_samples);

#ifdef __cplusplus
}
#endif
