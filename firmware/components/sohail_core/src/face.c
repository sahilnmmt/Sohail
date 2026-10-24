#include "sohail/face.h"

#include <math.h>
#include <stddef.h>
#include <string.h>

/*                      eye_w eye_h  rad  spc   y    tilt  smile heart mw    mh    open  r     g     b */
static const face_params_t PRESETS[FACE_COUNT] = {
    [FACE_NEUTRAL]  = {0.25f, 0.34f, 0.30f, 0.46f, 0.42f, 0.00f, 0.00f, 0.0f, 0.00f, 0.00f, 0.0f, 0.35f, 0.90f, 1.00f},
    [FACE_HAPPY]    = {0.27f, 0.28f, 0.45f, 0.46f, 0.42f, 0.00f, 0.75f, 0.0f, 0.18f, 0.07f, 0.0f, 0.40f, 0.95f, 0.80f},
    [FACE_LOVE]     = {0.30f, 0.30f, 0.30f, 0.48f, 0.42f, 0.00f, 0.00f, 1.0f, 0.12f, 0.05f, 0.0f, 1.00f, 0.35f, 0.60f},
    [FACE_LAUGH]    = {0.27f, 0.24f, 0.45f, 0.46f, 0.40f, 0.00f, 0.85f, 0.0f, 0.26f, 0.16f, 0.0f, 1.00f, 0.85f, 0.30f},
    [FACE_SAD]      = {0.23f, 0.28f, 0.30f, 0.46f, 0.45f, 0.45f, 0.00f, 0.0f, 0.00f, 0.00f, 0.0f, 0.40f, 0.55f, 1.00f},
    [FACE_WOW]      = {0.24f, 0.38f, 1.00f, 0.46f, 0.40f, 0.00f, 0.00f, 0.0f, 0.10f, 0.12f, 1.0f, 1.00f, 1.00f, 1.00f},
    [FACE_SLEEPY]   = {0.25f, 0.05f, 0.50f, 0.46f, 0.48f, 0.10f, 0.00f, 0.0f, 0.00f, 0.00f, 0.0f, 0.30f, 0.45f, 0.80f},
    [FACE_EXCITED]  = {0.28f, 0.38f, 0.55f, 0.46f, 0.40f, 0.00f, 0.00f, 0.0f, 0.20f, 0.12f, 0.0f, 1.00f, 0.80f, 0.20f},
    [FACE_THINKING] = {0.22f, 0.26f, 0.35f, 0.46f, 0.42f, -0.15f, 0.00f, 0.0f, 0.00f, 0.00f, 0.0f, 0.60f, 0.60f, 1.00f},
};

static const char *const NAMES[FACE_COUNT] = {
    "neutral", "happy", "love", "laugh", "sad", "wow", "sleepy", "excited", "thinking",
};

const face_params_t *face_preset(face_expr_t expr)
{
    return &PRESETS[(unsigned)expr < FACE_COUNT ? expr : FACE_NEUTRAL];
}

const char *face_expr_name(face_expr_t expr)
{
    return (unsigned)expr < FACE_COUNT ? NAMES[expr] : "?";
}

/* xorshift32: small, deterministic, good enough for idle motion. */
static uint32_t rnd(face_anim_t *a)
{
    uint32_t x = a->rng;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    a->rng = x;
    return x;
}

static float rnd_range(face_anim_t *a, float lo, float hi)
{
    return lo + (hi - lo) * (float)(rnd(a) % 10000u) / 10000.0f;
}

void face_anim_init(face_anim_t *a, face_expr_t initial, uint32_t seed)
{
    memset(a, 0, sizeof(*a));
    a->target = initial;
    a->cur = *face_preset(initial);
    a->rng = seed ? seed : 0x5011A1u;
}

void face_anim_set(face_anim_t *a, face_expr_t expr)
{
    a->target = (unsigned)expr < FACE_COUNT ? expr : FACE_NEUTRAL;
}

static float approach(float cur, float target, float k)
{
    return cur + (target - cur) * k;
}

