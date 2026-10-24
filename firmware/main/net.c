#include "net.h"

#include <stdio.h>
#include <string.h>

#include "app.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_netif_sntp.h"
#include "esp_random.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "wifi_provisioning/manager.h"
#include "wifi_provisioning/scheme_ble.h"

static const char *TAG = "net";

#define RETRY_MIN_MS 1000
#define RETRY_MAX_MS 30000

static net_connected_cb_t s_on_first_ip;
static bool s_got_ip_once;
static bool s_provisioning;
static uint32_t s_retry_ms = RETRY_MIN_MS;
static esp_timer_handle_t s_retry_timer;

static void retry_cb(void *arg)
{
    esp_wifi_connect();
}

static void schedule_reconnect(void)
{
    if (s_provisioning) {
        return; /* the provisioning manager drives connection attempts */
    }
    esp_timer_stop(s_retry_timer); /* no-op if not running */
    esp_timer_start_once(s_retry_timer, (uint64_t)s_retry_ms * 1000);
    ESP_LOGI(TAG, "reconnecting in %lu ms", (unsigned long)s_retry_ms);
    s_retry_ms = s_retry_ms * 2 > RETRY_MAX_MS ? RETRY_MAX_MS : s_retry_ms * 2;
}

static void on_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_PROV_EVENT) {
        switch (id) {
        case WIFI_PROV_CRED_RECV:
            ESP_LOGI(TAG, "received Wi-Fi credentials for \"%s\"",
                     (const char *)((wifi_sta_config_t *)data)->ssid);
            break;
        case WIFI_PROV_CRED_FAIL:
            ESP_LOGW(TAG, "provisioning failed: %s",
                     *(wifi_prov_sta_fail_reason_t *)data == WIFI_PROV_STA_AUTH_ERROR
                         ? "wrong password" : "network not found");
            app_post_simple(EV_PROV_FAIL);
            wifi_prov_mgr_reset_sm_state_on_failure(); /* let the app try again */
            break;
        case WIFI_PROV_CRED_SUCCESS:
            ESP_LOGI(TAG, "provisioning successful");
            break;
        case WIFI_PROV_END:
            s_provisioning = false;
            wifi_prov_mgr_deinit();
            break;
        default:
            break;
        }
    } else if (base == WIFI_EVENT) {
        if (id == WIFI_EVENT_STA_START) {
            esp_wifi_connect();
        } else if (id == WIFI_EVENT_STA_DISCONNECTED) {
            app_post_simple(EV_WIFI_DOWN);
            if (s_provisioning) {
                esp_wifi_connect(); /* as in the ESP-IDF wifi_prov_mgr example */
            } else {
                schedule_reconnect();
            }
        }
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *ev = (ip_event_got_ip_t *)data;
        ESP_LOGI(TAG, "got IP " IPSTR, IP2STR(&ev->ip_info.ip));
        s_retry_ms = RETRY_MIN_MS;
        app_post_simple(EV_WIFI_UP);
        if (!s_got_ip_once) {
            s_got_ip_once = true;
            esp_sntp_config_t sntp = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
            esp_netif_sntp_init(&sntp);
            if (s_on_first_ip) {
                s_on_first_ip();
            }
        }
    }
}

static void start_provisioning(void)
{
    uint8_t mac[6];
    char service_name[24];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    /* Espressif's ESP BLE Provisioning apps only list names starting "PROV_". */
    snprintf(service_name, sizeof(service_name), "PROV_SOHAIL_%02X%02X", mac[4], mac[5]);

    /* Proof-of-possession: shown on the robot's screen, typed into the app.
     * A fresh random code each time means only someone looking at this
     * robot can provision it. */
    robot_event_t ev = {.type = EV_PROV_START};
    snprintf(ev.prov_code, sizeof(ev.prov_code), "%06lu", (unsigned long)(esp_random() % 1000000));

    s_provisioning = true;
    ESP_LOGI(TAG, "starting BLE provisioning as %s", service_name);
    ESP_ERROR_CHECK(wifi_prov_mgr_start_provisioning(WIFI_PROV_SECURITY_1, ev.prov_code, service_name, NULL));
    app_post(&ev);
}

void net_start(net_connected_cb_t on_first_ip)
{
    s_on_first_ip = on_first_ip;

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_PROV_EVENT, ESP_EVENT_ANY_ID, on_event, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, on_event, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, on_event, NULL));

    esp_timer_create_args_t timer = {.callback = retry_cb, .name = "wifi_retry"};
    ESP_ERROR_CHECK(esp_timer_create(&timer, &s_retry_timer));

    esp_netif_create_default_wifi_sta();
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    wifi_prov_mgr_config_t prov_cfg = {
        .scheme = wifi_prov_scheme_ble,
        /* Frees BT memory once provisioning ends; re-provisioning goes
         * through a factory reset + reboot anyway. */
        .scheme_event_handler = WIFI_PROV_SCHEME_BLE_EVENT_HANDLER_FREE_BTDM,
    };
    ESP_ERROR_CHECK(wifi_prov_mgr_init(prov_cfg));

    bool provisioned = false;
    ESP_ERROR_CHECK(wifi_prov_mgr_is_provisioned(&provisioned));
    if (provisioned) {
        ESP_LOGI(TAG, "credentials found, connecting");
        wifi_prov_mgr_deinit();
        ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
        ESP_ERROR_CHECK(esp_wifi_start());
    } else {
        start_provisioning();
    }
}

void net_factory_reset(void)
{
    esp_wifi_restore(); /* clears stored credentials */
    ESP_LOGW(TAG, "credentials erased, rebooting into setup mode");
    esp_restart();
}
