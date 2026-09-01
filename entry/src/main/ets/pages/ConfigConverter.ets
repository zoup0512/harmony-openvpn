/**
 * Config converter — port of ConfigConverter: parses an imported .ovpn
 * file / downloaded profile, lets the user pick a profile name, compat mode,
 * TLS profile, make default, resolve missing referenced files, shows the
 * import log and finally saves the profile.
 */

import { router, promptAction } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { R } from '../common/Res';
import { VpnProfile } from '../core/VpnProfile';
import { ProfileManager } from '../core/ProfileManager';
import { ConfigParser, ConfigParseError } from '../core/ConfigParser';
import { FileSelectRow } from '../components/FileSelectRow';
import { showSingleChoice, compatModeEntries, compatModeToIndex, compatModeFromIndex,
  tlsProfileEntries, tlsProfileValues } from '../components/settings/SettingsCommon';

interface ConverterRouteParams {
  text: string;
  fileName: string;
}

@Entry
@Component
struct ConfigConverter {
  private profile: VpnProfile = new VpnProfile('unset');
  @State loadedOk: boolean = false;
  @State errorText: string = '';
  @State name: string = '';
  @State compatIdx: number = 0;
  @State tlsProfile: string = 'legacy';
  @State makeDefault: boolean = false;
  @State missingCa: string = '';
  @State missingCert: string = '';
  @State missingKey: string = '';
  @State missingPkcs12: string = '';
  @State missingTlsAuth: string = '';
  @State missingCrl: string = '';
  @State importLog: string = '';

  aboutToAppear(): void {
    let params = router.getParams() as ConverterRouteParams;
    if (params === undefined || params === null || params.text === undefined) {
      this.errorText = R.s('import_error_message');
      return;
    }
    try {
      let parser = new ConfigParser();
      let lines = (params.text as string).replace(/\r\n/g, '\n').split('\n');
      parser.parseConfig(lines);
      let np = parser.convertProfile();
      this.profile = np;
      let fileName = params.fileName === undefined || params.fileName === null ? '' : params.fileName;
      let possibleName = fileName.replace(/\.(ovpn|conf)$/i, '');
      this.name = this.uniqueName(np.mName === ConfigParser.CONVERTED_PROFILE ? possibleName : np.mName);
      this.compatIdx = compatModeToIndex(np.mCompatMode);
      this.tlsProfile = np.mTlSCertProfile === '' ? 'legacy' : np.mTlSCertProfile;
      this.collectMissingFiles();
      this.buildImportLog(params.fileName);
      this.loadedOk = true;
    } catch (e) {
      if (e instanceof ConfigParseError) {
        this.errorText = e.message;
      } else {
        this.errorText = `${e}`;
      }
    }
  }

  private uniqueName(base: string): string {
    if (base !== '' && ProfileManager.getProfileByName(base) === undefined) {
      return base;
    }
    let prefix = base !== '' ? base : R.s('converted_profile');
    if (ProfileManager.getProfileByName(prefix) === undefined) {
      return prefix;
    }
    let i = 1;
    while (ProfileManager.getProfileByName(`${prefix} ${i}`) !== undefined) {
      i++;
    }
    return `${prefix} ${i}`;
  }

  private isMissing(v?: string): string {
    if (v === undefined || v === null) {
      return '';
    }
    if (VpnProfile.isEmbedded(v)) {
      return '';
    }
    return v;
  }

  private collectMissingFiles(): void {
    this.missingCa = this.isMissing(this.profile.mCaFilename);
    this.missingCert = this.isMissing(this.profile.mClientCertFilename);
    this.missingKey = this.isMissing(this.profile.mClientKeyFilename);
    this.missingPkcs12 = this.isMissing(this.profile.mPKCS12Filename);
    this.missingTlsAuth = this.isMissing(this.profile.mTLSAuthFilename);
    this.missingCrl = this.isMissing(this.profile.mCrlFilename);
  }

  private hasMissing(): boolean {
    return this.missingCa !== '' || this.missingCert !== '' || this.missingKey !== '' ||
      this.missingPkcs12 !== '' || this.missingTlsAuth !== '' || this.missingCrl !== '';
  }

  private buildImportLog(fileName: string): void {
    let lines: string[] = [];
    if (fileName !== '') {
      lines.push(`${R.s('file_imported_from', fileName)}`);
    }
    lines.push(R.s('import_done'));
    if (this.profile.mUseCustomConfig) {
      lines.push(R.s('custom_options_imported'));
    }
    this.importLog = lines.join('\n');
  }

  private saveProfile(): void {
    if (this.name === '' || ProfileManager.getProfileByName(this.name) !== undefined) {
      promptAction.showToast({ message: R.s('duplicate_profile_name') });
      return;
    }
    let p = this.profile;
    p.mName = this.name;
    p.mCompatMode = compatModeFromIndex(this.compatIdx);
    p.mTlSCertProfile = this.tlsProfile;
    p.addChangeLogEntry('Profile created via ConfigConverter');
    ProfileManager.addProfile(p);
    if (this.makeDefault) {
      ProfileManager.setAlwaysOnVPN(p.getUUID());
    }
    promptAction.showToast({ message: R.s('import_done') });
    router.back();
  }

