/* Face animation + overlay rendering task. */
#pragma once

#include "sohail/robot.h"

void ui_start(void);
/* Thread-safe: copies the view for the next frame. */
void ui_set_view(const robot_view_t *view);
