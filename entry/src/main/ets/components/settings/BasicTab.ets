/**
 * Basic settings tab — port of Settings_Basic + basic_settings.xml.
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { VpnProfile } from '../../core/VpnProfile';
import { FileSelectRow } from '../FileSelectRow';
import { TapRow } from '../PrefRows';
import {
  vpnTypeEntries,
  compatModeEntries,
  compatModeToIndex,
  compatModeFromIndex,
  authRetryEntries,
  showSingleChoice
} from './SettingsCommon';

@Component
export struct BasicTab {
  profile: VpnProfile = new VpnProfile('unset');
  @State name: string = '';
  @State compatModeIdx: number = 0;
  @State legacyProvider: boolean = false;
  @State useLzo: boolean = false;
  @State authType: number = VpnProfile.TYPE_KEYSTORE;
  @State caFilename: string = '';
  @State checkPeerFp: boolean = false;
  @State peerFps: string = '';
  @State clientCert: string = '';
  @State clientKey: string = '';
  @State keyPassword: string = '';
  @State pkcs12File: string = '';
  @State pkcs12Password: string = '';
  @State username: string = '';
  @State password: string = '';
  @State authRetry: number = 0;
  @State crlFilename: string = '';
  @State keyPwNeeded: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  load(): void {
    let p = this.profile;
    this.name = p.mName;
    this.compatModeIdx = compatModeToIndex(p.mCompatMode);
    this.legacyProvider = p.mUseLegacyProvider;
    this.useLzo = p.mUseLzo;
    this.authType = p.mAuthenticationType;
    this.caFilename = p.mCaFilename === undefined ? '' : p.mCaFilename;
    this.checkPeerFp = p.mCheckPeerFingerprint;
    this.peerFps = p.mPeerFingerPrints;
    this.clientCert = p.mClientCertFilename === undefined ? '' : p.mClientCertFilename;
    this.clientKey = p.mClientKeyFilename === undefined ? '' : p.mClientKeyFilename;
    this.keyPassword = p.mKeyPassword === undefined ? '' : p.mKeyPassword;
    this.pkcs12File = p.mPKCS12Filename === undefined ? '' : p.mPKCS12Filename;
    this.pkcs12Password = p.mPKCS12Password === undefined ? '' : p.mPKCS12Password;
    this.username = p.mUsername === undefined ? '' : p.mUsername;
    this.password = p.mPassword === undefined ? '' : p.mPassword;
    this.authRetry = p.mAuthRetry;
    this.crlFilename = p.mCrlFilename === undefined ? '' : p.mCrlFilename;
    this.keyPwNeeded = p.requireTLSKeyPassword();
  }

  private showUserPW(): boolean {
    return this.authType === VpnProfile.TYPE_USERPASS ||
      this.authType === VpnProfile.TYPE_USERPASS_CERTIFICATES ||
      this.authType === VpnProfile.TYPE_USERPASS_PKCS12 ||
      this.authType === VpnProfile.TYPE_USERPASS_KEYSTORE;
  }

  private showCerts(): boolean {
    return this.authType === VpnProfile.TYPE_CERTIFICATES ||
      this.authType === VpnProfile.TYPE_USERPASS_CERTIFICATES;
  }

  private showPkcs12(): boolean {
    return this.authType === VpnProfile.TYPE_PKCS12 ||
      this.authType === VpnProfile.TYPE_USERPASS_PKCS12;
  }

  private showKeystore(): boolean {
    return this.authType === VpnProfile.TYPE_KEYSTORE ||
      this.authType === VpnProfile.TYPE_USERPASS_KEYSTORE;
  }

  private showCaCert(): boolean {
    return this.authType !== VpnProfile.TYPE_STATICKEYS &&
      this.authType !== VpnProfile.TYPE_EXTERNAL_APP;
  }

  private showCrl(): boolean {
    return this.authType !== VpnProfile.TYPE_STATICKEYS;
  }

  build() {
    Scroll() {
      Column() {
        // ---- Profile name ----
        Text(R.s('profilename'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')
          .padding({ left: 16, top: 12, bottom: 4 })
        TextInput({ text: this.name })
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor(Theme.CARD_BG)
          .onChange((v: string) => {
            this.name = v;
            this.profile.mName = v;
          })

        TapRow({
          title: R.s('compat_mode_label'),
          summary: compatModeEntries()[this.compatModeIdx],
          onRowClick: () => {
            showSingleChoice(R.s('compat_mode_label'), compatModeEntries(), this.compatModeIdx, (i: number) => {
              this.compatModeIdx = i;
              this.profile.mCompatMode = compatModeFromIndex(i);
            });
          }
        })

        Row() {
          Checkbox()
            .select(this.legacyProvider)
            .selectedColor(Theme.PRIMARY)
            .onChange((v: boolean) => {
              this.legacyProvider = v;
              this.profile.mUseLegacyProvider = v;
            })
          Text(R.s('loadossllegacy'))
            .fontSize(15)
            .fontColor(Theme.TEXT_PRIMARY)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor(Theme.CARD_BG)
        .border({ width: { bottom: 1 }, color: '1F000000' })

        Row() {
          Checkbox()
            .select(this.useLzo)
            .selectedColor(Theme.PRIMARY)
            .onChange((v: boolean) => {
              this.useLzo = v;
              this.profile.mUseLzo = v;
            })
          Text(R.s('useLZO'))
            .fontSize(15)
            .fontColor(Theme.TEXT_PRIMARY)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 10 })
        .backgroundColor(Theme.CARD_BG)
        .border({ width: { bottom: 1 }, color: '1F000000' })

        TapRow({
          title: R.s('vpn_type'),
          summary: vpnTypeEntries()[this.authType],
          onRowClick: () => {
            showSingleChoice(R.s('vpn_type'), vpnTypeEntries(), this.authType, (i: number) => {
              this.authType = i;
              this.profile.mAuthenticationType = i;
            });
          }
        })

        // ---- Username / Password ----
        if (this.showUserPW()) {
          Text(R.s('auth_username'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .padding({ left: 16, top: 12, bottom: 4 })
          TextInput({ text: this.username })
            .width('100%')
            .padding({ left: 16, right: 16 })
            .backgroundColor(Theme.CARD_BG)
            .onChange((v: string) => {
              this.username = v;
              this.profile.mUsername = v;
            })
          Text(R.s('auth_pwquery'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .padding({ left: 16, top: 12, bottom: 4 })
          TextInput({ text: this.password, placeholder: R.s('pw_query_hint') })
            .type(InputType.Password)
            .width('100%')
            .padding({ left: 16, right: 16 })
            .backgroundColor(Theme.CARD_BG)
            .onChange((v: string) => {
              this.password = v;
              this.profile.mPassword = v;
            })
          TapRow({
            title: R.s('auth_failed_behaviour'),
            summary: authRetryEntries()[this.authRetry],
            onRowClick: () => {
              showSingleChoice(R.s('auth_failed_behaviour'), authRetryEntries(), this.authRetry, (i: number) => {
                this.authRetry = i;
                this.profile.mAuthRetry = i;
              });
            }
          })
        }

        // ---- Certificates ----
        if (this.showCerts()) {
          FileSelectRow({
            title: R.s('client_certificate_title'),
            value: this.clientCert,
            certificate: true,
            suffixes: '.pem,.crt,.cer,.ovpn,.conf,.txt',
            onSelect: (v: string) => {
              this.clientCert = v;
              this.profile.mClientCertFilename = v === '' ? undefined : v;
            }
          })
          FileSelectRow({
            title: R.s('client_key_title'),
            value: this.clientKey,
            suffixes: '.pem,.key,.ovpn,.conf,.txt',
            onSelect: (v: string) => {
              this.clientKey = v;
              this.profile.mClientKeyFilename = v === '' ? undefined : v;
              this.keyPwNeeded = this.profile.requireTLSKeyPassword();
            }
          })
          if (this.keyPwNeeded) {
            Text(R.s('private_key_password'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .padding({ left: 16, top: 12, bottom: 4 })
            TextInput({ text: this.keyPassword, placeholder: R.s('pw_query_hint') })
              .type(InputType.Password)
              .width('100%')
              .padding({ left: 16, right: 16 })
              .backgroundColor(Theme.CARD_BG)
              .onChange((v: string) => {
                this.keyPassword = v;
                this.profile.mKeyPassword = v;
              })
          }
        }

        // ---- PKCS12 ----
        if (this.showPkcs12()) {
          FileSelectRow({
            title: R.s('client_pkcs12_title'),
            value: this.pkcs12File,
            suffixes: '.p12,.pkcs12,.pfx,.ovpn,.conf',
            onSelect: (v: string) => {
              this.pkcs12File = v;
              this.profile.mPKCS12Filename = v === '' ? undefined : v;
            }
          })
          Text(R.s('pkcs12pwquery'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .padding({ left: 16, top: 12, bottom: 4 })
          TextInput({ text: this.pkcs12Password, placeholder: R.s('pw_query_hint') })
            .type(InputType.Password)
            .width('100%')
            .padding({ left: 16, right: 16 })
            .backgroundColor(Theme.CARD_BG)
            .onChange((v: string) => {
              this.pkcs12Password = v;
              this.profile.mPKCS12Password = v;
            })
        }

        // ---- Keystore (not available on HarmonyOS) ----
        if (this.showKeystore()) {
          Column() {
            Text(R.s('client_certificate_title'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .padding({ bottom: 4 })
            Text(this.profile.mAlias === undefined ? R.s('client_no_certificate') : this.profile.mAlias)
              .fontSize(14)
              .fontColor(Theme.TEXT_SECONDARY)
              .width('100%')
            Text(R.s('keystore_not_supported'))
              .fontSize(13)
              .fontColor(Theme.WARNING_RED)
              .width('100%')
              .padding({ top: 4 })
            Text(R.s('extracahint'))
              .fontSize(13)
              .fontColor(Theme.TEXT_SECONDARY)
              .width('100%')
              .padding({ top: 4 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor(Theme.CARD_BG)
          .alignItems(HorizontalAlign.Start)
          .border({ width: { bottom: 1 }, color: '1F000000' })
        }

        // ---- Static keys ----
        if (this.authType === VpnProfile.TYPE_STATICKEYS) {
          Text(R.s('static_keys_info'))
            .fontSize(14)
            .fontColor(Theme.TEXT_SECONDARY)
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.CARD_BG)
        }

        // ---- External auth ----
        if (this.authType === VpnProfile.TYPE_EXTERNAL_APP) {
          Column() {
            Text(R.s('external_authenticator'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .padding({ bottom: 4 })
            Text(R.s('extauth_not_supported'))
              .fontSize(13)
              .fontColor(Theme.WARNING_RED)
              .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor(Theme.CARD_BG)
          .alignItems(HorizontalAlign.Start)
          .border({ width: { bottom: 1 }, color: '1F000000' })
        }

        // ---- CA certificate ----
        if (this.showCaCert()) {
          FileSelectRow({
            title: R.s('ca_title'),
            value: this.caFilename,
            certificate: true,
            showClear: this.showPkcs12() || this.showKeystore(),
            onSelect: (v: string) => {
              this.caFilename = v;
              this.profile.mCaFilename = v === '' ? undefined : v;
            }
          })
          Row() {
            Checkbox()
              .select(this.checkPeerFp)
              .selectedColor(Theme.PRIMARY)
              .onChange((v: boolean) => {
                this.checkPeerFp = v;
                this.profile.mCheckPeerFingerprint = v;
              })
            Text(R.s('check_peer_fingerprint'))
              .fontSize(15)
              .fontColor(Theme.TEXT_PRIMARY)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor(Theme.CARD_BG)
          if (this.checkPeerFp) {
            TextArea({ text: this.peerFps, placeholder: R.s('fingerprint') })
              .width('100%')
              .padding({ left: 16, right: 16 })
              .backgroundColor(Theme.CARD_BG)
              .height(100)
              .onChange((v: string) => {
                this.peerFps = v;
                this.profile.mPeerFingerPrints = v;
              })
          }
        }

        // ---- CRL ----
        if (this.showCrl()) {
          FileSelectRow({
            title: R.s('crl_title'),
            value: this.crlFilename,
            certificate: true,
            showClear: true,
            onSelect: (v: string) => {
              this.crlFilename = v;
              this.profile.mCrlFilename = v === '' ? undefined : v;
            }
          })
        }
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
