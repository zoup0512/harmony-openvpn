/**
 * libovpnexec — NAPI wrapper around the OpenVPN3 core (client/ovpncli.hpp),
 * the HarmonyOS equivalent of ics-openvpn's SWIG/JNI glue.
 *
 * JS interface (see ets/vpnservice/OvpnEngine.ets):
 *   attach(cb)                      register event callback (log/event/tun_establish_req/done)
 *   startTunnel(opts)               eval config and connect on a worker thread
 *   stopTunnel()                    stop the running connection
 *   getTunStats()                   read aggregate TUN traffic counters while active
 *   respondCrText({response})       answer an active CR_TEXT request
 *   resolveTunEstablish(fd)         answer a tun_establish_req with the TUN fd
 *
 * TUN model: the core calls tun_builder_* callbacks while establishing the
 * session; we collect the parameters, ask ArkTS (via vpnExtension
 * VpnConnection.create) for the virtual network card fd, and block the worker
 * thread until resolveTunEstablish() delivers it — the same flow as the
 * Android VpnService.Builder.establish() path.
 */

#include <napi/native_api.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "client/ovpncli.hpp" // public interface (declarations only)
#include "openvpn/common/base64.hpp"

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
    bool hasDynamicChallenge = false;
    ClientAPI::DynamicChallenge dynamicChallenge;
    // Transient callback data only; never put this value in info/log output.
    std::string dynamicChallengeCookie;
};

napi_threadsafe_function g_tsfn = nullptr;
std::thread g_worker;
// g_running guards single-tunnel ownership; a restart (OTP/credentials
// resubmission) must wait for the previous worker to fully unwind instead
// of failing with "tunnel already running".
std::mutex g_run_mtx;
std::condition_variable g_run_cv;
std::atomic<bool> g_running{false};
std::atomic<bool> g_client_ready{false};
std::mutex g_client_mtx; // protects the client pointer during start/stop/event callbacks

// TUN establish handshake (worker thread <-> ArkTS)
std::mutex g_tun_mtx;
std::condition_variable g_tun_cv;
int g_tun_fd_result = -1;   // fd delivered by resolveTunEstablish(), or negative error
bool g_tun_pending = false; // tun_establish_req emitted, answer not yet delivered

ClientAPI::OpenVPNClient *g_client = nullptr;

void emit(std::string type, std::string name, std::string info,
          bool error = false, bool fatal = false)
{
    if (g_tsfn == nullptr) {
        return;
    }
    EvMsg *m = new EvMsg;
    m->type = std::move(type);
    m->name = std::move(name);
    m->info = std::move(info);
    m->error = error;
    m->fatal = fatal;
    napi_call_threadsafe_function(g_tsfn, m, napi_tsfn_nonblocking);
}

