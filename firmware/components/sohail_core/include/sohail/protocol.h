/*
 * Sohail device message protocol (v1).
 *
 * Messages are small JSON objects carried over MQTT. See
 * docs/04-device-protocol.md for the wire format and topic layout.
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SOHAIL_PROTO_VERSION 1
#define SOHAIL_ID_MAX        24  /* device / message / group id, chars */
#define SOHAIL_NAME_MAX      16  /* display name, bytes */
#define SOHAIL_TEXT_MAX      140 /* text body, bytes */
#define SOHAIL_TOPIC_MAX     80

typedef enum {
    SOHAIL_MSG_NUDGE = 0,
    SOHAIL_MSG_EMOJI,
    SOHAIL_MSG_TEXT,
} sohail_msg_type_t;

typedef enum {
    SOHAIL_EMOJI_HAPPY = 0,
    SOHAIL_EMOJI_LOVE,
    SOHAIL_EMOJI_LAUGH,
    SOHAIL_EMOJI_SAD,
    SOHAIL_EMOJI_WOW,
    SOHAIL_EMOJI_SLEEPY,
    SOHAIL_EMOJI_COUNT,
} sohail_emoji_t;

typedef struct {
    char id[SOHAIL_ID_MAX + 1];
    char from[SOHAIL_ID_MAX + 1];
    char name[SOHAIL_NAME_MAX + 1];
    sohail_msg_type_t type;
    sohail_emoji_t emoji;           /* valid when type == SOHAIL_MSG_EMOJI */
    char text[SOHAIL_TEXT_MAX + 1]; /* valid when type == SOHAIL_MSG_TEXT */
    uint32_t ts;                    /* unix seconds, 0 if sender had no clock */
} sohail_msg_t;

typedef enum {
    SOHAIL_OK = 0,
    SOHAIL_ERR_ARG,
    SOHAIL_ERR_PARSE,
    SOHAIL_ERR_VERSION,
    SOHAIL_ERR_FIELD,
    SOHAIL_ERR_NOMEM,
} sohail_err_t;

/* Ids may only contain [A-Za-z0-9_-] so they are safe inside MQTT topics. */
bool sohail_id_valid(const char *id);

const char *sohail_emoji_name(sohail_emoji_t emoji);
bool sohail_emoji_from_name(const char *name, sohail_emoji_t *out);
const char *sohail_msg_type_name(sohail_msg_type_t type);

/* Returns bytes written (excluding NUL), or -1 on error / buffer too small. */
int sohail_msg_encode(const sohail_msg_t *msg, char *buf, size_t buf_len);
sohail_err_t sohail_msg_decode(const char *json, size_t len, sohail_msg_t *out);

/* Topic builders. Return false if an id is invalid or the buffer is too small. */
bool sohail_topic_device_inbox(char *buf, size_t len, const char *device_id);
bool sohail_topic_device_status(char *buf, size_t len, const char *device_id);
bool sohail_topic_group_inbox(char *buf, size_t len, const char *group_id);

#ifdef __cplusplus
}
#endif
