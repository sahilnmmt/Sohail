/* Tiny assertion helpers shared by the host tests. */
#pragma once

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_failures;

#define CHECK(cond)                                                              \
    do {                                                                         \
        if (!(cond)) {                                                           \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond); \
            g_failures++;                                                        \
        }                                                                        \
    } while (0)

#define CHECK_EQ_INT(a, b)                                                       \
    do {                                                                         \
        long _a = (long)(a), _b = (long)(b);                                     \
        if (_a != _b) {                                                          \
            fprintf(stderr, "%s:%d: %s == %s failed: %ld != %ld\n", __FILE__,    \
                    __LINE__, #a, #b, _a, _b);                                   \
            g_failures++;                                                        \
        }                                                                        \
    } while (0)

#define CHECK_STR(a, b)                                                          \
    do {                                                                         \
        const char *_a = (a), *_b = (b);                                         \
        if (strcmp(_a, _b) != 0) {                                               \
            fprintf(stderr, "%s:%d: %s == %s failed: \"%s\" != \"%s\"\n",        \
                    __FILE__, __LINE__, #a, #b, _a, _b);                         \
            g_failures++;                                                        \
        }                                                                        \
    } while (0)

#define RUN(fn)                                                                  \
    do {                                                                         \
        int _before = g_failures;                                                \
        fn();                                                                    \
        printf("%s %s\n", g_failures == _before ? "PASS" : "FAIL", #fn);         \
    } while (0)

#define TEST_EXIT() return g_failures ? EXIT_FAILURE : EXIT_SUCCESS
