#include "CWasmtimeShim.h"

#include <dlfcn.h>
#include <limits.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

bool synora_wasmtime_library_available(const char *path, const char *allowed_root) {
  if (path == NULL || allowed_root == NULL ||
      (strcmp(strrchr(path, '/') == NULL ? path : strrchr(path, '/') + 1,
              "libwasmtime.dylib") != 0)) {
    return false;
  }

  char resolved_path[PATH_MAX];
  char resolved_root[PATH_MAX];
  if (realpath(path, resolved_path) == NULL ||
      realpath(allowed_root, resolved_root) == NULL) {
    return false;
  }
  size_t root_length = strlen(resolved_root);
  if (strncmp(resolved_path, resolved_root, root_length) != 0 ||
      (resolved_path[root_length] != '\0' && resolved_path[root_length] != '/')) {
    return false;
  }

  void *handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
  if (handle == NULL) {
    return false;
  }
  dlclose(handle);
  return true;
}
