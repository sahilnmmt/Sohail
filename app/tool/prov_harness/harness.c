/*
 * Device side of ESP-IDF BLE provisioning, running on a PC.
 *
 * Links ESP-IDF's real protocomm session layer, security1 (Curve25519 +
 * AES-256-CTR with a proof-of-possession code) and the wifi_config /
 * wifi_scan endpoint handlers, with a fake Wi-Fi radio behind them. The
 * Flutter app's provisioning client is tested against it, so the app speaks
 * exactly what the robot's firmware speaks.
 *
 * Usage: prov_harness <pop> <correct_wifi_password>
 * stdin, one request per line:   <endpoint> <hex payload>
 * stdout, one response per line: OK <hex payload> | ERR <code>
 * The extra endpoint "harness-state" returns the stored SSID/password as text.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <protocomm.h>
#include <protocomm_security.h>
#include <protocomm_security1.h>
#include <wifi_provisioning/wifi_config.h>
#include <wifi_provisioning/wifi_scan.h>

#define SESSION_ID 0x5011A1

static const char *s_correct_password;
static wifi_prov_config_set_data_t s_config;
static int s_status_polls;
static int s_applied;

/* ---- fake Wi-Fi radio --------------------------------------------------- */

static const struct { const char *ssid; int rssi; uint8_t auth; uint8_t channel; } NETWORKS[] = {
    {"HomeWiFi", -42, 3 /* WPA2_PSK */, 6},
    {"Neighbours-5G", -71, 7 /* WPA2_WPA3_PSK */, 11},
    {"Cafe Free WiFi", -83, 0 /* Open */, 1},
};
#define NETWORK_COUNT (sizeof(NETWORKS) / sizeof(NETWORKS[0]))

static esp_err_t scan_start(bool blocking, bool passive, uint8_t group_channels, uint32_t period_ms,
                            wifi_prov_scan_ctx_t **ctx)
{
    return ESP_OK;
}

static esp_err_t scan_status(bool *finished, uint16_t *count, wifi_prov_scan_ctx_t **ctx)
{
    *finished = true;
    *count = NETWORK_COUNT;
    return ESP_OK;
}

static esp_err_t scan_result(uint16_t index, wifi_prov_scan_result_t *r, wifi_prov_scan_ctx_t **ctx)
{
    if (index >= NETWORK_COUNT) {
        return ESP_FAIL;
    }
    memset(r, 0, sizeof(*r));
    strncpy(r->ssid, NETWORKS[index].ssid, sizeof(r->ssid) - 1);
    memset(r->bssid, 0x10 + index, sizeof(r->bssid));
    r->channel = NETWORKS[index].channel;
    r->rssi = NETWORKS[index].rssi;
    r->auth = NETWORKS[index].auth;
    return ESP_OK;
}

static esp_err_t set_config(const wifi_prov_config_set_data_t *req, wifi_prov_ctx_t **ctx)
{
    s_config = *req;
    s_applied = 0;
    return ESP_OK;
}

static esp_err_t apply_config(wifi_prov_ctx_t **ctx)
{
    s_applied = 1;
    s_status_polls = 0;
    return ESP_OK;
}

