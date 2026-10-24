/* ST7789 SPI panel with double-buffered band uploads. */
#pragma once

#include <stdint.h>

#include "esp_err.h"

#define DISPLAY_BAND_ROWS 40

esp_err_t display_init(void);

/* Blocks until one of the two DMA band buffers is free and returns it
 * (CONFIG_SOHAIL_LCD_WIDTH * DISPLAY_BAND_ROWS pixels). */
uint16_t *display_acquire_band(void);

/* Queues a band for transfer; the buffer is released when the DMA finishes. */
void display_submit_band(uint16_t *band, int y, int rows);
