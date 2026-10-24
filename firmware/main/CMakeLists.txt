idf_component_register(
    SRCS app_main.c display.c ui.c net.c messaging.c input.c audio.c
    INCLUDE_DIRS "."
    REQUIRES sohail_core
    PRIV_REQUIRES driver esp_driver_gpio esp_driver_spi esp_driver_i2s esp_lcd
                  esp_wifi esp_netif esp_event nvs_flash wifi_provisioning
                  mqtt mbedtls esp_timer)
