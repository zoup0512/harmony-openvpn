/**
 * NAPI bridge to the bundled Go frpc core (libfrp_host.so).
 * Only the in-process fallback entry is exposed here; the native child
 * process path enters through libfrp_host.so:Main directly.
 */

/**
 * Starts one frpc instance described by the JSON payload
 * (see FrpRuntimeAdapter entryParams). Returns 0 when the host
 * accepted the request, non-zero on invalid parameters.
 */
export const runFrpHost: (paramsJson: string) => number;