void emit_event(const ClientAPI::Event &ev)
{
    if (g_tsfn == nullptr) {
        return;
    }
    EvMsg *m = new EvMsg;
    m->type = "event";
    m->name = ev.name;
    m->info = ev.info;
    m->error = ev.error;
    m->fatal = ev.fatal;
    if (ev.name == "DYNAMIC_CHALLENGE") {
        m->hasDynamicChallenge =
            ClientAPI::OpenVPNClientHelper::parse_dynamic_challenge(ev.info, m->dynamicChallenge);
        // A dynamic challenge's raw CRV1 value is a credential-bearing cookie.
        // Keep it out of the generic event info field, which callers may log.
        m->info.clear();
        if (m->hasDynamicChallenge) {
            m->dynamicChallengeCookie = ev.info;
        }
    }
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
    if (m->hasDynamicChallenge) {
        napi_value dc;
        napi_create_object(env, &dc);
        napi_create_string_utf8(env, m->dynamicChallenge.challenge.c_str(), NAPI_AUTO_LENGTH, &v);
        napi_set_named_property(env, dc, "challenge", v);
        napi_get_boolean(env, m->dynamicChallenge.echo, &v);
        napi_set_named_property(env, dc, "echo", v);
        napi_get_boolean(env, m->dynamicChallenge.responseRequired, &v);
        napi_set_named_property(env, dc, "responseRequired", v);
        napi_create_string_utf8(env, m->dynamicChallenge.stateID.c_str(), NAPI_AUTO_LENGTH, &v);
        napi_set_named_property(env, dc, "stateID", v);
        napi_create_string_utf8(env, m->dynamicChallengeCookie.c_str(), NAPI_AUTO_LENGTH, &v);
        napi_set_named_property(env, dc, "cookie", v);
        napi_set_named_property(env, obj, "dynamicChallenge", dc);
    }
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
        // OpenVPN3 delivers this callback from its connection thread after the
        // client has enabled foreign-thread access. This is the safe lifetime
        // window for respondCrText() to post a control-channel message.
        if (ev.name == "DISCONNECTED" || ev.name == "EXITING") {
            g_client_ready = false;
        } else {
            g_client_ready = true;
        }
        emit_event(ev);
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
        // The builder sequence re-runs on every (re)connection (tunPersist is
        // false), so start from a clean parameter set — otherwise routes and
        // addresses accumulate across reconnects.
        addrs.clear();
        routes.clear();
        excludeRoutes.clear();
        dnsServers.clear();
        searchDomains.clear();
        mtu = 0;
        rerouteGw = false;
        sessionName.clear();
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

    // tunprop.hpp does NOT emit add_route calls for the default route: the
    // whole redirect-gateway job (usually pushed by the server at runtime)
    // is delegated to this hook. Install the default routes here or traffic
    // never enters the TUN while the session still reports CONNECTED.
    bool tun_builder_reroute_gw(bool ipv4, bool ipv6, unsigned int flags) override
    {
        rerouteGw = ipv4 || ipv6;
        // RedirectGatewayFlags::RG_DEF1 from openvpn/client/rgopt.hpp
        constexpr unsigned int RG_DEF1 = 1u << 4;
        const bool def1 = (flags & RG_DEF1) != 0;
        if (ipv4) {
            if (def1) {
                addRouteUnique("0.0.0.0/1");
                addRouteUnique("128.0.0.0/1");
            } else {
                addRouteUnique("0.0.0.0/0");
            }
        }
        if (ipv6) {
            if (def1) {
                addRouteUnique("::/1");
                addRouteUnique("8000::/1");
            } else {
                addRouteUnique("::/0");
            }
        }
        emit("log", "", std::string("reroute_gw: ipv4=") + (ipv4 ? "1" : "0") +
             " ipv6=" + (ipv6 ? "1" : "0") + " def1=" + (def1 ? "1" : "0"));
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

    // The config may already contain an explicit default route (e.g. a
    // client-side "route 0.0.0.0 0.0.0.0 vpn_gateway" in addition to the
    // pushed redirect-gateway); keep the route list free of duplicates.
    void addRouteUnique(const std::string &route)
    {
        if (std::find(routes.begin(), routes.end(), route) == routes.end()) {
            routes.push_back(route);
        }
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
            g_tun_pending = true;
        }
        emit("tun_establish_req", sessionName, req);

        std::unique_lock<std::mutex> lock(g_tun_mtx);
        bool ok = g_tun_cv.wait_for(lock, std::chrono::seconds(20),
                                    [] { return !g_tun_pending; });
        int fd = g_tun_fd_result;
        if (!ok || fd < 0) {
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

bool read_bool_prop(napi_env env, napi_value obj, const char *name, bool &out)
{
    napi_value v;
    if (napi_get_named_property(env, obj, name, &v) != napi_ok) {
        return false;
    }
    napi_valuetype t;
    if (napi_typeof(env, v, &t) != napi_ok || t != napi_boolean) {
        return false;
    }
    return napi_get_value_bool(env, v, &out) == napi_ok;
}

bool read_int_prop(napi_env env, napi_value obj, const char *name, int &out)
{
    napi_value v;
    if (napi_get_named_property(env, obj, name, &v) != napi_ok) {
        return false;
    }
    napi_valuetype t;
    if (napi_typeof(env, v, &t) != napi_ok || t != napi_number) {
        return false;
    }
    int32_t value = 0;
    if (napi_get_value_int32(env, v, &value) != napi_ok) {
        return false;
    }
    out = value;
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
    std::string response;
    std::string dynamicChallengeCookie;
    std::string ssoMethods = "webauth,crtext";
    bool infoEnabled = true;
    int connTimeout = 120;
    if (argc >= 1 && argv[0] != nullptr) {
        read_str_prop(env, argv[0], "content", content);
        read_str_prop(env, argv[0], "username", username);
        read_str_prop(env, argv[0], "password", password);
        read_str_prop(env, argv[0], "response", response);
        read_str_prop(env, argv[0], "dynamicChallengeCookie", dynamicChallengeCookie);
        read_int_prop(env, argv[0], "connTimeout", connTimeout);
        std::string configuredSsoMethods;
        if (read_str_prop(env, argv[0], "ssoMethods", configuredSsoMethods) &&
            !configuredSsoMethods.empty()) {
            ssoMethods = configuredSsoMethods;
        }
        read_bool_prop(env, argv[0], "info", infoEnabled);
    }

    napi_value result;
    napi_create_object(env, &result);
    napi_value okv;
    napi_value errv;

    // Claim the single-tunnel slot. An OTP/credentials resubmission stops the
    // previous engine first; the ArkTS stop() only waits for the TUN destroy,
    // so the old worker thread may still be unwinding here. Wait for it
    // instead of failing with "tunnel already running".
    {
        std::unique_lock<std::mutex> lock(g_run_mtx);
        if (!g_run_cv.wait_for(lock, std::chrono::seconds(5),
                               [] { return !g_running; })) {
            napi_get_boolean(env, false, &okv);
            napi_create_string_utf8(env, "previous tunnel still stopping", NAPI_AUTO_LENGTH, &errv);
            napi_set_named_property(env, result, "ok", okv);
            napi_set_named_property(env, result, "error", errv);
            return result;
        }
        g_running = true;
    }
    auto *client = new NapiClient();
    {
        std::lock_guard<std::mutex> lock(g_client_mtx);
        g_client = client;
        g_client_ready = false;
    }

    ClientAPI::Config config;
    config.content = content;
    config.guiVersion = "harmony-openvpn 1.0";
    config.ssoMethods = ssoMethods;
    config.info = infoEnabled;
    config.connTimeout = connTimeout < 0 ? 0 : connTimeout;
    config.tunPersist = false;
    config.compressionMode = "yes";

    ClientAPI::EvalConfig eval = client->eval_config(config);
    if (eval.error) {
        emit("log", "", "eval_config error: " + eval.message);
        {
            std::lock_guard<std::mutex> lock(g_client_mtx);
            delete client;
            if (g_client == client) {
                g_client = nullptr;
            }
            g_client_ready = false;
        }
        {
            std::lock_guard<std::mutex> lock(g_run_mtx);
            g_running = false;
        }
        g_run_cv.notify_all();
        napi_get_boolean(env, false, &okv);
        napi_create_string_utf8(env, eval.message.c_str(), NAPI_AUTO_LENGTH, &errv);
        napi_set_named_property(env, result, "ok", okv);
        napi_set_named_property(env, result, "error", errv);
        return result;
    }

    if (!username.empty() || !password.empty() || !response.empty() ||
        !dynamicChallengeCookie.empty()) {
        ClientAPI::ProvideCreds creds;
        creds.username = username;
        creds.password = password;
        creds.response = response;
        creds.dynamicChallengeCookie = dynamicChallengeCookie;
        ClientAPI::Status st = client->provide_creds(creds);
        if (st.error) {
            emit("log", "", "provide_creds error: " + st.message);
            {
                std::lock_guard<std::mutex> lock(g_client_mtx);
                delete client;
                if (g_client == client) {
                    g_client = nullptr;
                }
                g_client_ready = false;
            }
            {
                std::lock_guard<std::mutex> lock(g_run_mtx);
                g_running = false;
            }
            g_run_cv.notify_all();
            napi_get_boolean(env, false, &okv);
            std::string message = st.message.empty() ? "Unable to provide VPN credentials" : st.message;
            napi_create_string_utf8(env, message.c_str(), NAPI_AUTO_LENGTH, &errv);
            napi_set_named_property(env, result, "ok", okv);
            napi_set_named_property(env, result, "error", errv);
            return result;
        }
    }

    g_worker = std::thread([client]() {
        auto *c = client;
        ClientAPI::Status st = c->connect();
        g_client_ready = false;
        emit("done", st.error ? "error" : "ok", st.message, st.error);
        {
            std::lock_guard<std::mutex> lock(g_client_mtx);
            delete c;
            if (g_client == c) {
                g_client = nullptr;
            }
        }
        {
            std::lock_guard<std::mutex> lock(g_run_mtx);
            g_running = false;
        }
        g_run_cv.notify_all();
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
    {
        std::lock_guard<std::mutex> lock(g_client_mtx);
        if (g_client != nullptr) {
            g_client->stop();
        }
    }
    {
        // unblock a pending tun establish wait
        std::lock_guard<std::mutex> lock(g_tun_mtx);
        if (g_tun_pending) {
            g_tun_fd_result = -2;
            g_tun_pending = false;
        }
    }
    g_tun_cv.notify_all();
    return nullptr;
}

napi_value GetTunStats(napi_env env, napi_callback_info)
{
    napi_value result;
    napi_create_object(env, &result);

    napi_value value;
    napi_get_boolean(env, false, &value);
    napi_set_named_property(env, result, "ok", value);
    napi_create_string_utf8(env, "", NAPI_AUTO_LENGTH, &value);
    napi_set_named_property(env, result, "error", value);

    long long bytesIn = 0;
    long long bytesOut = 0;
    long long packetsIn = 0;
    long long packetsOut = 0;
    long long errorsIn = 0;
    long long errorsOut = 0;
    {
        std::lock_guard<std::mutex> lock(g_client_mtx);
        if (g_client == nullptr || !g_running.load()) {
            napi_create_string_utf8(env, "no active OpenVPN client", NAPI_AUTO_LENGTH, &value);
            napi_set_named_property(env, result, "error", value);
            return result;
        }
        const ClientAPI::InterfaceStats stats = g_client->tun_stats();
        bytesIn = stats.bytesIn;
        bytesOut = stats.bytesOut;
        packetsIn = stats.packetsIn;
        packetsOut = stats.packetsOut;
        errorsIn = stats.errorsIn;
        errorsOut = stats.errorsOut;
    }

    napi_get_boolean(env, true, &value);
    napi_set_named_property(env, result, "ok", value);
    napi_create_double(env, static_cast<double>(bytesIn), &value);
    napi_set_named_property(env, result, "bytesIn", value);
    napi_create_double(env, static_cast<double>(bytesOut), &value);
    napi_set_named_property(env, result, "bytesOut", value);
    napi_create_double(env, static_cast<double>(packetsIn), &value);
    napi_set_named_property(env, result, "packetsIn", value);
    napi_create_double(env, static_cast<double>(packetsOut), &value);
    napi_set_named_property(env, result, "packetsOut", value);
    napi_create_double(env, static_cast<double>(errorsIn), &value);
    napi_set_named_property(env, result, "errorsIn", value);
    napi_create_double(env, static_cast<double>(errorsOut), &value);
    napi_set_named_property(env, result, "errorsOut", value);
    napi_create_string_utf8(env, "", NAPI_AUTO_LENGTH, &value);
    napi_set_named_property(env, result, "error", value);
    return result;
}

napi_value RespondCrText(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    napi_value result;
    napi_create_object(env, &result);
    napi_value okv;
    napi_value errv;
    std::string response;
    bool ok = argc >= 1 && read_str_prop(env, argv[0], "response", response);
    std::string error;
    if (!ok) {
        error = "respondCrText requires a response string";
    } else if (!g_running.load()) {
        error = "respondCrText unsupported: no active OpenVPN client";
    } else if (!g_client_ready.load()) {
        error = "respondCrText unsupported: OpenVPN control channel is not ready";
    } else {
        // OpenVPN3's CR_TEXT protocol expects a base64 encoded response. The
        // ClientAPI post_cc_msg() wrapper posts to the connection io_context
        // and is safe from this NAPI thread during the active client lifetime.
        std::lock_guard<std::mutex> lock(g_client_mtx);
        if (g_client == nullptr || !g_client_ready.load()) {
            error = "respondCrText unsupported: OpenVPN client is not active";
        } else {
            Base64 base64;
            g_client->post_cc_msg("CR_RESPONSE," + base64.encode(response));
            ok = true;
        }
    }

    napi_get_boolean(env, ok && error.empty(), &okv);
    napi_create_string_utf8(env, error.c_str(), NAPI_AUTO_LENGTH, &errv);
    napi_set_named_property(env, result, "ok", okv);
    napi_set_named_property(env, result, "error", errv);
    return result;
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
        g_tun_pending = false;
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
        {"getTunStats", nullptr, GetTunStats, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"respondCrText", nullptr, RespondCrText, nullptr, nullptr, nullptr, napi_default, nullptr},
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
