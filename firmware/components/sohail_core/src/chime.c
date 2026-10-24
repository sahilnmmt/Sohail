#include "sohail/chime.h"

#include <math.h>

typedef struct {
    float freq;   /* Hz, 0 = rest */
    uint16_t ms;
} note_t;

#define MAX_NOTES 4

static const struct {
    uint8_t count;
    note_t notes[MAX_NOTES];
} CHIMES[CHIME_COUNT] = {
    [CHIME_MESSAGE] = {2, {{784.0f, 150}, {1046.5f, 260}}},
    [CHIME_SENT]    = {1, {{1318.5f, 90}}},
    [CHIME_ERROR]   = {2, {{392.0f, 160}, {261.6f, 260}}},
    [CHIME_HAPPY]   = {3, {{1046.5f, 80}, {1318.5f, 80}, {1568.0f, 140}}},
    [CHIME_BOOT]    = {3, {{523.3f, 100}, {659.3f, 100}, {784.0f, 180}}},
};

static size_t note_samples(const note_t *n, uint32_t sr)
{
    return (size_t)n->ms * sr / 1000u;
}

size_t chime_length(chime_t chime, uint32_t sample_rate)
{
    if ((unsigned)chime >= CHIME_COUNT) {
        return 0;
    }
    size_t total = 0;
    for (int i = 0; i < CHIMES[chime].count; i++) {
        total += note_samples(&CHIMES[chime].notes[i], sample_rate);
    }
    return total;
}

size_t chime_render(chime_t chime, uint32_t sample_rate, uint8_t volume,
                    size_t start, int16_t *out, size_t max_samples)
{
    if ((unsigned)chime >= CHIME_COUNT || sample_rate == 0) {
        return 0;
    }
    if (volume > 100) {
        volume = 100;
    }
    const float amp = 12000.0f * (float)volume / 100.0f;
    size_t written = 0;
    size_t note_start = 0;

    for (int i = 0; i < CHIMES[chime].count && written < max_samples; i++) {
        const note_t *n = &CHIMES[chime].notes[i];
        size_t len = note_samples(n, sample_rate);
        size_t attack = sample_rate / 200; /* 5 ms, avoids clicks */
        for (size_t s = 0; s < len && written < max_samples; s++) {
            size_t pos = note_start + s;
            if (pos < start + written) {
                continue;
            }
            /* Short linear attack, exponential decay: a soft bell. */
            float env = s < attack ? (float)s / (float)attack : 1.0f;
            env *= expf(-3.0f * (float)s / (float)len);
            float t = (float)s / (float)sample_rate;
            float v = n->freq > 0 ? sinf(6.2831853f * n->freq * t) : 0.0f;
            out[written++] = (int16_t)(v * env * amp);
        }
        note_start += len;
    }
    return written;
}
