#include "sohail/protocol.h"
#include "test.h"

static sohail_msg_t make(sohail_msg_type_t type)
{
    sohail_msg_t m = {0};
    strcpy(m.id, "m-01");
    strcpy(m.from, "sohail-a1b2c3");
    strcpy(m.name, "Grandma");
    m.type = type;
    m.ts = 1761300000u;
    return m;
}

static void roundtrip_all_types(void)
{
    for (int t = SOHAIL_MSG_NUDGE; t <= SOHAIL_MSG_TEXT; t++) {
        sohail_msg_t in = make((sohail_msg_type_t)t), out;
        in.emoji = SOHAIL_EMOJI_WOW;
        strcpy(in.text, "Dinner at 7 \"sharp\"\nlove you");
        char buf[512];
        int n = sohail_msg_encode(&in, buf, sizeof(buf));
        CHECK(n > 0);
        CHECK_EQ_INT(sohail_msg_decode(buf, (size_t)n, &out), SOHAIL_OK);
        CHECK_STR(out.id, in.id);
        CHECK_STR(out.from, in.from);
        CHECK_STR(out.name, in.name);
        CHECK_EQ_INT(out.type, in.type);
        CHECK_EQ_INT(out.ts, in.ts);
        if (t == SOHAIL_MSG_EMOJI) {
            CHECK_EQ_INT(out.emoji, SOHAIL_EMOJI_WOW);
        }
        if (t == SOHAIL_MSG_TEXT) {
            CHECK_STR(out.text, in.text);
        }
    }
}

static void encode_rejects_bad_input(void)
{
    char buf[512];
    sohail_msg_t m = make(SOHAIL_MSG_NUDGE);
    strcpy(m.from, "bad/id");
    CHECK_EQ_INT(sohail_msg_encode(&m, buf, sizeof(buf)), -1);

    m = make(SOHAIL_MSG_TEXT); /* empty text */
    CHECK_EQ_INT(sohail_msg_encode(&m, buf, sizeof(buf)), -1);

    m = make(SOHAIL_MSG_EMOJI);
    m.emoji = SOHAIL_EMOJI_COUNT;
    CHECK_EQ_INT(sohail_msg_encode(&m, buf, sizeof(buf)), -1);

    m = make(SOHAIL_MSG_NUDGE);
    CHECK_EQ_INT(sohail_msg_encode(&m, buf, 10), -1); /* buffer too small */
}

static void decode_accepts_external_json(void)
{
    /* As produced by tools/sohail_cli.py (key order and spacing differ). */
    const char *j = "{\"type\": \"emoji\", \"emoji\": \"love\", \"from\": \"cli-1\", "
                    "\"id\": \"abc123\", \"v\": 1}";
    sohail_msg_t m;
    CHECK_EQ_INT(sohail_msg_decode(j, strlen(j), &m), SOHAIL_OK);
    CHECK_EQ_INT(m.type, SOHAIL_MSG_EMOJI);
    CHECK_EQ_INT(m.emoji, SOHAIL_EMOJI_LOVE);
    CHECK_STR(m.name, "");
    CHECK_EQ_INT(m.ts, 0);
}

