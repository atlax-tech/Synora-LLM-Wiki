#ifndef SYNORA_WASMTIME_SHIM_H
#define SYNORA_WASMTIME_SHIM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

bool synora_wasmtime_library_available(const char *path, const char *allowed_root);

/* Runs the guest start function under epoch interruption. `deadline_ns` bounds execution
 * (0 = unbounded); `cancel` may point to a flag polled every 10 ms (NULL = no cancel).
 * The library must resolve inside `allowed_root`. */
bool synora_wasmtime_run_start(const char *path, const char *allowed_root,
                               const unsigned char *module, size_t module_size,
                               uint64_t deadline_ns, const int *cancel);

#endif
