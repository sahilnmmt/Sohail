#include "audio.h"

#include "sdkconfig.h"

#if CONFIG_SOHAIL_AUDIO_ENABLE

#include "driver/i2s_std.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"

static const char *TAG = "audio";

#define SAMPLE_RATE 16000
#define CHUNK 256

static i2s_chan_handle_t s_tx;
static QueueHandle_t s_queue;

static void audio_task(void *arg)
{
    static int16_t buf[CHUNK];
    chime_t chime;
    for (;;) {
        xQueueReceive(s_queue, &chime, portMAX_DELAY);
        size_t total = chime_length(chime, SAMPLE_RATE);
        for (size_t pos = 0; pos < total;) {
            size_t n = chime_render(chime, SAMPLE_RATE, CONFIG_SOHAIL_AUDIO_VOLUME, pos, buf, CHUNK);
            if (n == 0) {
                break;
            }
            size_t written;
            i2s_channel_write(s_tx, buf, n * sizeof(int16_t), &written, portMAX_DELAY);
            pos += n;
        }
    }
}

void audio_init(void)
{
    i2s_chan_config_t chan = I2S_CHANNEL_DEFAULT_CONFIG(I2S_NUM_AUTO, I2S_ROLE_MASTER);
    chan.auto_clear = true; /* send silence when idle instead of repeating the last buffer */
    ESP_ERROR_CHECK(i2s_new_channel(&chan, &s_tx, NULL));

    i2s_std_config_t std = {
        .clk_cfg = I2S_STD_CLK_DEFAULT_CONFIG(SAMPLE_RATE),
        .slot_cfg = I2S_STD_PHILIPS_SLOT_DEFAULT_CONFIG(I2S_DATA_BIT_WIDTH_16BIT, I2S_SLOT_MODE_MONO),
        .gpio_cfg = {
            .mclk = I2S_GPIO_UNUSED,
            .bclk = CONFIG_SOHAIL_PIN_I2S_BCLK,
            .ws = CONFIG_SOHAIL_PIN_I2S_WS,
            .dout = CONFIG_SOHAIL_PIN_I2S_DOUT,
            .din = I2S_GPIO_UNUSED,
        },
    };
    ESP_ERROR_CHECK(i2s_channel_init_std_mode(s_tx, &std));
    ESP_ERROR_CHECK(i2s_channel_enable(s_tx));

    s_queue = xQueueCreate(4, sizeof(chime_t));
    configASSERT(s_queue);
    xTaskCreate(audio_task, "audio", 3072, NULL, 5, NULL);
    ESP_LOGI(TAG, "I2S speaker ready");
}

void audio_play(chime_t chime)
{
    xQueueSend(s_queue, &chime, 0);
}

#else /* !CONFIG_SOHAIL_AUDIO_ENABLE */

void audio_init(void) {}
void audio_play(chime_t chime) { (void)chime; }

#endif