void face_anim_step(face_anim_t *a, uint32_t now_ms, face_frame_t *out)
{
    if (!a->started) {
        a->started = true;
        a->last_ms = now_ms;
        a->next_blink_ms = now_ms + 1500;
        a->next_gaze_ms = now_ms + 1000;
    }
    uint32_t dt = now_ms - a->last_ms;
    if (dt > 500) {
        dt = 500;
    }
    a->last_ms = now_ms;

    /* Ease every parameter towards the preset with a ~120 ms time constant. */
    const face_params_t *t = face_preset(a->target);
    float k = 1.0f - expf(-(float)dt / 120.0f);
    float *c = (float *)&a->cur;
    const float *tp = (const float *)t;
    for (size_t i = 0; i < sizeof(face_params_t) / sizeof(float); i++) {
        c[i] = approach(c[i], tp[i], k);
    }
    /* Hearts are a shape swap, not a blend, so switch straight away. */
    a->cur.heart = t->heart;

    bool sleepy = a->target == FACE_SLEEPY;

    /* Blink: 140 ms close/open every 2-6 s, never while asleep. */
    float blink = 0.0f;
    if (!sleepy) {
        if ((int32_t)(now_ms - a->next_blink_ms) >= 0) {
            a->blink_start_ms = now_ms;
            a->next_blink_ms = now_ms + (uint32_t)rnd_range(a, 2000, 6000);
        }
        uint32_t since = now_ms - a->blink_start_ms;
        if (a->blink_start_ms && since < 140) {
            float ph = (float)since / 140.0f;
            blink = ph < 0.5f ? ph * 2.0f : (1.0f - ph) * 2.0f;
        }
    }

    /* Gaze: occasional saccades; thinking looks up and to the side. */
    if ((int32_t)(now_ms - a->next_gaze_ms) >= 0) {
        if (a->target == FACE_THINKING) {
            a->gaze_tx = (rnd(a) & 1) ? 0.7f : -0.7f;
            a->gaze_ty = -0.6f;
        } else if (sleepy || (rnd(a) % 3) == 0) {
            a->gaze_tx = 0.0f;
            a->gaze_ty = 0.0f;
        } else {
            a->gaze_tx = rnd_range(a, -0.8f, 0.8f);
            a->gaze_ty = rnd_range(a, -0.5f, 0.5f);
        }
        a->next_gaze_ms = now_ms + (uint32_t)rnd_range(a, 800, 3000);
    }
    float gk = 1.0f - expf(-(float)dt / 60.0f);
    a->gaze_x = approach(a->gaze_x, a->gaze_tx, gk);
    a->gaze_y = approach(a->gaze_y, a->gaze_ty, gk);

    float bob = 0.0f;
    float tsec = (float)now_ms / 1000.0f;
    if (a->target == FACE_EXCITED || a->target == FACE_LAUGH) {
        bob = -fabsf(sinf(tsec * 7.0f)) * 8.0f;
    } else if (sleepy) {
        bob = sinf(tsec * 1.5f) * 3.0f; /* slow breathing */
    }

    out->p = a->cur;
    out->blink = blink;
    out->gaze_x = a->gaze_x;
    out->gaze_y = a->gaze_y;
    out->bob = bob;
}

/* ---- rendering ---------------------------------------------------------- */

typedef struct {
    float cx, cy, hw, hh, r; /* centre, half extents, corner radius (px) */
    float tilt, smile;
    float inner;            /* +1 if the inner side is +x (left eye), -1 otherwise */
    bool heart;
} eye_geom_t;

static bool inside_round_rect(float px, float py, const eye_geom_t *e)
{
    float qx = fabsf(px - e->cx) - (e->hw - e->r);
    float qy = fabsf(py - e->cy) - (e->hh - e->r);
    float ox = qx > 0 ? qx : 0;
    float oy = qy > 0 ? qy : 0;
    float in = (qx > qy ? qx : qy);
    float d = sqrtf(ox * ox + oy * oy) + (in < 0 ? in : 0) - e->r;
    return d <= 0.0f;
}

static bool inside_heart(float px, float py, const eye_geom_t *e)
{
    /* (x^2 + y^2 - 1)^3 - x^2 y^3 <= 0, y up, scaled to the eye box. */
    float s = e->hw > e->hh ? e->hw : e->hh;
    float x = (px - e->cx) / (s * 0.85f);
    float y = -(py - e->cy) / (s * 0.85f) + 0.15f;
    float a = x * x + y * y - 1.0f;
    return a * a * a - x * x * y * y * y <= 0.0f;
}

static bool inside_eye(float px, float py, const eye_geom_t *e)
{
    if (e->heart) {
        return inside_heart(px, py, e);
    }
    if (!inside_round_rect(px, py, e)) {
        return false;
    }
    float u = (px - e->cx) / e->hw; /* -1..1 across the eye */
    if (e->tilt != 0.0f) {
        /* Slanted upper lid: lowered towards the inner (tilt > 0) side. */
        float side = (u * e->inner + 1.0f) * 0.5f; /* 0 outer .. 1 inner */
        float s = e->tilt > 0 ? side : 1.0f - side;
        float cut = e->cy - e->hh + fabsf(e->tilt) * 2.0f * e->hh * s * 0.6f;
        if (py < cut) {
            return false;
        }
    }
    if (e->smile > 0.0f) {
        /* Lower lid pushed up in the middle: ^ ^ eyes. */
        float bottom = e->cy + e->hh - e->smile * 2.0f * e->hh * (1.0f - u * u);
        if (py > bottom) {
            return false;
        }
    }
    return true;
}

