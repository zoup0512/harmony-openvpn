/**
 * libovpnexec — NAPI wrapper around the OpenVPN3 core (client/ovpncli.hpp),
 * the HarmonyOS equivalent of ics-openvpn's SWIG/JNI glue.
 *
 * JS interface (see ets/vpnservice/OvpnEngine.ets):
 *   attach(cb)                      register event callback (log/event/tun_establish_req/done)
 *   startTunnel(opts)               eval config and connect on a worker thread
 *   stopTunnel()                    stop the running connection
 *   resolveTunEstablish(fd)         answer a tun_establish_req with the TUN fd
 *
 * TUN model: the core calls tun_builder_* callbacks while establishing the
 * session; we collect the parameters, ask ArkTS (via vpnExtension
 * VpnConnection.create) for the virtual network card fd, and block the worker
 * thread until resolveTunEstablish() delivers it — the same flow as the
 * Android VpnService.Builder.establish() path.
 */

#include <napi/native_api.h>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "client/ovpncli.hpp" // public interface (declarations only)

// Route all core logging through the LogReceiver callbacks, exactly like
// client/ovpncli.cpp does — must be configured before any header that uses
// the OPENVPN_LOG_* macros (e.g. openvpn/client/dns.hpp -> common/options.hpp).
#ifndef OPENVPN_LOG
#define OPENVPN_LOG_CLASS openvpn::ClientAPI::LogReceiver
#define OPENVPN_LOG_INFO openvpn::ClientAPI::LogInfo
#include <openvpn/log/logthread.hpp>
#endif

#include "openvpn/client/dns.hpp"

namespace {

using namespace openvpn;

struct EvMsg {
    std::string type;  // log | event | tun_establish_req | done
    std::string name;
    std::string info;
    bool error = false;
    bool fatal = false;
};

napi_threadsafe_function g_tsfn = nullptr;
std::thread g_worker;
std::atomic<bool> g_running{false};

// TUN establish handshake (worker thread <-> ArkTS)
std::mutex g_tun_mtx;
std::condition_variable g_tun_cv;
int g_tun_fd_result = -1;       // -2 = aborted by stop
bool g_tun_waiting = false;

ClientAPI::OpenVPNClient *g_client = nullptr;

void emit(std::string type, std::string name, std::string info,
          bool error = false, bool fatal = false)
{
    if (g_tsfn == nullptr) {
        return;
    }
    EvMsg *m = new EvMsg{std::move(type), std::move(name), std::move(info), error, fatal};
    napi_call_threadsafe_function(g_tsfn, m, napi_tsfn_nonblocking);
}

void call_js(napi_env env, napi_value js_cb, void * /*context*/, void *data)
{
    EvMsg *m = static_cast<EvMsg *>(data);
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    napi_value obj;
    napi_create_object(env, &obj);
    napi_value v;
    napi_create_string_utf8(env, m->type.c_str(), NAPI_AUTO_LENGTH, &v);
    napi_set_named_property(env, obj, "type", v);
    napi_create_string_utf8(env, m->name.c_str(), NAPI_AUTO_LENGTH, &v);
    napi_set_named_property(env, obj, "name", v);
    napi_create_string_utf8(env, m->info.c_str(), NAPI_AUTO_LENGTH, &v);
    napi_set_named_property(env, obj, "info", v);
    napi_get_boolean(env, m->error, &v);
    napi_set_named_property(env, obj, "error", v);
    napi_get_boolean(env, m->fatal, &v);
    napi_set_named_property(env, obj, "fatal", v);
    napi_call_function(env, undefined, js_cb, 1, &obj, nullptr);
    delete m;
}

class NapiClient : public ClientAPI::OpenVPNClient {
  public:
    // Collected tun builder parameters, forwarded to ArkTS for VpnConfig.
    std::vector<std::string> addrs;         // "addr/prefix"
    std::vector<std::string> routes;        // "addr/prefix"
    std::vector<std::string> excludeRoutes; // "addr/prefix"
    std::vector<std::string> dnsServers;
    std::vector<std::string> searchDomains;
    int mtu = 0;
    bool rerouteGw = false;
    std::string sessionName;

    // ---- LogReceiver / event receivers ----
    void log(const ClientAPI::LogInfo &li) override
    {
        emit("log", "", li.text);
    }

    void event(const ClientAPI::Event &ev) override
    {
        emit("event", ev.name, ev.info, ev.error, ev.fatal);
    }

    void acc_event(const ClientAPI::AppCustomControlMessageEvent &) override
    {
    }

    void external_pki_cert_request(ClientAPI::ExternalPKICertRequest &req) override
    {
        req.error = true;
        req.errorText = "External PKI is not supported in this build";
    }

    void external_pki_sign_request(ClientAPI::ExternalPKISignRequest &req) override
    {
        req.error = true;
        req.errorText = "External PKI is not supported in this build";
    }

    bool pause_on_connection_timeout() override
    {
        return false;
    }

