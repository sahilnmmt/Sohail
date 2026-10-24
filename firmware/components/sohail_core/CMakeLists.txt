# Hardware-independent robot logic. Built as an ESP-IDF component on the
# device and as a plain static library by host_tests/.
set(SOHAIL_CORE_SRCS
    src/protocol.c
    src/robot.c
    src/face.c
    src/gfx.c
    src/font5x7.c
    src/button.c
    src/touch_detect.c
    src/chime.c)

if(ESP_PLATFORM)
    idf_component_register(SRCS ${SOHAIL_CORE_SRCS}
                           INCLUDE_DIRS include
                           PRIV_REQUIRES json)
else()
    add_library(sohail_core STATIC ${SOHAIL_CORE_SRCS})
    target_include_directories(sohail_core PUBLIC include)
    target_link_libraries(sohail_core PUBLIC cjson m)
endif()
