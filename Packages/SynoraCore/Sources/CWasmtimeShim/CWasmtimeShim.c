#include "CWasmtimeShim.h"

#include <dlfcn.h>
#include <limits.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

typedef struct wasm_engine_t wasm_engine_t;
typedef struct wasmtime_store_t wasmtime_store_t;
typedef struct wasmtime_context_t wasmtime_context_t;
typedef struct wasmtime_module_t wasmtime_module_t;
typedef struct wasmtime_error_t wasmtime_error_t;
typedef struct wasm_trap_t wasm_trap_t;
typedef struct {
  uint64_t store_id;
  size_t private_data;
} wasmtime_instance_t;

static void *open_library(const char *path, const char *allowed_root) {
  if (path == NULL || allowed_root == NULL ||
      (strcmp(strrchr(path, '/') == NULL ? path : strrchr(path, '/') + 1,
              "libwasmtime.dylib") != 0)) {
    return NULL;
  }

  char resolved_path[PATH_MAX];
  char resolved_root[PATH_MAX];
  if (realpath(path, resolved_path) == NULL ||
      realpath(allowed_root, resolved_root) == NULL) {
    return NULL;
  }
  size_t root_length = strlen(resolved_root);
  if (strncmp(resolved_path, resolved_root, root_length) != 0 ||
      (resolved_path[root_length] != '\0' && resolved_path[root_length] != '/')) {
    return NULL;
  }
  return dlopen(resolved_path, RTLD_NOW | RTLD_LOCAL);
}

bool synora_wasmtime_library_available(const char *path, const char *allowed_root) {
  void *handle = open_library(path, allowed_root);
  if (handle == NULL) {
    return false;
  }
  dlclose(handle);
  return true;
}

bool synora_wasmtime_run_start(const char *path, const char *allowed_root,
                               const unsigned char *module_bytes,
                               size_t module_size) {
  if (module_bytes == NULL || module_size == 0) {
    return false;
  }
  void *handle = open_library(path, allowed_root);
  if (handle == NULL) {
    return false;
  }

  wasm_engine_t *(*engine_new)(void) = dlsym(handle, "wasm_engine_new");
  void (*engine_delete)(wasm_engine_t *) = dlsym(handle, "wasm_engine_delete");
  wasmtime_store_t *(*store_new)(wasm_engine_t *, void *, void (*)(void *)) =
      dlsym(handle, "wasmtime_store_new");
  wasmtime_context_t *(*store_context)(wasmtime_store_t *) =
      dlsym(handle, "wasmtime_store_context");
  void (*store_delete)(wasmtime_store_t *) = dlsym(handle, "wasmtime_store_delete");
  wasmtime_error_t *(*module_new)(wasm_engine_t *, const uint8_t *, size_t,
                                  wasmtime_module_t **) =
      dlsym(handle, "wasmtime_module_new");
  void (*module_delete)(wasmtime_module_t *) = dlsym(handle, "wasmtime_module_delete");
  void (*error_delete)(wasmtime_error_t *) = dlsym(handle, "wasmtime_error_delete");
  void (*trap_delete)(wasm_trap_t *) = dlsym(handle, "wasm_trap_delete");
  wasmtime_error_t *(*instance_new)(wasmtime_context_t *, const wasmtime_module_t *,
                                    const void *, size_t, wasmtime_instance_t *,
                                    wasm_trap_t **) =
      dlsym(handle, "wasmtime_instance_new");
  bool symbols = engine_new && engine_delete && store_new && store_context &&
                 store_delete && module_new && module_delete && error_delete &&
                 trap_delete && instance_new;
  if (!symbols) {
    dlclose(handle);
    return false;
  }

  bool success = false;
  wasm_engine_t *engine = engine_new();
  wasmtime_store_t *store = engine == NULL ? NULL : store_new(engine, NULL, NULL);
  wasmtime_module_t *module = NULL;
  wasmtime_error_t *error = engine == NULL
                                ? NULL
                                : module_new(engine, module_bytes, module_size, &module);
  if (engine != NULL && store != NULL && error == NULL && module != NULL) {
    wasmtime_instance_t instance = {0};
    wasm_trap_t *trap = NULL;
    error = instance_new(store_context(store), module, NULL, 0, &instance, &trap);
    success = error == NULL && trap == NULL;
    if (trap != NULL) {
      trap_delete(trap);
    }
  }
  if (error != NULL) {
    error_delete(error);
  }
  if (module != NULL) {
    module_delete(module);
  }
  if (store != NULL) {
    store_delete(store);
  }
  if (engine != NULL) {
    engine_delete(engine);
  }
  dlclose(handle);
  return success;
}