    // The whole extension process is protected (vpnExtension.protectProcessNet)
    // before the tunnel starts, so per-socket protection is a no-op here.
    bool socket_protect(openvpn_io::detail::socket_type, std::string remote, bool) override
    {
        emit("log", "", "socket_protect: " + remote + " (process already protected)");
        return true;
    }

    // ---- TunBuilderBase ----
    // All parameters are collected and applied by the ArkTS side through the
    // vpnExtension VpnConfig; every setter just records and succeeds.
    bool tun_builder_new() override
    {
        return true;
    }

    bool tun_builder_set_layer(int layer) override
    {
        return layer == 0 || layer == 3;
    }

    bool tun_builder_set_remote_address(const std::string &, bool) override
    {
        return true;
    }

    bool tun_builder_add_address(const std::string &address, int prefix_length,
                                 const std::string & /*gateway*/, bool /*ipv6*/,
                                 bool /*net30*/) override
    {
        addrs.push_back(address + "/" + std::to_string(prefix_length));
        return true;
    }

    bool tun_builder_set_route_metric_default(int) override
    {
        return true;
    }

    bool tun_builder_reroute_gw(bool ipv4, bool ipv6, unsigned int) override
    {
        rerouteGw = ipv4 || ipv6;
        return true;
    }

    bool tun_builder_add_route(const std::string &address, int prefix_length, int,
                               bool) override
    {
        routes.push_back(address + "/" + std::to_string(prefix_length));
        return true;
    }

    bool tun_builder_exclude_route(const std::string &address, int prefix_length, int,
                                   bool) override
    {
        excludeRoutes.push_back(address + "/" + std::to_string(prefix_length));
        return true;
    }

    bool tun_builder_add_dns_server(const std::string &address, bool) override
    {
        dnsServers.push_back(address);
        return true;
    }

    bool tun_builder_add_dns_options(const DnsOptions &dns) override
    {
        for (const auto &srv : dns.servers) {
            for (const auto &a : srv.second.addresses) {
                dnsServers.push_back(a.to_string());
            }
        }
        for (const auto &d : dns.search_domains) {
            searchDomains.push_back(d.domain);
        }
        return true;
    }

    bool tun_builder_add_search_domain(const std::string &domain) override
    {
        searchDomains.push_back(domain);
        return true;
    }

    bool tun_builder_set_adapter_domain_suffix(const std::string &) override
    {
        return true;
    }

    bool tun_builder_set_mtu(int m) override
    {
        mtu = m;
        return true;
    }

    bool tun_builder_set_session_name(const std::string &name) override
    {
        sessionName = name;
        return true;
    }

    bool tun_builder_add_proxy_bypass(const std::string &) override
    {
        return true;
    }

    bool tun_builder_set_proxy_auto_config_url(const std::string &) override
    {
        return true;
    }

    bool tun_builder_set_proxy_http(const std::string &, int) override
    {
        return true;
    }

    bool tun_builder_set_proxy_https(const std::string &, int) override
    {
        return true;
    }

    bool tun_builder_add_wins_server(const std::string &) override
    {
        return true;
    }

    bool tun_builder_set_allow_family(int, bool) override
    {
        return true;
    }

    bool tun_builder_set_allow_local_dns(bool) override
    {
        return true;
    }

    bool tun_builder_persist() override
    {
        return true;
    }

    const std::vector<std::string> tun_builder_get_local_networks(bool) override
    {
        return {};
    }

    void tun_builder_teardown(bool) override
    {
        emit("log", "", "TUN teardown");
    }

    static std::string join(const std::vector<std::string> &v)
    {
        std::string out;
        for (size_t i = 0; i < v.size(); ++i) {
            if (i != 0) {
                out += ",";
            }
            out += v[i];
        }
        return out;
    }

