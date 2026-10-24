/* Wi-Fi station + BLE provisioning + SNTP. */
#pragma once

typedef void (*net_connected_cb_t)(void);

/*
 * Starts Wi-Fi. If no credentials are stored, starts BLE provisioning and
 * posts EV_PROV_START with a random code for the ESP BLE Provisioning app.
 * on_first_ip runs once, the first time the station gets an IP address.
 */
void net_start(net_connected_cb_t on_first_ip);

/* Erases Wi-Fi credentials and reboots into provisioning. Does not return. */
void net_factory_reset(void);
