#include "CWasmtimeShim.h"

#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct wasm_engine_t wasm_engine_t;
typedef struct wasm_engine_t wasmtime_engine_t;
typedef struct wasm_config_t wasm_config_t;
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

static uint64_t monotonic_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

struct epoch_context {
  void (*increment_epoch)(wasmtime_engine_t *);
  wasmtime_engine_t *engine;
  const int *cancel;
  uint64_t deadline_ns;
  _Atomic int done;
};

/* Increments the engine epoch once the deadline passes or cancel is set, which
 * traps a running guest instead of letting an infinite loop hang the service. */
static void *epoch_thread(void *argument) {
  struct epoch_context *context = argument;
  while (!atomic_load_explicit(&context->done, memory_order_seq_cst)) {
    int cancelled = context->cancel != NULL && atomic_load_explicit(
        (_Atomic int *)context->cancel, memory_order_seq_cst);
    if (cancelled || monotonic_ns() >= context->deadline_ns) {
      context->increment_epoch(context->engine);
      atomic_store_explicit(&context->done, 1, memory_order_seq_cst);
      break;
    }
    struct timespec pause = {0, 10 * 1000 * 1000};
    nanosleep(&pause, NULL);
  }
  return NULL;
}

bool synora_wasmtime_run_start(const char *path, const char *allowed_root,
                               const unsigned char *module_bytes, size_t module_size,
                               uint64_t deadline_ns, const int *cancel) {
  if (module_bytes == NULL || module_size == 0) {
    return false;
  }
  void *handle = open_library(path, allowed_root);
  if (handle == NULL) {
    return false;
  }

  wasm_engine_t *(*engine_new)(void) = dlsym(handle, "wasm_engine_new");
  void (*engine_delete)(wasm_engine_t *) = dlsym(handle, "wasm_engine_delete");
  wasm_config_t *(*config_new)(void) = dlsym(handle, "wasm_config_new");
  void (*config_delete)(wasm_config_t *) = dlsym(handle, "wasm_config_delete");
  void (*config_epoch_set)(wasm_config_t *, bool) =
      dlsym(handle, "wasmtime_config_epoch_interruption_set");
  wasm_engine_t *(*engine_new_with_config)(wasm_config_t *) =
      dlsym(handle, "wasm_engine_new_with_config");
  void (*engine_increment_epoch)(wasmtime_engine_t *) =
      dlsym(handle, "wasmtime_engine_increment_epoch");
  void (*context_set_epoch_deadline)(wasmtime_context_t *, uint64_t) =
      dlsym(handle, "wasmtime_context_set_epoch_deadline");
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
  bool symbols = engine_new && engine_delete && config_new && config_delete &&
                 config_epoch_set && engine_new_with_config && engine_increment_epoch &&
                 context_set_epoch_deadline &&
                 store_new && store_context && store_delete && module_new && module_delete &&
                 error_delete && trap_delete && instance_new;
  if (!symbols) {
    dlclose(handle);
    return false;
  }

  bool success = false;
  wasm_config_t *config = config_new();
  wasmtime_engine_t *engine = NULL;
  if (config != NULL) {
    config_epoch_set(config, true);
    // engine_new_with_config consumes the config on success and failure.
    engine = engine_new_with_config(config);
  }

  struct epoch_context context = {
      engine_increment_epoch, engine, cancel, monotonic_ns() + deadline_ns, 0};
  pthread_t thread = NULL;
  bool thread_running = engine != NULL && (deadline_ns != 0 || cancel != NULL) &&
                        pthread_create(&thread, NULL, epoch_thread, &context) == 0;

  wasmtime_store_t *store = engine == NULL ? NULL : store_new(engine, NULL, NULL);
  if (store != NULL) {
    // Epoch interruption defaults to deadline 0, which traps immediately; grant an
    // effectively unbounded budget unless a deadline/cancel thread will bump the epoch.
    context_set_epoch_deadline(store_context(store), thread_running ? 1 : UINT64_MAX);
  }
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
  if (thread_running) {
    atomic_store_explicit(&context.done, 1, memory_order_seq_cst);
    pthread_join(thread, NULL);
  }
  if (engine != NULL) {
    engine_delete(engine);
  }
  dlclose(handle);
  return success;
}
