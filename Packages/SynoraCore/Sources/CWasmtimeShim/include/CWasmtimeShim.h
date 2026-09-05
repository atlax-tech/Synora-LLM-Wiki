#ifndef SYNORA_WASMTIME_SHIM_H
#define SYNORA_WASMTIME_SHIM_H

#include <stdbool.h>

bool synora_wasmtime_library_available(const char *path, const char *allowed_root);

#endif
