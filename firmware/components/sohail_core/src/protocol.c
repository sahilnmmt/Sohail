#include "sohail/protocol.h"

#include <stdio.h>
#include <string.h>

#include "cJSON.h"

static const char *const EMOJI_NAMES[SOHAIL_EMOJI_COUNT] = {
    "happy", "love", "laugh", "sad", "wow", "sleepy",
};

static const char *const TYPE_NAMES[] = {"nudge", "emoji", "text"};

bool sohail_id_valid(const char *id)
{
    if (!id) {
        return false;
    }
    size_t n = 0;
    for (const char *p = id; *p; p++, n++) {
        char c = *p;
        bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') || c == '_' || c == '-';
        if (!ok || n >= SOHAIL_ID_MAX) {
            return false;
        }
    }
    return n > 0;
}

const char *sohail_emoji_name(sohail_emoji_t emoji)
{
    return (unsigned)emoji < SOHAIL_EMOJI_COUNT ? EMOJI_NAMES[emoji] : NULL;
}

bool sohail_emoji_from_name(const char *name, sohail_emoji_t *out)
{
    if (!name) {
        return false;
    }
    for (int i = 0; i < SOHAIL_EMOJI_COUNT; i++) {
        if (strcmp(name, EMOJI_NAMES[i]) == 0) {
            *out = (sohail_emoji_t)i;
            return true;
        }
    }
    return false;
}

const char *sohail_msg_type_name(sohail_msg_type_t type)
{
    return (unsigned)type <= SOHAIL_MSG_TEXT ? TYPE_NAMES[type] : NULL;
}

static bool name_valid(const char *name)
{
    size_t n = strlen(name);
    if (n > SOHAIL_NAME_MAX) {
        return false;
    }
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)name[i];
        if (c < 0x20 || c == 0x7f) {
            return false;
        }
    }
    return true;
}

static bool text_valid(const char *text)
{
    size_t n = strlen(text);
    if (n == 0 || n > SOHAIL_TEXT_MAX) {
        return false;
    }
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)text[i];
        if (c < 0x20 && c != '\n') {
            return false;
        }
    }
    return true;
}

int sohail_msg_encode(const sohail_msg_t *msg, char *buf, size_t buf_len)
{
    if (!msg || !buf || buf_len == 0 || !sohail_id_valid(msg->id) ||
        !sohail_id_valid(msg->from) || !name_valid(msg->name)) {
        return -1;
    }
    const char *type = sohail_msg_type_name(msg->type);
    if (!type) {
        return -1;
    }

    cJSON *root = cJSON_CreateObject();
    if (!root) {
        return -1;
    }
    cJSON_AddNumberToObject(root, "v", SOHAIL_PROTO_VERSION);
    cJSON_AddStringToObject(root, "id", msg->id);
    cJSON_AddStringToObject(root, "from", msg->from);
    if (msg->name[0]) {
        cJSON_AddStringToObject(root, "name", msg->name);
    }
    cJSON_AddStringToObject(root, "type", type);
    if (msg->type == SOHAIL_MSG_EMOJI) {
        const char *emoji = sohail_emoji_name(msg->emoji);
        if (!emoji) {
            cJSON_Delete(root);
            return -1;
        }
        cJSON_AddStringToObject(root, "emoji", emoji);
    } else if (msg->type == SOHAIL_MSG_TEXT) {
        if (!text_valid(msg->text)) {
            cJSON_Delete(root);
            return -1;
        }
        cJSON_AddStringToObject(root, "text", msg->text);
    }
    cJSON_AddNumberToObject(root, "ts", msg->ts);

    bool ok = cJSON_PrintPreallocated(root, buf, (int)buf_len, false);
    cJSON_Delete(root);
    if (!ok) {
        return -1;
    }
    return (int)strlen(buf);
}

/* Copies a string member into dst. Missing members are allowed only when
 * required is false; dst is then left empty. */
static bool copy_str(const cJSON *root, const char *key, char *dst, size_t dst_size, bool required)
{
    const cJSON *item = cJSON_GetObjectItemCaseSensitive(root, key);
    if (!item) {
        dst[0] = '\0';
        return !required;
    }
    if (!cJSON_IsString(item) || strlen(item->valuestring) >= dst_size) {
        return false;
    }
    strcpy(dst, item->valuestring);
    return true;
}

sohail_err_t sohail_msg_decode(const char *json, size_t len, sohail_msg_t *out)
{
    if (!json || !out) {
        return SOHAIL_ERR_ARG;
    }
    memset(out, 0, sizeof(*out));

    cJSON *root = cJSON_ParseWithLength(json, len);
    if (!root) {
        return SOHAIL_ERR_PARSE;
    }
    sohail_err_t err = SOHAIL_ERR_FIELD;

    const cJSON *v = cJSON_GetObjectItemCaseSensitive(root, "v");
    if (!cJSON_IsObject(root)) {
        err = SOHAIL_ERR_PARSE;
        goto done;
    }
    if (!cJSON_IsNumber(v) || v->valuedouble != SOHAIL_PROTO_VERSION) {
        err = SOHAIL_ERR_VERSION;
        goto done;
    }

    char type[8];
    if (!copy_str(root, "id", out->id, sizeof(out->id), true) || !sohail_id_valid(out->id) ||
        !copy_str(root, "from", out->from, sizeof(out->from), true) || !sohail_id_valid(out->from) ||
        !copy_str(root, "name", out->name, sizeof(out->name), false) || !name_valid(out->name) ||
        !copy_str(root, "type", type, sizeof(type), true)) {
        goto done;
    }

    if (strcmp(type, "nudge") == 0) {
        out->type = SOHAIL_MSG_NUDGE;
    } else if (strcmp(type, "emoji") == 0) {
        char emoji[12];
        out->type = SOHAIL_MSG_EMOJI;
        if (!copy_str(root, "emoji", emoji, sizeof(emoji), true) ||
            !sohail_emoji_from_name(emoji, &out->emoji)) {
            goto done;
        }
    } else if (strcmp(type, "text") == 0) {
        out->type = SOHAIL_MSG_TEXT;
        if (!copy_str(root, "text", out->text, sizeof(out->text), true) || !text_valid(out->text)) {
            goto done;
        }
    } else {
        goto done;
    }

    const cJSON *ts = cJSON_GetObjectItemCaseSensitive(root, "ts");
    if (ts) {
        if (!cJSON_IsNumber(ts) || ts->valuedouble < 0 || ts->valuedouble > 4294967295.0) {
            goto done;
        }
        out->ts = (uint32_t)ts->valuedouble;
    }
    err = SOHAIL_OK;

done:
    cJSON_Delete(root);
    if (err != SOHAIL_OK) {
        memset(out, 0, sizeof(*out));
    }
    return err;
}

static bool build_topic(char *buf, size_t len, const char *fmt, const char *id)
{
    if (!buf || !sohail_id_valid(id)) {
        return false;
    }
    int n = snprintf(buf, len, fmt, id);
    return n > 0 && (size_t)n < len;
}

bool sohail_topic_device_inbox(char *buf, size_t len, const char *device_id)
{
    return build_topic(buf, len, "sohail/v1/dev/%s/inbox", device_id);
}

bool sohail_topic_device_status(char *buf, size_t len, const char *device_id)
{
    return build_topic(buf, len, "sohail/v1/dev/%s/status", device_id);
}

bool sohail_topic_group_inbox(char *buf, size_t len, const char *group_id)
{
    return build_topic(buf, len, "sohail/v1/group/%s/inbox", group_id);
}
