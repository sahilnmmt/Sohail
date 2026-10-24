/*
 * Virtual Sohail robot: the real robot state machine and screen renderer with
 * time, network and input supplied by the caller. Used by the scripted test
 * run (host_tests/test_scenario.c) and the browser preview (sim/web).
 */
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "sohail/robot.h"

#define SIM_W 240
#define SIM_H 280
#define SIM_SAMPLE_RATE 16000

void sim_init(uint32_t seed, uint32_t now_ms);
/* Device id used for this robot's messages and to ignore its own echoes
 * (default "sohail-sim001"). Call before sim_init. False if invalid. */
bool sim_set_identity(const char *device_id, const char *name);
/* Decode a message as received over MQTT with the firmware's decoder and
 * deliver it. Returns the action flags, or -1 if the robot rejects it. */
int sim_receive_json(const char *json, size_t len, uint32_t now_ms);
/* Encode the most recent ACT_SEND as the firmware would publish it.
 * Returns the JSON length, or -1. */
int sim_encode_last_send(const char *msg_id, uint32_t unix_ts, char *out, size_t out_len);
/* Simple events (robot_event_type_t). Returns the action flags produced. */
uint32_t sim_post(int type, uint32_t now_ms);
uint32_t sim_start_provisioning(const char *code, uint32_t now_ms);
/* Deliver a message from another robot (sohail_msg_type_t / sohail_emoji_t). */
uint32_t sim_receive(int type, int emoji, const char *name, const char *text, uint32_t now_ms);
uint32_t sim_tick(uint32_t now_ms);

/* Details of the most recent actions. */
int sim_last_chime(void);
int sim_last_send_type(void);
int sim_last_send_emoji(void);

/* Render a frame into the framebuffer (SIM_W * SIM_H RGB565, native order). */
void sim_render(uint32_t now_ms);
uint16_t *sim_framebuffer(void);

const robot_t *sim_robot(void);
const char *sim_state_name(void);
