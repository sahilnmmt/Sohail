/* MQTT link to the broker: group + direct inbox, presence, sending. */
#pragma once

#include <stdbool.h>

#include "esp_err.h"
#include "sohail/protocol.h"

esp_err_t messaging_init(const char *device_id);
/* Connects to the broker; the client reconnects by itself afterwards. */
void messaging_start(void);
/* Queues a nudge or emoji for the group. False if it could not be queued. */
bool messaging_send(sohail_msg_type_t type, sohail_emoji_t emoji);
