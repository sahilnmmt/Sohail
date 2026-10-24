#include "messaging.h"

#include <stdio.h>
#include <string.h>
#include <time.h>

#include "app.h"
#include "esp_crt_bundle.h"
#include "esp_log.h"
#include "esp_random.h"
#include "mqtt_client.h"
#include "sdkconfig.h"

static const char *TAG = "msg";

#define MSG_MAX_BYTES 1024
#define CLOCK_VALID_AFTER 1700000000 /* SNTP has synced if time() is past this */

static esp_mqtt_client_handle_t s_client;
static char s_device_id[SOHAIL_ID_MAX + 1];
static char s_topic_inbox[SOHAIL_TOPIC_MAX];
static char s_topic_group[SOHAIL_TOPIC_MAX];
static char s_topic_status[SOHAIL_TOPIC_MAX];

/* Reassembly buffer for messages split across MQTT_EVENT_DATA events. Only
 * touched from the MQTT task. */
static char s_rx[MSG_MAX_BYTES];
static int s_rx_len;
static bool s_rx_drop;

static void handle_message(const char *data, int len)
{
    robot_event_t ev = {.type = EV_MSG};
    sohail_err_t err = sohail_msg_decode(data, (size_t)len, &ev.msg);
    if (err != SOHAIL_OK) {
        ESP_LOGW(TAG, "ignoring malformed message (err %d)", err);
        return;
    }
    ESP_LOGI(TAG, "%s from %s", sohail_msg_type_name(ev.msg.type), ev.msg.from);
    app_post(&ev);
}

static void on_data(esp_mqtt_event_handle_t e)
{
    if (e->current_data_offset == 0) {
        s_rx_len = 0;
        s_rx_drop = e->total_data_len > MSG_MAX_BYTES;
        if (s_rx_drop) {
            ESP_LOGW(TAG, "dropping %d byte message", e->total_data_len);
        }
    }
    if (s_rx_drop || s_rx_len + e->data_len > MSG_MAX_BYTES) {
        s_rx_drop = true; /* also guards against a fragment arriving without its start */
        return;
    }
    memcpy(s_rx + s_rx_len, e->data, e->data_len);
    s_rx_len += e->data_len;
    if (s_rx_len == e->total_data_len) {
        handle_message(s_rx, s_rx_len);
    }
}

static void on_mqtt_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    esp_mqtt_event_handle_t e = data;
    switch ((esp_mqtt_event_id_t)id) {
    case MQTT_EVENT_CONNECTED:
        ESP_LOGI(TAG, "connected to broker");
        esp_mqtt_client_subscribe_single(s_client, s_topic_inbox, 1);
        esp_mqtt_client_subscribe_single(s_client, s_topic_group, 1);
        esp_mqtt_client_publish(s_client, s_topic_status, "online", 0, 1, 1);
        app_post_simple(EV_CLOUD_UP);
        break;
    case MQTT_EVENT_DISCONNECTED:
        ESP_LOGW(TAG, "disconnected from broker");
        app_post_simple(EV_CLOUD_DOWN);
        break;
    case MQTT_EVENT_DATA:
        on_data(e);
        break;
    case MQTT_EVENT_ERROR:
        if (e->error_handle->error_type == MQTT_ERROR_TYPE_CONNECTION_REFUSED) {
            ESP_LOGE(TAG, "broker refused connection (code %d): check username/password",
                     (int)e->error_handle->connect_return_code);
        } else {
            ESP_LOGW(TAG, "mqtt error type %d", e->error_handle->error_type);
        }
        break;
    default:
        break;
    }
}

esp_err_t messaging_init(const char *device_id)
{
    snprintf(s_device_id, sizeof(s_device_id), "%s", device_id);
    if (!sohail_topic_device_inbox(s_topic_inbox, sizeof(s_topic_inbox), device_id) ||
        !sohail_topic_device_status(s_topic_status, sizeof(s_topic_status), device_id) ||
        !sohail_topic_group_inbox(s_topic_group, sizeof(s_topic_group), CONFIG_SOHAIL_GROUP_ID)) {
        ESP_LOGE(TAG, "invalid device or group id (use letters, digits, '-' and '_')");
        return ESP_ERR_INVALID_ARG;
    }

    esp_mqtt_client_config_t cfg = {
        .broker.address.uri = CONFIG_SOHAIL_MQTT_URI,
        .credentials.client_id = s_device_id,
        .session.last_will = {
            .topic = s_topic_status,
            .msg = "offline",
            .qos = 1,
            .retain = 1,
        },
        .session.keepalive = 30,
    };
    if (strncmp(CONFIG_SOHAIL_MQTT_URI, "mqtts://", 8) == 0) {
        cfg.broker.verification.crt_bundle_attach = esp_crt_bundle_attach;
    }
    if (CONFIG_SOHAIL_MQTT_USERNAME[0]) {
        cfg.credentials.username = CONFIG_SOHAIL_MQTT_USERNAME;
        cfg.credentials.authentication.password = CONFIG_SOHAIL_MQTT_PASSWORD;
    }

    s_client = esp_mqtt_client_init(&cfg);
    if (!s_client) {
        return ESP_FAIL;
    }
    return esp_mqtt_client_register_event(s_client, ESP_EVENT_ANY_ID, on_mqtt_event, NULL);
}

void messaging_start(void)
{
    ESP_LOGI(TAG, "connecting to %s", CONFIG_SOHAIL_MQTT_URI);
    ESP_ERROR_CHECK(esp_mqtt_client_start(s_client));
}

bool messaging_send(sohail_msg_type_t type, sohail_emoji_t emoji)
{
    sohail_msg_t m = {.type = type, .emoji = emoji};
    snprintf(m.id, sizeof(m.id), "%08lx%08lx", (unsigned long)esp_random(), (unsigned long)esp_random());
    snprintf(m.from, sizeof(m.from), "%s", s_device_id);
    snprintf(m.name, sizeof(m.name), "%s", CONFIG_SOHAIL_DEVICE_NAME);
    time_t now = time(NULL);
    m.ts = now > CLOCK_VALID_AFTER ? (uint32_t)now : 0;

    char buf[512];
    int len = sohail_msg_encode(&m, buf, sizeof(buf));
    if (len < 0) {
        ESP_LOGE(TAG, "encode failed");
        return false;
    }
    /* enqueue never blocks the robot task; QoS 1 is retried by the client. */
    int id = esp_mqtt_client_enqueue(s_client, s_topic_group, buf, len, 1, 0, true);
    if (id < 0) {
        ESP_LOGW(TAG, "could not queue message");
        return false;
    }
    ESP_LOGI(TAG, "queued %s (%s)", sohail_msg_type_name(type), m.id);
    return true;
}
