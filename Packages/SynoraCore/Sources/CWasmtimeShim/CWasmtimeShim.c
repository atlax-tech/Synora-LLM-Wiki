#include "CWasmtimeShim.h"

#include <dlfcn.h>
#include <limits.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

typedef struct wasm_engine_t wasm_engine_t;
typedef struct wasm_engine_t wasmtime_engine_t;
typedef struct wasm_config_t wasm_config_t;
typedef struct wasmtime_store_t wasmtime_store_t;
typedef struct wasmtime_context_t wasmtime_context_t;
typedef struct wasmtime_module_t wasmtime_module_t;
typedef struct wasmtime_error_t wasmtime_error_t;
typedef struct wasm_trap_t wasm_trap_t;
typedef struct wasmtime_caller wasmtime_caller_t;
typedef struct wasmtime_valtype wasmtime_valtype_t;
typedef struct wasmtime_functype wasmtime_functype_t;
typedef struct { uint64_t store_id; void *__private; } wasmtime_func_t;
typedef struct {
  struct { uint64_t store_id; uint32_t __private1; };
  uint32_t __private2;
} wasmtime_memory_t;
/* Exact layouts from the pinned Wasmtime 48.0.1 headers with GC enabled;
 * the shim never links the library, so struct copies keep it self-contained. */
typedef struct wasmtime_val {
  uint8_t kind;
  union {
    int32_t i32;
    int64_t i64;
    float f32;
    double f64;
    struct { uint64_t store_id; uint32_t __private1; uint32_t __private2; void *__private3; }
        ref;
    unsigned char v128[16];
  } of;
} wasmtime_val_t;
typedef struct wasmtime_extern {
  uint8_t kind;
  union {
    wasmtime_func_t func;
    wasmtime_memory_t memory;
    unsigned char padding[24];
  } of;
} wasmtime_extern_t;
typedef struct {
  size_t size;
  wasmtime_valtype_t **data;
} wasmtime_valtype_vec_t;
typedef struct { uint64_t store_id; size_t private_data; } wasmtime_instance_t;

/* wasm_valkind_t enum value for i32 in the wasm C API (not the binary encoding). */
#define SYNORA_WASMTIME_I32 0
#define SYNORATIME_VAL_I32 0
#define SYNORA_EXTERN_FUNC 0
#define SYNORA_EXTERN_MEMORY 3

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

struct broker_context {
  const synora_broker_t *broker;
  wasmtime_context_t *store_context;
  void *handle;
  uint8_t *memory_data;
  size_t memory_size;
};

/* Reads the capability and target strings from guest memory and forwards the
 * broker verdict (0 = allow) as the host function result. */
static wasm_trap_t *broker_host_callback(void *env, wasmtime_caller_t *caller,
                                         const wasmtime_val_t *args, size_t nargs,
                                         wasmtime_val_t *results, size_t nresults) {
  struct broker_context *context = env;
  bool (*caller_export_get)(wasmtime_caller_t *, const char *, size_t,
                            wasmtime_extern_t *) =
      dlsym(context->handle, "wasmtime_caller_export_get");
  uint8_t *(*memory_data)(wasmtime_context_t *, const wasmtime_memory_t *) =
      dlsym(context->handle, "wasmtime_memory_data");
  size_t (*memory_size)(wasmtime_context_t *, const wasmtime_memory_t *) =
      dlsym(context->handle, "wasmtime_memory_data_size");
  results[0].kind = SYNORATIME_VAL_I32;
  results[0].of.i32 = 1;
  if (nresults != 1 || !caller_export_get || !memory_data || !memory_size) {
    return NULL;
  }
  wasmtime_extern_t item;
  if (!caller_export_get(caller, "memory", 6, &item) ||
      item.kind != SYNORA_EXTERN_MEMORY) {
    return NULL;
  }
  context->memory_data = memory_data(context->store_context, &item.of.memory);
  context->memory_size = memory_size(context->store_context, &item.of.memory);
  if (context->memory_data == NULL) {
    return NULL;
  }
  size_t capability_length = (size_t)args[1].of.i32;
  size_t target_length = (size_t)args[3].of.i32;
  size_t capability_offset = (size_t)args[0].of.i32;
  size_t target_offset = (size_t)args[2].of.i32;
  if (capability_offset > context->memory_size ||
      capability_length > context->memory_size - capability_offset ||
      target_offset > context->memory_size ||
      target_length > context->memory_size - target_offset ||
      context->broker == NULL || context->broker->request == NULL) {
    return NULL;
  }
  results[0].of.i32 = context->broker->request(
      context->broker->context,
      (const char *)context->memory_data + capability_offset, capability_length,
      (const char *)context->memory_data + target_offset, target_length);
  return NULL;
}

