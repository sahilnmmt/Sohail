#include "display.h"

#include <string.h>

#include "driver/gpio.h"
#include "driver/spi_master.h"
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_vendor.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "sdkconfig.h"

static const char *TAG = "display";

#define LCD_HOST SPI2_HOST
#define W CONFIG_SOHAIL_LCD_WIDTH
#define H CONFIG_SOHAIL_LCD_HEIGHT

static esp_lcd_panel_handle_t s_panel;
static uint16_t *s_bands[2];
static int s_next_band;
static SemaphoreHandle_t s_free_bands; /* counts buffers not owned by the DMA */

static bool on_trans_done(esp_lcd_panel_io_handle_t io, esp_lcd_panel_io_event_data_t *edata, void *ctx)
{
    BaseType_t woken = pdFALSE;
    xSemaphoreGiveFromISR(s_free_bands, &woken);
    return woken == pdTRUE;
}

esp_err_t display_init(void)
{
    if (CONFIG_SOHAIL_PIN_LCD_BL >= 0) {
        gpio_config_t bl = {
            .pin_bit_mask = 1ULL << CONFIG_SOHAIL_PIN_LCD_BL,
            .mode = GPIO_MODE_OUTPUT,
        };
        ESP_ERROR_CHECK(gpio_config(&bl));
        gpio_set_level(CONFIG_SOHAIL_PIN_LCD_BL, 0); /* off until the first frame */
    }

    spi_bus_config_t bus = {
        .sclk_io_num = CONFIG_SOHAIL_PIN_LCD_SCLK,
        .mosi_io_num = CONFIG_SOHAIL_PIN_LCD_MOSI,
        .miso_io_num = -1,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = W * DISPLAY_BAND_ROWS * sizeof(uint16_t),
    };
    ESP_RETURN_ON_ERROR(spi_bus_initialize(LCD_HOST, &bus, SPI_DMA_CH_AUTO), TAG, "spi bus");

    s_free_bands = xSemaphoreCreateCounting(2, 2);
    for (int i = 0; i < 2; i++) {
        s_bands[i] = heap_caps_malloc(W * DISPLAY_BAND_ROWS * sizeof(uint16_t),
                                      MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
        if (!s_bands[i] || !s_free_bands) {
            return ESP_ERR_NO_MEM;
        }
    }

    esp_lcd_panel_io_handle_t io;
    esp_lcd_panel_io_spi_config_t io_cfg = {
        .cs_gpio_num = CONFIG_SOHAIL_PIN_LCD_CS,
        .dc_gpio_num = CONFIG_SOHAIL_PIN_LCD_DC,
        .spi_mode = 0,
        .pclk_hz = CONFIG_SOHAIL_LCD_PCLK_MHZ * 1000 * 1000,
        .trans_queue_depth = 4,
        .on_color_trans_done = on_trans_done,
        .lcd_cmd_bits = 8,
        .lcd_param_bits = 8,
    };
    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)LCD_HOST, &io_cfg, &io),
                        TAG, "panel io");

    esp_lcd_panel_dev_config_t panel_cfg = {
        .reset_gpio_num = CONFIG_SOHAIL_PIN_LCD_RST,
#if CONFIG_SOHAIL_LCD_BGR
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_BGR,
#else
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
#endif
        .bits_per_pixel = 16,
    };
    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_st7789(io, &panel_cfg, &s_panel), TAG, "st7789");
    ESP_ERROR_CHECK(esp_lcd_panel_reset(s_panel));
    ESP_ERROR_CHECK(esp_lcd_panel_init(s_panel));
#if CONFIG_SOHAIL_LCD_INVERT
    ESP_ERROR_CHECK(esp_lcd_panel_invert_color(s_panel, true));
#endif
    ESP_ERROR_CHECK(esp_lcd_panel_set_gap(s_panel, CONFIG_SOHAIL_LCD_X_GAP, CONFIG_SOHAIL_LCD_Y_GAP));
    ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(s_panel, true));

    /* Clear to black before the backlight comes on. */
    for (int y = 0; y < H; y += DISPLAY_BAND_ROWS) {
        int rows = H - y < DISPLAY_BAND_ROWS ? H - y : DISPLAY_BAND_ROWS;
        uint16_t *band = display_acquire_band();
        memset(band, 0, W * rows * sizeof(uint16_t));
        display_submit_band(band, y, rows);
    }
    if (CONFIG_SOHAIL_PIN_LCD_BL >= 0) {
        gpio_set_level(CONFIG_SOHAIL_PIN_LCD_BL, 1);
    }
    ESP_LOGI(TAG, "ST7789 %dx%d ready", W, H);
    return ESP_OK;
}

uint16_t *display_acquire_band(void)
{
    /* Transfers finish in submission order, so alternating buffers is safe. */
    xSemaphoreTake(s_free_bands, portMAX_DELAY);
    uint16_t *band = s_bands[s_next_band];
    s_next_band ^= 1;
    return band;
}

void display_submit_band(uint16_t *band, int y, int rows)
{
    esp_err_t err = esp_lcd_panel_draw_bitmap(s_panel, 0, y, W, y + rows, band);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "draw_bitmap: %s", esp_err_to_name(err));
        xSemaphoreGive(s_free_bands); /* nothing queued, so no callback will release it */
    }
}