  build() {
    Column() {
      // ---- Toolbar ----
      Row() {
        Text(R.s('import_configuration_file'))
          .fontSize(18)
          .fontColor(Color.White)
          .layoutWeight(1)
          .padding({ left: 16 })
        Image($r('app.media.ic_close'))
          .width(22).height(22).fillColor(Color.White)
          .margin({ left: 8 })
          .onClick(() => {
            router.back();
          })
        Image($r('app.media.ic_save'))
          .width(22).height(22).fillColor(Color.White)
          .margin({ left: 12, right: 12 })
          .enabled(this.loadedOk)
          .onClick(() => {
            this.saveProfile();
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor(Theme.PRIMARY)
      .alignItems(VerticalAlign.Center)

      if (!this.loadedOk) {
        Column() {
          Text(R.s('error_importing_file'))
            .fontSize(18)
            .fontColor(Theme.WARNING_RED)
          Text(this.errorText)
            .fontSize(14)
            .fontColor(Theme.TEXT_SECONDARY)
            .padding({ top: 8 })
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .layoutWeight(1)
      } else {
        Scroll() {
          Column() {
            // Profile name
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
              })

            // compat mode
            Row() {
              Text(R.s('compat_mode_label'))
                .fontSize(14)
                .fontColor(Theme.TEXT_PRIMARY)
                .layoutWeight(1)
              Text(compatModeEntries()[this.compatIdx])
                .fontSize(14)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12 })
            .onClick(() => {
              showSingleChoice(R.s('compat_mode_label'), compatModeEntries(), this.compatIdx, (i: number) => {
                this.compatIdx = i;
              });
            })

            // tls profile
            Row() {
              Text(R.s('tls_profile'))
                .fontSize(14)
                .fontColor(Theme.TEXT_PRIMARY)
                .layoutWeight(1)
              Text(this.tlsProfile)
                .fontSize(14)
                .fontColor(Theme.TEXT_SECONDARY)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12 })
            .onClick(() => {
              let values = tlsProfileValues();
              showSingleChoice(R.s('tls_profile'), tlsProfileEntries(), values.indexOf(this.tlsProfile),
                (i: number) => {
                  this.tlsProfile = values[i];
                });
            })

            // make default
            Row() {
              Checkbox()
                .select(this.makeDefault)
                .selectedColor(Theme.PRIMARY)
                .onChange((v: boolean) => {
                  this.makeDefault = v;
                })
              Text(R.s('make_default_profile'))
                .fontSize(14)
                .fontColor(Theme.TEXT_PRIMARY)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12 })

            // missing files
            if (this.hasMissing()) {
              Text(R.s('files_missing_hint'))
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.WARNING_RED)
                .width('100%')
                .padding({ left: 16, top: 16, bottom: 4 })
              if (this.missingCa !== '') {
                FileSelectRow({
                  title: R.s('ca_title'),
                  value: '',
                  certificate: true,
                  onSelect: (v: string) => {
                    this.missingCa = v === '' ? this.missingCa : '';
                    this.profile.mCaFilename = v === '' ? this.profile.mCaFilename : v;
                  }
                })
              }
              if (this.missingCert !== '') {
                FileSelectRow({
                  title: R.s('client_certificate_title'),
                  value: '',
                  certificate: true,
                  onSelect: (v: string) => {
                    this.missingCert = v === '' ? this.missingCert : '';
                    this.profile.mClientCertFilename = v === '' ? this.profile.mClientCertFilename : v;
                  }
                })
              }
              if (this.missingKey !== '') {
                FileSelectRow({
                  title: R.s('client_key_title'),
                  value: '',
                  onSelect: (v: string) => {
                    this.missingKey = v === '' ? this.missingKey : '';
                    this.profile.mClientKeyFilename = v === '' ? this.profile.mClientKeyFilename : v;
                  }
                })
              }
              if (this.missingPkcs12 !== '') {
                FileSelectRow({
                  title: R.s('client_pkcs12_title'),
                  value: '',
                  suffixes: '.p12,.pkcs12,.pfx,.ovpn,.conf',
                  onSelect: (v: string) => {
                    this.missingPkcs12 = v === '' ? this.missingPkcs12 : '';
                    this.profile.mPKCS12Filename = v === '' ? this.profile.mPKCS12Filename : v;
                  }
                })
              }
              if (this.missingTlsAuth !== '') {
                FileSelectRow({
                  title: R.s('tls_auth_file'),
                  value: '',
                  onSelect: (v: string) => {
                    this.missingTlsAuth = v === '' ? this.missingTlsAuth : '';
                    this.profile.mTLSAuthFilename = v === '' ? this.profile.mTLSAuthFilename : v;
                  }
                })
              }
              if (this.missingCrl !== '') {
                FileSelectRow({
                  title: R.s('crl_title'),
                  value: '',
                  certificate: true,
                  onSelect: (v: string) => {
                    this.missingCrl = v === '' ? this.missingCrl : '';
                    this.profile.mCrlFilename = v === '' ? this.profile.mCrlFilename : v;
                  }
                })
              }
            }

            // import log
            Text(R.s('import_log'))
              .fontSize(16)
              .fontColor(Theme.TEXT_PRIMARY)
              .width('100%')
              .padding({ left: 16, top: 16, bottom: 4 })
            Text(this.importLog)
              .fontSize(13)
              .fontColor(Theme.TEXT_SECONDARY)
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 16 })
          }
          .width('100%')
        }
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
