#include "sohail/touch_detect.h"
#include "test.h"

static void detects_touch_with_hysteresis(void)
{
    touch_detect_t t;
    touch_detect_init(&t, 5);
    for (int i = 0; i < 30; i++) CHECK(!touch_detect_update(&t, 20000));
    CHECK(touch_detect_update(&t, 21500));  /* +7.5 %: press */
    CHECK(!touch_detect_update(&t, 21500)); /* edge only once */
    CHECK(!touch_detect_update(&t, 20700)); /* +3.5 %: still held (hysteresis) */
    CHECK(t.touched);
    CHECK(!touch_detect_update(&t, 20100)); /* released */
    CHECK(!t.touched);
    CHECK(touch_detect_update(&t, 21500));
}

static void baseline_tracks_drift(void)
{
    touch_detect_t t;
    touch_detect_init(&t, 5);
    uint32_t v = 20000;
    for (int i = 0; i < 2000; i++) { /* slow 10 % drift must not register */
        if (i % 20 == 0) v += 20;
        CHECK(!touch_detect_update(&t, v));
    }
    CHECK(t.baseline > 21500);
}

int main(void)
{
    RUN(detects_touch_with_hysteresis);
    RUN(baseline_tracks_drift);
    TEST_EXIT();
}
