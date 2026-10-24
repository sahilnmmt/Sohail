/* Host stub: just the record type wifi_scan.h sizes its fields from. */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
typedef struct {
    uint8_t bssid[6];
    uint8_t ssid[33];
} wifi_ap_record_t;
