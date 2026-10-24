/* Renders every expression (plus the overlay UI) to PPM files for review:
 *   render_faces <out_dir>
 */
#include <stdio.h>
#include <string.h>

#include "sohail/face.h"
#include "sohail/gfx.h"

#define W 240
#define H 280

static uint16_t frame[W * H];

static void write_ppm(const char *path)
{
    FILE *f = fopen(path, "wb");
    if (!f) {
        perror(path);
        return;
    }
    fprintf(f, "P6\n%d %d\n255\n", W, H);
    for (int i = 0; i < W * H; i++) {
        uint16_t c = frame[i];
        unsigned char rgb[3] = {(unsigned char)((c >> 8) & 0xF8), (unsigned char)((c >> 3) & 0xFC),
                                (unsigned char)((c << 3) & 0xF8)};
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);
}

int main(int argc, char **argv)
{
    const char *dir = argc > 1 ? argv[1] : ".";
    char path[512];
    for (int e = 0; e < FACE_COUNT; e++) {
        face_frame_t fr = {.p = *face_preset((face_expr_t)e)};
        face_render_band(&fr, frame, W, H, 0, H, false);
        gfx_band_t b = {.buf = frame, .width = W, .y0 = 0, .rows = H};
        gfx_text_centered(&b, 250, 2, 0xFFFF, face_expr_name((face_expr_t)e));
        snprintf(path, sizeof(path), "%s/face_%d_%s.ppm", dir, e, face_expr_name((face_expr_t)e));
        write_ppm(path);
    }
    /* Font sheet. */
    memset(frame, 0, sizeof(frame));
    gfx_band_t b = {.buf = frame, .width = W, .y0 = 0, .rows = H};
    char line[20];
    for (int row = 0; row < 6; row++) {
        int n = 0;
        for (int c = 0x20 + row * 16; c < 0x20 + row * 16 + 16 && c < 0x7F; c++) line[n++] = (char)c;
        line[n] = 0;
        gfx_text(&b, 4, 10 + row * 24, 2, 0xFFFF, line);
    }
    snprintf(path, sizeof(path), "%s/font.ppm", dir);
    write_ppm(path);
    return 0;
}
