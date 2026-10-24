# Host-side unit tests for components/sohail_core (no ESP-IDF needed).
#   cmake -S firmware/host_tests -B build/host && cmake --build build/host && ctest --test-dir build/host
cmake_minimum_required(VERSION 3.16)
project(sohail_host_tests C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
add_compile_options(-Wall -Wextra -Werror -Wno-unused-parameter)

# Same cJSON release that ESP-IDF v5.3 bundles.
include(FetchContent)
FetchContent_Declare(cjson
    GIT_REPOSITORY https://github.com/DaveGamble/cJSON.git
    GIT_TAG v1.7.18
    GIT_SHALLOW TRUE)
FetchContent_GetProperties(cjson)
if(NOT cjson_POPULATED)
    FetchContent_Populate(cjson)
endif()
add_library(cjson STATIC ${cjson_SOURCE_DIR}/cJSON.c)
target_include_directories(cjson PUBLIC ${cjson_SOURCE_DIR})
target_compile_options(cjson PRIVATE -w)

add_subdirectory(../components/sohail_core sohail_core)

enable_testing()
foreach(t protocol robot face gfx button touch chime)
    add_executable(test_${t} test_${t}.c)
    target_link_libraries(test_${t} sohail_core)
    add_test(NAME ${t} COMMAND test_${t})
endforeach()

# Writes one PPM per expression for eyeballing the faces.
add_executable(render_faces render_faces.c)
target_link_libraries(render_faces sohail_core)
