/**
 * Basic settings tab — port of Settings_Basic + basic_settings.xml.
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { VpnProfile } from '../../core/VpnProfile';
import { FileSelectRow } from '../FileSelectRow';
import { PrefCategory, CheckRow, TapRow } from '../PrefRows';
import {
  vpnTypeEntries,
  compatModeEntries,
  compatModeToIndex,
  compatModeFromIndex,
  authRetryEntries,
  showSingleChoice
} from './SettingsCommon';

const TAB_BACKGROUND: string = Theme.DARK_BACKGROUND;
const TAB_SURFACE: string = Theme.DARK_SURFACE;
const TAB_SURFACE_ALT: string = Theme.DARK_SURFACE_ALT;
const TAB_BORDER: string = Theme.DARK_BORDER;
const TAB_TEXT: string = Theme.DARK_TEXT_PRIMARY;
const TAB_MUTED: string = Theme.DARK_TEXT_SECONDARY;
const TAB_DISABLED: string = Theme.DARK_TEXT_DISABLED;
const TAB_WARNING: string = Theme.DARK_WARNING;

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

  @Builder
  SectionHeader(title: string) {
    PrefCategory({ title: title, darkMode: true })
  }

  @Builder
  GeneralCard() {
    Column() {
      Text(R.s('profilename'))
        .fontSize(12)
        .fontColor(TAB_MUTED)
        .width('100%')
      TextInput({ text: this.name })
        .fontSize(17)
        .fontColor(TAB_TEXT)
        .backgroundColor(Theme.TRANSPARENT)
        .padding({ left: 0, right: 0, top: 6, bottom: 8 })
        .width('100%')
        .onChange((v: string) => {
          this.name = v;
          this.profile.mName = v;
        })
      Divider()
        .color(TAB_BORDER)
        .strokeWidth(1)
        .margin({ bottom: 8 })

      TapRow({
        title: R.s('compat_mode_label'),
        summary: compatModeEntries()[this.compatModeIdx],
        darkMode: true,
        onRowClick: () => {
          showSingleChoice(R.s('compat_mode_label'), compatModeEntries(), this.compatModeIdx, (i: number) => {
            this.compatModeIdx = i;
            this.profile.mCompatMode = compatModeFromIndex(i);
          });
        }
      })
      CheckRow({
        title: R.s('loadossllegacy'),
        checked: this.legacyProvider,
        darkMode: true,
        onChange: (v: boolean) => {
          this.legacyProvider = v;
          this.profile.mUseLegacyProvider = v;
        }
      })
      CheckRow({
        title: R.s('useLZO'),
        checked: this.useLzo,
        showDivider: false,
        darkMode: true,
        onChange: (v: boolean) => {
          this.useLzo = v;
          this.profile.mUseLzo = v;
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(TAB_SURFACE)
    .border({ width: 1, color: TAB_BORDER })
    .borderRadius(Theme.DARK_CARD_RADIUS)
  }

  @Builder
  AuthenticationCard() {
    Column() {
      TapRow({
        title: R.s('vpn_type'),
        summary: vpnTypeEntries()[this.authType],
        showDivider: this.showUserPW(),
        darkMode: true,
        onRowClick: () => {
          showSingleChoice(R.s('vpn_type'), vpnTypeEntries(), this.authType, (i: number) => {
            this.authType = i;
            this.profile.mAuthenticationType = i;
          });
        }
      })

      if (this.showUserPW()) {
        Text(R.s('auth_username'))
          .fontSize(12)
          .fontColor(TAB_MUTED)
          .width('100%')
          .margin({ top: 16 })
        TextInput({ text: this.username })
          .fontSize(17)
          .fontColor(TAB_TEXT)
          .backgroundColor(Theme.TRANSPARENT)
          .padding({ left: 0, right: 0, top: 6, bottom: 8 })
          .width('100%')
          .onChange((v: string) => {
            this.username = v;
            this.profile.mUsername = v;
          })
        Divider()
          .color(TAB_BORDER)
          .strokeWidth(1)

        Text(R.s('auth_pwquery'))
          .fontSize(12)
          .fontColor(TAB_MUTED)
          .width('100%')
          .margin({ top: 16 })
        TextInput({ text: this.password, placeholder: R.s('pw_query_hint') })
          .type(InputType.Password)
          .fontSize(17)
          .fontColor(TAB_TEXT)
          .placeholderColor(TAB_DISABLED)
          .backgroundColor(Theme.TRANSPARENT)
          .padding({ left: 0, right: 0, top: 6, bottom: 8 })
          .width('100%')
          .onChange((v: string) => {
            this.password = v;
            this.profile.mPassword = v;
          })
        Divider()
          .color(TAB_BORDER)
          .strokeWidth(1)
          .margin({ bottom: 8 })
        TapRow({
          title: R.s('auth_failed_behaviour'),
          summary: authRetryEntries()[this.authRetry],
          showDivider: false,
          darkMode: true,
          onRowClick: () => {
            showSingleChoice(R.s('auth_failed_behaviour'), authRetryEntries(), this.authRetry, (i: number) => {
              this.authRetry = i;
              this.profile.mAuthRetry = i;
            });
          }
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor(TAB_SURFACE)
    .border({ width: 1, color: TAB_BORDER })
    .borderRadius(Theme.DARK_CARD_RADIUS)
  }

  @Builder
  CertificateMaterialCard() {
    Column() {
      if (this.showCerts()) {
        FileSelectRow({
          title: R.s('client_certificate_title'),
          value: this.clientCert,
          certificate: true,
          suffixes: '.pem,.crt,.cer,.ovpn,.conf,.txt',
          darkMode: true,
          onSelect: (v: string) => {
            this.clientCert = v;
            this.profile.mClientCertFilename = v === '' ? undefined : v;
          }
        })
        FileSelectRow({
          title: R.s('client_key_title'),
          value: this.clientKey,
          suffixes: '.pem,.key,.ovpn,.conf,.txt',
          darkMode: true,
          onSelect: (v: string) => {
            this.clientKey = v;
            this.profile.mClientKeyFilename = v === '' ? undefined : v;
            this.keyPwNeeded = this.profile.requireTLSKeyPassword();
          }
        })
        if (this.keyPwNeeded) {
          Column() {
            Text(R.s('private_key_password'))
              .fontSize(12)
              .fontColor(TAB_MUTED)
              .width('100%')
            TextInput({ text: this.keyPassword, placeholder: R.s('pw_query_hint') })
              .type(InputType.Password)
              .fontSize(17)
              .fontColor(TAB_TEXT)
              .placeholderColor(TAB_DISABLED)
              .backgroundColor(Theme.TRANSPARENT)
              .padding({ left: 0, right: 0, top: 6, bottom: 8 })
              .width('100%')
              .onChange((v: string) => {
                this.keyPassword = v;
                this.profile.mKeyPassword = v;
              })
          }
          .width('100%')
          .padding(16)
          .alignItems(HorizontalAlign.Start)
        }
      }

      if (this.showPkcs12()) {
        FileSelectRow({
          title: R.s('client_pkcs12_title'),
          value: this.pkcs12File,
          suffixes: '.p12,.pkcs12,.pfx,.ovpn,.conf',
          darkMode: true,
          onSelect: (v: string) => {
            this.pkcs12File = v;
            this.profile.mPKCS12Filename = v === '' ? undefined : v;
          }
        })
        Column() {
          Text(R.s('pkcs12pwquery'))
            .fontSize(12)
            .fontColor(TAB_MUTED)
            .width('100%')
          TextInput({ text: this.pkcs12Password, placeholder: R.s('pw_query_hint') })
            .type(InputType.Password)
            .fontSize(17)
            .fontColor(TAB_TEXT)
            .placeholderColor(TAB_DISABLED)
            .backgroundColor(Theme.TRANSPARENT)
            .padding({ left: 0, right: 0, top: 6, bottom: 8 })
            .width('100%')
            .onChange((v: string) => {
              this.pkcs12Password = v;
              this.profile.mPKCS12Password = v;
            })
        }
        .width('100%')
        .padding(16)
        .alignItems(HorizontalAlign.Start)
      }

      if (this.authType === VpnProfile.TYPE_STATICKEYS) {
        Text(R.s('static_keys_info'))
          .fontSize(14)
          .fontColor(TAB_MUTED)
          .lineHeight(20)
          .width('100%')
          .padding(16)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(TAB_SURFACE)
    .border({ width: 1, color: TAB_BORDER })
    .borderRadius(Theme.DARK_CARD_RADIUS)
  }

  @Builder
  KeystoreUnsupportedCard() {
    Column() {
      Text(R.s('client_certificate_title'))
        .fontSize(12)
        .fontColor(TAB_MUTED)
        .width('100%')
      Text(this.profile.mAlias === undefined ? R.s('client_no_certificate') : this.profile.mAlias)
        .fontSize(17)
        .fontColor(TAB_TEXT)
        .width('100%')
        .margin({ top: 6 })
      Text(R.s('keystore_not_supported'))
        .fontSize(13)
        .fontColor(TAB_WARNING)
        .lineHeight(19)
        .width('100%')
        .padding({ top: 12 })
      Text(R.s('extracahint'))
        .fontSize(13)
        .fontColor(TAB_MUTED)
        .lineHeight(19)
        .width('100%')
        .padding({ top: 6 })
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(TAB_SURFACE)
    .border({ width: 1, color: TAB_BORDER })
    .borderRadius(Theme.DARK_CARD_RADIUS)
  }

  @Builder
  ExternalUnsupportedCard() {
    Column() {
      Text(R.s('external_authenticator'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(TAB_TEXT)
        .width('100%')
      Text(R.s('extauth_not_supported'))
        .fontSize(13)
        .fontColor(TAB_WARNING)
        .lineHeight(19)
        .width('100%')
        .padding({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(TAB_SURFACE)
    .border({ width: 1, color: TAB_BORDER })
    .borderRadius(Theme.DARK_CARD_RADIUS)
  }

  @Builder
  TrustRevocationCard() {
    Column() {
      if (this.showCaCert()) {
        FileSelectRow({
          title: R.s('ca_title'),
          value: this.caFilename,
          certificate: true,
          showClear: this.showPkcs12() || this.showKeystore(),
          darkMode: true,
          onSelect: (v: string) => {
            this.caFilename = v;
            this.profile.mCaFilename = v === '' ? undefined : v;
          }
        })
        CheckRow({
          title: R.s('check_peer_fingerprint'),
          checked: this.checkPeerFp,
          showDivider: this.checkPeerFp || this.showCrl(),
          darkMode: true,
          onChange: (v: boolean) => {
            this.checkPeerFp = v;
            this.profile.mCheckPeerFingerprint = v;
          }
        })
        if (this.checkPeerFp) {
          TextArea({ text: this.peerFps, placeholder: R.s('fingerprint') })
            .fontSize(15)
            .fontColor(TAB_TEXT)
            .placeholderColor(TAB_DISABLED)
            .backgroundColor(TAB_SURFACE_ALT)
            .border({ width: 1, color: TAB_BORDER })
            .borderRadius(Theme.DARK_INPUT_RADIUS)
            .height(100)
            .width('100%')
            .padding(12)
            .margin({ top: 8, bottom: 8 })
            .onChange((v: string) => {
              this.peerFps = v;
              this.profile.mPeerFingerPrints = v;
            })
        }
      }

      if (this.showCrl()) {
        FileSelectRow({
          title: R.s('crl_title'),
          value: this.crlFilename,
          certificate: true,
          showClear: true,
          darkMode: true,
          onSelect: (v: string) => {
            this.crlFilename = v;
            this.profile.mCrlFilename = v === '' ? undefined : v;
          }
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(TAB_SURFACE)
    .border({ width: 1, color: TAB_BORDER })
    .borderRadius(Theme.DARK_CARD_RADIUS)
  }

  build() {
    Scroll() {
      Column() {
        this.SectionHeader(R.s('basic_general_section'))
        this.GeneralCard()

        this.SectionHeader(R.s('basic_authentication_section'))
        this.AuthenticationCard()

        if (this.showCerts() || this.showPkcs12() || this.authType === VpnProfile.TYPE_STATICKEYS) {
          this.SectionHeader(R.s('basic_certificate_section'))
          this.CertificateMaterialCard()
        }

        if (this.showKeystore() || this.authType === VpnProfile.TYPE_EXTERNAL_APP) {
          this.SectionHeader(R.s('basic_unsupported_section'))
          if (this.showKeystore()) {
            this.KeystoreUnsupportedCard()
          }
          if (this.authType === VpnProfile.TYPE_EXTERNAL_APP) {
            this.ExternalUnsupportedCard()
          }
        }

        if (this.showCaCert() || this.showCrl()) {
          this.SectionHeader(R.s('basic_trust_section'))
          this.TrustRevocationCard()
        }
      }
      .width('100%')
      .backgroundColor(TAB_BACKGROUND)
      .padding({ left: 16, right: 16, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(TAB_BACKGROUND)
  }
}
