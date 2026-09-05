#ifndef SYNORA_WASMTIME_SHIM_H
#define SYNORA_WASMTIME_SHIM_H

#include <stdbool.h>
#include <stddef.h>

bool synora_wasmtime_library_available(const char *path, const char *allowed_root);
bool synora_wasmtime_run_start(const char *path, const char *allowed_root,
                               const unsigned char *module, size_t module_size);

#endif
