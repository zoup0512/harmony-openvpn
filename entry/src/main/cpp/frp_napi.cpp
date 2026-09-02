// libfrpglue.so — NAPI bridge to the Go frpc host (libfrp_host.so).
//
// The Go core is built as a c-shared library outside CMake (see
// native/frpc-host/build-ohos.sh) and shipped alongside this module. This
// glue dlopen()s it lazily and forwards the in-process entry, which is used
// as fallback on devices that cannot spawn native child processes.
#include "napi/native_api.h"
#include <dlfcn.h>
#include <future>
#include <string>
#include <thread>

namespace {
using FrpHostRunFn = int (*)(const char *);

void *g_host = nullptr;
FrpHostRunFn g_run = nullptr;

// The Go runtime must be initialized on a non-main thread (its thread-local
// setup conflicts with the JS/main thread); every entry call is dispatched
// to a short-lived worker thread and waited for once.
int CallOnWorkerThread(const std::string &params)
{
    std::promise<int> done;
    std::future<int> future = done.get_future();
    std::thread worker([&params, &done]() {
        done.set_value(g_run(params.c_str()));
    });
    worker.detach();
    return future.get();
}

// Resolves the Go core on first use. The load is intentionally lazy so a
// missing or incompatible core only fails the fallback path.
bool EnsureHostLoaded(std::string &error)
{
    if (g_run != nullptr) {
        return true;
    }
    g_host = dlopen("libfrp_host.so", RTLD_NOW | RTLD_LOCAL);
    if (g_host == nullptr) {
        error = "dlopen libfrp_host.so failed: ";
        error += dlerror() != nullptr ? dlerror() : "unknown";
        return false;
    }
    g_run = reinterpret_cast<FrpHostRunFn>(dlsym(g_host, "FrpHostRun"));
    if (g_run == nullptr) {
        error = "dlsym FrpHostRun failed";
        return false;
    }
    return true;
}

napi_value RunFrpHost(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    size_t length = 0;
    napi_get_value_string_utf8(env, args[0], nullptr, 0, &length);
    std::string params(length, '\0');
    napi_get_value_string_utf8(env, args[0], params.data(), length + 1, &length);

    napi_value result = nullptr;
    std::string error;
    if (!EnsureHostLoaded(error)) {
        napi_create_int32(env, -1, &result);
        return result;
    }
    napi_create_int32(env, CallOnWorkerThread(params), &result);
    return result;
}
} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"runFrpHost", nullptr, RunFrpHost, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module frpglueModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "frpglue",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterFrpglueModule(void)
{
    napi_module_register(&frpglueModule);
}
