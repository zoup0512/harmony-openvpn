/**
 * Port of fragments/Utils.kt getWarningText + profile error localisation.
 */

import { VpnProfile, ProfileError } from '../core/VpnProfile';
import { R } from './Res';

export function profileErrorKey(e: ProfileError): string {
  switch (e) {
    case ProfileError.NO_KEYSTORE_CERT_SELECTED:
      return 'no_keystore_cert_selected';
    case ProfileError.NO_CA_CERT_SELECTED:
      return 'no_ca_cert_selected';
    case ProfileError.DEPRECATED_TLS_REMOTE:
      return 'deprecated_tls_remote';
    case ProfileError.IPV4_FORMAT_ERROR:
      return 'ipv4_format_error';
    case ProfileError.CUSTOM_ROUTE_FORMAT_ERROR:
      return 'custom_route_format_error';
    case ProfileError.MISSING_TLSAUTH:
      return 'missing_tlsauth';
    case ProfileError.MISSING_CERTIFICATES:
      return 'missing_certificates';
    case ProfileError.REMOTE_NO_SERVER_SELECTED:
      return 'remote_no_server_selected';
    case ProfileError.OPENVPN3_NOSTATICKEYS:
      return 'openvpn3_nostatickeys';
    case ProfileError.OPENVPN3_PKCS12:
      return 'openvpn3_pkcs12';
    case ProfileError.OPENVPN3_SOCKSPROXY:
      return 'openvpn3_socksproxy';
    case ProfileError.NO_ORBOTFOUND:
      return 'no_orbotfound';
    case ProfileError.ERROR_ORBOT_AND_PROXY_OPTIONS:
      return 'error_orbot_and_proxy_options';
    case ProfileError.BF_CBC_REQUIRES_LEGACY:
      return 'bf_cbc_requires_legacy';
    default:
      return '';
  }
}

export function profileErrorText(e: ProfileError): string {
  let key = profileErrorKey(e);
  if (key === '') {
    return '';
  }
  return R.s(key);
}

export function getWarningText(p: VpnProfile): string {
  let parts: string[] = [];
  let err = p.checkProfile(false);
  if (err !== ProfileError.NO_ERROR) {
    parts.push(profileErrorText(err));
  }
  if (p.mUseLegacyProvider) {
    parts.push('legacy Provider enabled');
  }
  if (p.mAuthenticationType === VpnProfile.TYPE_STATICKEYS) {
    parts.push('deprecated static key (--secret) mode');
  }
  if (p.mCompatMode > 0 && p.mCompatMode < 20500) {
    parts.push('compat mode enabled');
  }
  if (p.mTlSCertProfile === 'insecure') {
    parts.push("low security (TLS security profile 'insecure' selected)");
  }
  return parts.join(', ');
}