    int tun_builder_establish() override
    {
        // Serialize the collected parameters for the ArkTS side; it creates the
        // virtual network card via vpnExtension and returns the fd.
        std::string req = "{";
        req += "\"addresses\":\"" + join(addrs) + "\"";
        req += ",\"routes\":\"" + join(routes) + "\"";
        req += ",\"excludeRoutes\":\"" + join(excludeRoutes) + "\"";
        req += ",\"dnsServers\":\"" + join(dnsServers) + "\"";
        req += ",\"searchDomains\":\"" + join(searchDomains) + "\"";
        req += ",\"mtu\":" + std::to_string(mtu);
        req += std::string(",\"rerouteGw\":") + (rerouteGw ? "true" : "false");
        req += "}";

        {
            std::lock_guard<std::mutex> lock(g_tun_mtx);
            g_tun_fd_result = -1;
            g_tun_waiting = true;
        }
        emit("tun_establish_req", sessionName, req);

        std::unique_lock<std::mutex> lock(g_tun_mtx);
        bool ok = g_tun_cv.wait_for(lock, std::chrono::seconds(20),
                                    [] { return g_tun_fd_result != -1; });
        int fd = g_tun_fd_result;
        g_tun_waiting = false;
        if (!ok || fd <= 0) {
            emit("log", "", "TUN establish failed or timed out (fd=" + std::to_string(fd) + ")");
            return -1;
        }
        return fd;
    }
};

// ---- NAPI exported functions ----

bool read_str_prop(napi_env env, napi_value obj, const char *name, std::string &out)
{
    napi_value v;
    if (napi_get_named_property(env, obj, name, &v) != napi_ok) {
        return false;
    }
    napi_valuetype t;
    if (napi_typeof(env, v, &t) != napi_ok || t != napi_string) {
        return false;
    }
    std::size_t len = 0;
    if (napi_get_value_string_utf8(env, v, nullptr, 0, &len) != napi_ok) {
        return false;
    }
    out.resize(len);
    napi_get_value_string_utf8(env, v, out.data(), len + 1, &len);
    return true;
}

napi_value Attach(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        napi_throw_error(env, nullptr, "attach requires a callback");
        return nullptr;
    }
    napi_value res;
    napi_create_string_utf8(env, "openvpn3", NAPI_AUTO_LENGTH, &res);
    if (g_tsfn != nullptr) {
        napi_release_threadsafe_function(g_tsfn, napi_tsfn_release);
        g_tsfn = nullptr;
    }
    napi_create_threadsafe_function(env, argv[0], nullptr, res, 0, 1,
                                    nullptr, nullptr, nullptr, call_js, &g_tsfn);
    return nullptr;
}

napi_value StartTunnel(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string content;
    std::string username;
    std::string password;
    if (argc >= 1 && argv[0] != nullptr) {
        read_str_prop(env, argv[0], "content", content);
        read_str_prop(env, argv[0], "username", username);
        read_str_prop(env, argv[0], "password", password);
    }

    napi_value result;
    napi_create_object(env, &result);
    napi_value okv;
    napi_value errv;

    if (g_running.exchange(true)) {
        napi_get_boolean(env, false, &okv);
        napi_create_string_utf8(env, "tunnel already running", NAPI_AUTO_LENGTH, &errv);
        napi_set_named_property(env, result, "ok", okv);
        napi_set_named_property(env, result, "error", errv);
        return result;
    }
    auto *client = new NapiClient();
    g_client = client;

    ClientAPI::Config config;
    config.content = content;
    config.guiVersion = "harmony-openvpn 1.0";
    config.connTimeout = 0;
    config.tunPersist = false;
    config.compressionMode = "yes";

    ClientAPI::EvalConfig eval = client->eval_config(config);
    if (eval.error) {
        emit("log", "", "eval_config error: " + eval.message);
        delete client;
        g_client = nullptr;
        g_running = false;
        napi_get_boolean(env, false, &okv);
        napi_create_string_utf8(env, eval.message.c_str(), NAPI_AUTO_LENGTH, &errv);
        napi_set_named_property(env, result, "ok", okv);
        napi_set_named_property(env, result, "error", errv);
        return result;
    }

    if (!username.empty() || !password.empty()) {
        ClientAPI::ProvideCreds creds;
        creds.username = username;
        creds.password = password;
        ClientAPI::Status st = client->provide_creds(creds);
        if (st.error) {
            emit("log", "", "provide_creds error: " + st.message);
        }
    }

    g_worker = std::thread([]() {
        auto *c = static_cast<NapiClient *>(g_client);
        ClientAPI::Status st = c->connect();
        emit("done", st.error ? "error" : "ok", st.message, st.error);
        delete c;
        g_client = nullptr;
        g_running = false;
    });
    g_worker.detach();

    napi_get_boolean(env, true, &okv);
    napi_create_string_utf8(env, "", NAPI_AUTO_LENGTH, &errv);
    napi_set_named_property(env, result, "ok", okv);
    napi_set_named_property(env, result, "error", errv);
    return result;
}

napi_value StopTunnel(napi_env, napi_callback_info)
{
    ClientAPI::OpenVPNClient *c = g_client;
    if (c != nullptr) {
        c->stop();
    }
    {
        // unblock a pending tun establish wait
        std::lock_guard<std::mutex> lock(g_tun_mtx);
        if (g_tun_fd_result == -1) {
            g_tun_fd_result = -2;
        }
    }
    g_tun_cv.notify_all();
    return nullptr;
}

napi_value ResolveTunEstablish(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int fd = -1;
    if (argc >= 1) {
        int32_t v = -1;
        if (napi_get_value_int32(env, argv[0], &v) == napi_ok) {
            fd = v;
        }
    }
    {
        std::lock_guard<std::mutex> lock(g_tun_mtx);
        g_tun_fd_result = fd;
    }
    g_tun_cv.notify_all();
    return nullptr;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"attach", nullptr, Attach, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startTunnel", nullptr, StartTunnel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopTunnel", nullptr, StopTunnel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"resolveTunEstablish", nullptr, ResolveTunEstablish, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module ovpnexecModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "ovpnexec",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterOvpnexecModule(void)
{
    napi_module_register(&ovpnexecModule);
}
