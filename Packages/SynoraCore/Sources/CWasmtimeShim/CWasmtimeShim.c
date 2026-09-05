#include "CWasmtimeShim.h"

#include <dlfcn.h>
#include <stddef.h>

bool synora_wasmtime_library_available(const char *path) {
  if (path == NULL) {
    return false;
  }
  void *handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
  if (handle == NULL) {
    return false;
  }
  dlclose(handle);
  return true;
}