static void decode_rejects_bad_messages(void)
{
    const char *bad[] = {
        "",
        "not json",
        "[1,2]",
        "{\"v\":2,\"id\":\"a\",\"from\":\"b\",\"type\":\"nudge\"}",           /* version */
        "{\"id\":\"a\",\"from\":\"b\",\"type\":\"nudge\"}",                   /* no version */
        "{\"v\":1,\"from\":\"b\",\"type\":\"nudge\"}",                        /* no id */
        "{\"v\":1,\"id\":\"a\",\"from\":\"b/#\",\"type\":\"nudge\"}",         /* topic chars */
        "{\"v\":1,\"id\":\"a\",\"from\":\"b\",\"type\":\"call\"}",            /* type */
        "{\"v\":1,\"id\":\"a\",\"from\":\"b\",\"type\":\"emoji\",\"emoji\":\"x\"}",
        "{\"v\":1,\"id\":\"a\",\"from\":\"b\",\"type\":\"text\"}",            /* no text */
        "{\"v\":1,\"id\":\"a\",\"from\":\"b\",\"type\":\"text\",\"text\":\"\"}",
        "{\"v\":1,\"id\":\"a\",\"from\":\"b\",\"type\":\"text\",\"text\":\"a\\u0007b\"}",
        "{\"v\":1,\"id\":\"a\",\"from\":\"b\",\"type\":\"nudge\",\"ts\":-5}",
        "{\"v\":1,\"id\":\"a\",\"from\":\"b\",\"type\":\"nudge\",\"name\":\"this name is far too long\"}",
        "{\"v\":1,\"id\":7,\"from\":\"b\",\"type\":\"nudge\"}",
    };
    for (size_t i = 0; i < sizeof(bad) / sizeof(bad[0]); i++) {
        sohail_msg_t m;
        sohail_err_t err = sohail_msg_decode(bad[i], strlen(bad[i]), &m);
        if (err == SOHAIL_OK) {
            fprintf(stderr, "accepted bad message #%zu: %s\n", i, bad[i]);
        }
        CHECK(err != SOHAIL_OK);
        CHECK_STR(m.id, ""); /* output cleared on failure */
    }

    char longtext[400] = "{\"v\":1,\"id\":\"a\",\"from\":\"b\",\"type\":\"text\",\"text\":\"";
    size_t n = strlen(longtext);
    memset(longtext + n, 'x', SOHAIL_TEXT_MAX + 1);
    strcpy(longtext + n + SOHAIL_TEXT_MAX + 1, "\"}");
    sohail_msg_t m;
    CHECK(sohail_msg_decode(longtext, strlen(longtext), &m) != SOHAIL_OK);
}

static void ids_and_topics(void)
{
    CHECK(sohail_id_valid("sohail-a1b2c3"));
    CHECK(sohail_id_valid("A_b-9"));
    CHECK(!sohail_id_valid(""));
    CHECK(!sohail_id_valid(NULL));
    CHECK(!sohail_id_valid("a+b"));
    CHECK(!sohail_id_valid("a/b"));
    CHECK(!sohail_id_valid("a#"));
    CHECK(!sohail_id_valid("1234567890123456789012345")); /* 25 chars */
    CHECK(sohail_id_valid("123456789012345678901234"));   /* 24 chars */

    char t[SOHAIL_TOPIC_MAX];
    CHECK(sohail_topic_device_inbox(t, sizeof(t), "sohail-a1b2c3"));
    CHECK_STR(t, "sohail/v1/dev/sohail-a1b2c3/inbox");
    CHECK(sohail_topic_device_status(t, sizeof(t), "x"));
    CHECK_STR(t, "sohail/v1/dev/x/status");
    CHECK(sohail_topic_group_inbox(t, sizeof(t), "family"));
    CHECK_STR(t, "sohail/v1/group/family/inbox");
    CHECK(!sohail_topic_group_inbox(t, sizeof(t), "fam/+"));
    CHECK(!sohail_topic_group_inbox(t, 10, "family"));

    sohail_emoji_t e;
    CHECK(sohail_emoji_from_name("sleepy", &e) && e == SOHAIL_EMOJI_SLEEPY);
    CHECK(!sohail_emoji_from_name("Sleepy", &e));
    CHECK(sohail_emoji_name(SOHAIL_EMOJI_COUNT) == NULL);
}

int main(void)
{
    RUN(roundtrip_all_types);
    RUN(encode_rejects_bad_input);
    RUN(decode_accepts_external_json);
    RUN(decode_rejects_bad_messages);
    RUN(ids_and_topics);
    TEST_EXIT();
}