static esp_err_t get_status(wifi_prov_config_get_data_t *resp, wifi_prov_ctx_t **ctx)
{
    memset(resp, 0, sizeof(*resp));
    if (!s_applied) {
        resp->wifi_state = WIFI_PROV_STA_DISCONNECTED;
        return ESP_OK;
    }
    if (++s_status_polls < 2) { /* connecting on the first poll, like a real radio */
        resp->wifi_state = WIFI_PROV_STA_CONNECTING;
        return ESP_OK;
    }
    int known = 0;
    for (size_t i = 0; i < NETWORK_COUNT; i++) {
        known |= strcmp(s_config.ssid, NETWORKS[i].ssid) == 0;
    }
    if (!known) {
        resp->wifi_state = WIFI_PROV_STA_DISCONNECTED;
        resp->fail_reason = WIFI_PROV_STA_AP_NOT_FOUND;
    } else if (strcmp(s_config.password, s_correct_password) != 0) {
        resp->wifi_state = WIFI_PROV_STA_DISCONNECTED;
        resp->fail_reason = WIFI_PROV_STA_AUTH_ERROR;
    } else {
        resp->wifi_state = WIFI_PROV_STA_CONNECTED;
        strcpy(resp->conn_info.ip_addr, "192.168.1.57");
        strncpy(resp->conn_info.ssid, s_config.ssid, sizeof(resp->conn_info.ssid) - 1);
        resp->conn_info.channel = 6;
        resp->conn_info.auth_mode = 3;
    }
    return ESP_OK;
}

/* ---- stdin/stdout framing ----------------------------------------------- */

static int hexval(int c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static void reply_ok(const uint8_t *data, ssize_t len)
{
    fputs("OK ", stdout);
    for (ssize_t i = 0; i < len; i++) {
        printf("%02x", data[i]);
    }
    fputc('\n', stdout);
    fflush(stdout);
}

int main(int argc, char **argv)
{
    if (argc != 3) {
        fprintf(stderr, "usage: %s <pop> <correct_wifi_password>\n", argv[0]);
        return 2;
    }
    s_correct_password = argv[2];

    protocomm_t *pc = protocomm_new();
    protocomm_security1_params_t pop = {.data = (const uint8_t *)argv[1], .len = (uint16_t)strlen(argv[1])};
    static wifi_prov_config_handlers_t config_handlers = {
        .get_status_handler = get_status, .set_config_handler = set_config, .apply_config_handler = apply_config};
    static wifi_prov_scan_handlers_t scan_handlers = {
        .scan_start = scan_start, .scan_status = scan_status, .scan_result = scan_result};

    if (!pc || protocomm_set_security(pc, "prov-session", &protocomm_security1, &pop) != ESP_OK ||
        protocomm_add_endpoint(pc, "prov-config", wifi_prov_config_data_handler, &config_handlers) != ESP_OK ||
        protocomm_add_endpoint(pc, "prov-scan", wifi_prov_scan_handler, &scan_handlers) != ESP_OK ||
        protocomm_open_session(pc, SESSION_ID) != ESP_OK) {
        fprintf(stderr, "protocomm setup failed\n");
        return 1;
    }

    static char line[8192];
    static uint8_t buf[4096];
    while (fgets(line, sizeof(line), stdin)) {
        char *sp = strchr(line, ' ');
        char *end = line + strcspn(line, "\r\n");
        *end = '\0';
        if (!sp) {
            sp = end;
        } else {
            *sp++ = '\0';
        }
        if (strcmp(line, "harness-state") == 0) {
            char state[160];
            int n = snprintf(state, sizeof(state), "ssid=%s;password=%s;applied=%d", s_config.ssid,
                             s_config.password, s_applied);
            reply_ok((const uint8_t *)state, n);
            continue;
        }
        ssize_t len = 0;
        for (char *p = sp; p[0] && p[1] && len < (ssize_t)sizeof(buf); p += 2) {
            int hi = hexval(p[0]), lo = hexval(p[1]);
            if (hi < 0 || lo < 0) {
                len = -1;
                break;
            }
            buf[len++] = (uint8_t)(hi << 4 | lo);
        }
        if (len < 0) {
            puts("ERR bad-hex");
            fflush(stdout);
            continue;
        }
        uint8_t *out = NULL;
        ssize_t outlen = 0;
        esp_err_t err = protocomm_req_handle(pc, line, SESSION_ID, buf, len, &out, &outlen);
        if (err != ESP_OK) {
            printf("ERR %d\n", err);
            fflush(stdout);
        } else {
            reply_ok(out, outlen);
        }
        free(out);
    }
    protocomm_delete(pc);
    return 0;
}