bool synora_wasmtime_run_start(const char *path, const char *allowed_root,
                               const unsigned char *module_bytes, size_t module_size,
                               uint64_t deadline_ns, const int *cancel,
                               const synora_broker_t *broker) {
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
                                    const wasmtime_extern_t *, size_t,
                                    wasmtime_instance_t *, wasm_trap_t **) =
      dlsym(handle, "wasmtime_instance_new");
  wasmtime_valtype_t *(*valtype_new)(uint8_t) = dlsym(handle, "wasm_valtype_new");
  void (*valtype_vec_new)(wasmtime_valtype_vec_t *, size_t, wasmtime_valtype_t **) =
      dlsym(handle, "wasm_valtype_vec_new");
  wasmtime_functype_t *(*functype_new)(wasmtime_valtype_vec_t *, wasmtime_valtype_vec_t *) =
      dlsym(handle, "wasm_functype_new");
  void (*functype_delete)(wasmtime_functype_t *) = dlsym(handle, "wasm_functype_delete");
  void (*func_new)(wasmtime_context_t *, const wasmtime_functype_t *,
                   wasm_trap_t *(*)(void *, wasmtime_caller_t *, const wasmtime_val_t *,
                                    size_t, wasmtime_val_t *, size_t),
                   void *, void (*)(void *), wasmtime_func_t *) =
      dlsym(handle, "wasmtime_func_new");
  bool symbols = engine_new && engine_delete && config_new && config_delete &&
                 config_epoch_set && engine_new_with_config && engine_increment_epoch &&
                 context_set_epoch_deadline && store_new && store_context && store_delete &&
                 module_new && module_delete && error_delete && trap_delete && instance_new &&
                 valtype_new && valtype_vec_new && functype_new && functype_delete && func_new;
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

  wasmtime_extern_t imports[1];
  size_t import_count = 0;
  struct broker_context broker_context = {broker, store_context(store), handle, NULL, 0};
  if (engine != NULL && store != NULL && error == NULL && module != NULL && broker != NULL) {
    wasmtime_valtype_t *params[4];
    for (size_t i = 0; i < 4; i++) {
      params[i] = valtype_new(SYNORA_WASMTIME_I32);
    }
    wasmtime_valtype_t *result_array[1] = {valtype_new(SYNORA_WASMTIME_I32)};
    wasmtime_valtype_vec_t parameter_types;
    valtype_vec_new(&parameter_types, 4, params);
    wasmtime_valtype_vec_t result_types;
    valtype_vec_new(&result_types, 1, result_array);
    wasmtime_functype_t *function_type = functype_new(&parameter_types, &result_types);
    if (function_type != NULL) {
      wasmtime_func_t host_function = {0};
      func_new(store_context(store), function_type, broker_host_callback, &broker_context,
               NULL, &host_function);
      imports[0].kind = SYNORA_EXTERN_FUNC;
      imports[0].of.func = host_function;
      import_count = 1;
    }
    functype_delete(function_type);
  }

  if (engine != NULL && store != NULL && error == NULL && module != NULL) {
    wasmtime_instance_t instance = {0};
    wasm_trap_t *trap = NULL;
    error = instance_new(store_context(store), module, imports, import_count, &instance,
                         &trap);
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