static void eye_bounds(const eye_geom_t *e, int screen_w, int y0, int y1, int *x0, int *x1, int *ey0, int *ey1)
{
    float s = e->heart ? (e->hw > e->hh ? e->hw : e->hh) * 1.2f : 0.0f;
    float hw = e->heart ? s : e->hw;
    float hh = e->heart ? s : e->hh;
    *x0 = (int)floorf(e->cx - hw) - 1;
    *x1 = (int)ceilf(e->cx + hw) + 1;
    *ey0 = (int)floorf(e->cy - hh) - 1;
    *ey1 = (int)ceilf(e->cy + hh) + 1;
    if (*x0 < 0) *x0 = 0;
    if (*x1 > screen_w) *x1 = screen_w;
    if (*ey0 < y0) *ey0 = y0;
    if (*ey1 > y1) *ey1 = y1;
}

static inline uint16_t px_out(uint16_t c, bool swap)
{
    return swap ? (uint16_t)((c >> 8) | (c << 8)) : c;
}

static uint8_t to8(float v)
{
    if (v <= 0.0f) return 0;
    if (v >= 1.0f) return 255;
    return (uint8_t)(v * 255.0f + 0.5f);
}

void face_render_band(const face_frame_t *f, uint16_t *buf, int screen_w, int screen_h,
                      int y0, int rows, bool swap_bytes)
{
    const face_params_t *p = &f->p;
    int y1 = y0 + rows;
    float W = (float)screen_w, H = (float)screen_h;

    memset(buf, 0, (size_t)screen_w * (size_t)rows * sizeof(uint16_t)); /* black is 0 either way */

    uint16_t color = px_out(face_rgb565(to8(p->r), to8(p->g), to8(p->b)), swap_bytes);

    float hw = p->eye_w * W * 0.5f;
    float hh = p->eye_h * W * 0.5f * (1.0f - 0.9f * f->blink);
    if (hh < 1.5f) hh = 1.5f;
    float r = p->radius * (hw < hh ? hw : hh);
    float gx = f->gaze_x * W * 0.06f;
    float gy = f->gaze_y * H * 0.05f;
    float cy = p->y * H + gy + f->bob;

    for (int side = 0; side < 2; side++) {
        eye_geom_t e = {
            .cx = W * 0.5f + (side ? 0.5f : -0.5f) * p->spacing * W + gx,
            .cy = cy,
            .hw = hw,
            .hh = hh,
            .r = r,
            .tilt = p->tilt,
            .smile = p->smile_lid,
            .inner = side ? -1.0f : 1.0f,
            .heart = p->heart > 0.5f,
        };
        if (e.heart && f->blink > 0.5f) {
            e.heart = false; /* hearts "blink" as flat eyes */
        }
        int x0, x1, ey0, ey1;
        eye_bounds(&e, screen_w, y0, y1, &x0, &x1, &ey0, &ey1);
        for (int y = ey0; y < ey1; y++) {
            uint16_t *row = buf + (size_t)(y - y0) * screen_w;
            for (int x = x0; x < x1; x++) {
                if (inside_eye((float)x + 0.5f, (float)y + 0.5f, &e)) {
                    row[x] = color;
                }
            }
        }
    }

    if (p->mouth_h > 0.01f && p->mouth_w > 0.01f) {
        float mcx = W * 0.5f + gx * 0.5f;
        float mcy = cy + p->eye_h * W * 0.5f + p->mouth_h * W * 0.2f + H * 0.06f;
        float mrx = p->mouth_w * W * 0.5f;
        float mry = p->mouth_h * W * 0.5f;
        int my0 = (int)floorf(mcy - mry) - 1, my1 = (int)ceilf(mcy + mry) + 1;
        int mx0 = (int)floorf(mcx - mrx) - 1, mx1 = (int)ceilf(mcx + mrx) + 1;
        if (my0 < y0) my0 = y0;
        if (my1 > y1) my1 = y1;
        if (mx0 < 0) mx0 = 0;
        if (mx1 > screen_w) mx1 = screen_w;
        /* A smile only shows the lower half; mouth_open grows the top half in. */
        float top = mcy - mry * p->mouth_open;
        for (int y = my0; y < my1; y++) {
            float py = (float)y + 0.5f;
            if (py < top) {
                continue;
            }
            uint16_t *row = buf + (size_t)(y - y0) * screen_w;
            float dy = (py - mcy) / mry;
            for (int x = mx0; x < mx1; x++) {
                float dx = ((float)x + 0.5f - mcx) / mrx;
                if (dx * dx + dy * dy <= 1.0f) {
                    row[x] = color;
                }
            }
        }
    }
}
