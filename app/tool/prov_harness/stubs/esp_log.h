/* Host stub: ESP-IDF logging goes to stderr when PROV_HARNESS_VERBOSE is set. */
#pragma once
#include <stdio.h>
#include <stdlib.h>
static inline int harness_verbose(void) { return getenv("PROV_HARNESS_VERBOSE") != NULL; }
#define HLOG(lvl, tag, fmt, ...) do { if (harness_verbose()) fprintf(stderr, lvl " (%s) " fmt "\n", tag, ##__VA_ARGS__); } while (0)
#define ESP_LOGE(tag, fmt, ...) HLOG("E", tag, fmt, ##__VA_ARGS__)
#define ESP_LOGW(tag, fmt, ...) HLOG("W", tag, fmt, ##__VA_ARGS__)
#define ESP_LOGI(tag, fmt, ...) HLOG("I", tag, fmt, ##__VA_ARGS__)
#define ESP_LOGD(tag, fmt, ...) HLOG("D", tag, fmt, ##__VA_ARGS__)
#define ESP_LOGV(tag, fmt, ...) HLOG("V", tag, fmt, ##__VA_ARGS__)
#define ESP_LOG_BUFFER_HEX_LEVEL(tag, buf, len, level) ((void)0)
#define ESP_LOG_BUFFER_HEXDUMP(tag, buf, len, level) ((void)0)
#define ESP_LOG_DEBUG 4
#define ESP_LOG_VERBOSE 5
