#ifndef SYNORA_WASMTIME_SHIM_H
#define SYNORA_WASMTIME_SHIM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Broker invoked when the guest calls the "synora"."request" host import.
 * Returns 0 to allow, non-zero to deny. The strings are not NUL-terminated. */
typedef struct synora_broker {
  int (*request)(void *context, const char *capability, size_t capability_length,
                 const char *target, size_t target_length);
  void *context;
} synora_broker_t;

bool synora_wasmtime_library_available(const char *path, const char *allowed_root);

/* Runs the guest start function under epoch interruption. `deadline_ns` bounds execution
 * (0 = unbounded); `cancel` may point to a flag polled every 10 ms (NULL = no cancel).
 * `broker` registers the "synora"."request" host import (NULL = no import registered).
 * The library must resolve inside `allowed_root`. */
bool synora_wasmtime_run_start(const char *path, const char *allowed_root,
                               const unsigned char *module, size_t module_size,
                               uint64_t deadline_ns, const int *cancel,
                               const synora_broker_t *broker);

#endif
