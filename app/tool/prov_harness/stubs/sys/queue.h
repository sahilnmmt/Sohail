/* Host stub: glibc's sys/queue.h lacks the BSD *_SAFE iterator newlib has. */
#pragma once
#include_next <sys/queue.h>
#ifndef SLIST_FOREACH_SAFE
#define SLIST_FOREACH_SAFE(var, head, field, tvar) \
    for ((var) = SLIST_FIRST((head)); (var) && ((tvar) = SLIST_NEXT((var), field), 1); (var) = (tvar))
#endif
#ifndef SLIST_FIRST
#define SLIST_FIRST(head) ((head)->slh_first)
#endif
#ifndef SLIST_NEXT
#define SLIST_NEXT(elm, field) ((elm)->field.sle_next)
#endif
