/* Chime playback on an I2S amplifier (no-op when the speaker is disabled). */
#pragma once

#include "sohail/chime.h"

void audio_init(void);
/* Non-blocking; drops the request if a backlog is already queued. */
void audio_play(chime_t chime);
