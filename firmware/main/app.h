/* Shared declarations between the firmware modules. */
#pragma once

#include <stdbool.h>

#include "sohail/protocol.h"
#include "sohail/robot.h"

/* Post an event to the robot task. Safe from any task (not from ISRs). */
bool app_post(const robot_event_t *ev);
bool app_post_simple(robot_event_type_t type);

/* This robot's id, e.g. "sohail-a1b2c3". Valid after app_main starts. */
const char *app_device_id(void);
