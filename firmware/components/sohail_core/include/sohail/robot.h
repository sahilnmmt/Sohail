/*
 * Robot behaviour state machine.
 *
 * Pure logic: it consumes events (network status, incoming messages, button
 * and touch gestures, time) and produces actions (send a message, play a
 * chime, factory reset) plus a view describing what the screen should show.
 * The firmware owns one robot_t in a single task; nothing here is thread-safe.
 */
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "sohail/face.h"
#include "sohail/protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

#define ROBOT_INBOX_LEN     8
#define ROBOT_SEEN_IDS      16
#define ROBOT_CONNECT_TIMEOUT_MS 20000 /* then fall back to offline companion mode */
#define ROBOT_SLEEP_AFTER_MS     (5u * 60u * 1000u)
#define ROBOT_SHOW_MS            6000
#define ROBOT_SHOW_TEXT_MS       10000
#define ROBOT_REACT_MS           2000
#define ROBOT_PICK_TIMEOUT_MS    8000
#define ROBOT_REMIND_MS          (2u * 60u * 1000u)
#define ROBOT_TITLE_MAX          (SOHAIL_ID_MAX + 8) /* fits a full sender id */

typedef enum {
    ROBOT_BOOT = 0,
    ROBOT_PROVISIONING, /* waiting for Wi-Fi credentials over BLE */
    ROBOT_CONNECTING,   /* have credentials, waiting for Wi-Fi + cloud */
    ROBOT_IDLE,
    ROBOT_NOTIFY,       /* unread message(s) waiting for a touch */
    ROBOT_SHOWING,      /* playing a message */
    ROBOT_PICK,         /* choosing an emoji reaction to send */
    ROBOT_SLEEP,
} robot_state_t;

typedef enum {
    EV_TICK = 0,
    EV_PROV_START,   /* not provisioned: BLE provisioning started */
    EV_PROV_FAIL,    /* credentials rejected by the access point */
    EV_WIFI_UP,
    EV_WIFI_DOWN,
    EV_CLOUD_UP,
    EV_CLOUD_DOWN,
    EV_MSG,          /* .msg is valid */
    EV_BTN_SHORT,
    EV_BTN_DOUBLE,
    EV_BTN_HOLD,
    EV_BTN_HOLD_RELEASED,
    EV_BTN_LONG,
    EV_TOUCH,
    EV_SEND_FAILED,
} robot_event_type_t;

typedef struct {
    robot_event_type_t type;
    sohail_msg_t msg;  /* EV_MSG */
    char prov_code[8]; /* EV_PROV_START: code the user types into the app */
} robot_event_t;

enum {
    ACT_SEND        = 1u << 0, /* send action.send_type / send_emoji to the group */
    ACT_CHIME       = 1u << 1, /* play action.chime */
    ACT_FACTORY_RESET = 1u << 2,
};

typedef struct {
    uint32_t flags;
    sohail_msg_type_t send_type;
    sohail_emoji_t send_emoji;
    int chime; /* chime_t */
} robot_actions_t;

typedef struct {
    face_expr_t face;
    char title[ROBOT_TITLE_MAX]; /* small line at the top, may be empty */
    char body[SOHAIL_TEXT_MAX + 1]; /* large text under the face, may be empty */
    bool show_code;   /* draw code prominently */
    char code[8];
    bool wifi_up, cloud_up;
    uint8_t unread;
} robot_view_t;

typedef struct {
    robot_state_t state;
    uint32_t state_since;
    uint32_t last_activity;
    bool wifi_up, cloud_up;
    bool offline_mode; /* connect timed out; acting as a local companion */

    char self_id[SOHAIL_ID_MAX + 1];
    char prov_code[8];

    sohail_msg_t inbox[ROBOT_INBOX_LEN];
    uint8_t inbox_head, inbox_count;
    uint32_t dropped;

    char seen[ROBOT_SEEN_IDS][SOHAIL_ID_MAX + 1];
    uint8_t seen_next;

    sohail_msg_t showing;
    uint32_t last_remind;

    /* Transient reaction (petting, "sent!", errors) shown over idle. */
    face_expr_t react_face;
    char react_title[ROBOT_TITLE_MAX];
    uint32_t react_until;
    bool reacting;

    sohail_emoji_t pick;
    bool reset_warning;
} robot_t;

void robot_init(robot_t *r, const char *self_id, uint32_t now_ms);
void robot_handle(robot_t *r, const robot_event_t *ev, uint32_t now_ms, robot_actions_t *act);
void robot_view(const robot_t *r, uint32_t now_ms, robot_view_t *view);
const char *robot_state_name(robot_state_t s);

/* Face shown for a received emoji. */
face_expr_t robot_emoji_face(sohail_emoji_t e);

#ifdef __cplusplus
}
#endif
