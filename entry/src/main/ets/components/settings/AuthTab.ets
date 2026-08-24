/**
 * Authentication/Encryption tab — port of Settings_Authentication +
 * vpn_authentification.xml (including the RemoteCN dialog).
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { VpnProfile } from '../../core/VpnProfile';
import { PrefCategory, SwitchRow, CheckRow, TapRow } from '../PrefRows';
import { FileSelectRow } from '../FileSelectRow';
import { InputDialog, InputDialogModel } from '../InputDialog';
import { showSingleChoice, tlsDirectionEntries, tlsDirectionValues, tlsProfileEntries, tlsProfileValues,
  x509VerifyLabel, x509VerifyEntries } from './SettingsCommon';

@Component
export struct AuthTab {
  profile: VpnProfile = new VpnProfile('unset');
  @State tlsProfile: string = '';
  @State expectTLSCert: boolean = false;
  @State checkRemoteCN: boolean = true;
  @State remoteCN: string = '';
  @State x509AuthType: number = VpnProfile.X509_VERIFY_TLSREMOTE_RDN;
  @State x509UserField: string = '';
  @State useTLSAuth: boolean = false;
  @State tlsAuthFile: string = '';
  @State tlsDirection: string = '';
  @State dataCiphers: string = '';
  @State auth: string = '';
  private editModel: InputDialogModel = new InputDialogModel();
  private editDialog: CustomDialogController = new CustomDialogController({
    builder: InputDialog({ model: this.editModel }),
    autoCancel: true,
    customStyle: true
  });
  private cnModel: InputDialogModel = new InputDialogModel();
  private cnDialog: CustomDialogController = new CustomDialogController({
    builder: InputDialog({ model: this.cnModel }),
    autoCancel: true,
    customStyle: true
  });

  aboutToAppear(): void {
    let p = this.profile;
    this.tlsProfile = p.mTlSCertProfile;
    this.expectTLSCert = p.mExpectTLSCert;
    this.checkRemoteCN = p.mCheckRemoteCN;
    this.remoteCN = p.mRemoteCN;
    this.x509AuthType = p.mX509AuthType;
    this.x509UserField = p.mx509UsernameField === undefined ? '' : p.mx509UsernameField;
    this.useTLSAuth = p.mUseTLSAuth;
    this.tlsAuthFile = p.mTLSAuthFilename === undefined ? '' : p.mTLSAuthFilename;
    this.tlsDirection = p.mTLSAuthDirection;
    this.dataCiphers = p.mDataCiphers;
    this.auth = p.mAuth;
  }

  private isStaticKeys(): boolean {
    return this.profile.mAuthenticationType === VpnProfile.TYPE_STATICKEYS;
  }

  private promptEdit(titleKey: string, messageKey: string, initial: string, onOk: (v: string) => void): void {
    this.editModel.title = R.s(titleKey);
    this.editModel.message = messageKey === '' ? '' : R.s(messageKey);
    this.editModel.initial = initial;
    this.editModel.multiLine = false;
    this.editModel.okText = R.s('ok');
    this.editModel.cancelText = R.s('cancel');
    this.editModel.neutralText = '';
    this.editModel.onOk = onOk;
    this.editDialog.open();
  }

  private remotecnSummary(): string {
    if (this.remoteCN === '') {
      if (this.profile.mConnections.length > 0) {
        return `rdn: ${this.profile.mConnections[0].mServerName}`;
      }
      return R.s('no_remote_defined');
    }
    switch (this.x509AuthType) {
      case VpnProfile.X509_VERIFY_TLSREMOTE:
      case VpnProfile.X509_VERIFY_TLSREMOTE_COMPAT_NOREMAPPING:
        return `tls-remote ${this.remoteCN}`;
      case VpnProfile.X509_VERIFY_TLSREMOTE_DN:
        return `dn: ${this.remoteCN}`;
      case VpnProfile.X509_VERIFY_TLSREMOTE_RDN_PREFIX:
        return `rdn prefix: ${this.remoteCN}`;
      default:
        return `rdn: ${this.remoteCN}`;
    }
  }

  private tlsAuthFileSummary(): string {
    if (this.tlsAuthFile.startsWith(VpnProfile.INLINE_TAG)) {
      return R.s('inline_file_data');
    }
    if (this.tlsAuthFile.startsWith(VpnProfile.DISPLAYNAME_TAG)) {
      return R.s('imported_from_file', VpnProfile.getDisplayName(this.tlsAuthFile));
    }
    if (this.tlsAuthFile === '') {
      return R.s('no_certificate');
    }
    return this.tlsAuthFile;
  }

  private openRemoteCnDialog(): void {
    // first select the verify type, then ask for the name
    let types = x509VerifyEntries(this.x509AuthType, this.remoteCN);
    let entries: string[] = [];
    for (let t of types) {
      entries.push(x509VerifyLabel(t));
    }
    showSingleChoice(R.s('enter_tlscn_title'), entries, types.indexOf(this.x509AuthType), (i: number) => {
      this.x509AuthType = types[i];
      this.profile.mX509AuthType = types[i];
      this.cnModel.title = R.s('enter_tlscn_title');
      this.cnModel.message = R.s('enter_tlscn_dialog');
      this.cnModel.initial = this.remoteCN;
      this.cnModel.placeholder = '';
      this.cnModel.okText = R.s('ok');
      this.cnModel.cancelText = R.s('cancel');
      this.cnModel.neutralText = '';
      this.cnModel.onOk = (v: string) => {
        this.remoteCN = v;
        this.profile.mRemoteCN = v;
      };
      this.cnDialog.open();
    });
  }

  build() {
    Scroll() {
      Column() {
        PrefCategory({ title: R.s('tls_settings') })
        TapRow({
          title: R.s('tls_profile'),
          summary: this.tlsProfile === '' ? R.s('tls_profile_legacy') : this.tlsProfile,
          onRowClick: () => {
            let values = tlsProfileValues();
            let idx = values.indexOf(this.tlsProfile);
            showSingleChoice(R.s('tls_profile'), tlsProfileEntries(), idx, (i: number) => {
              this.tlsProfile = values[i];
              this.profile.mTlSCertProfile = values[i];
            });
          }
        })
        CheckRow({
          title: R.s('check_remote_tlscert_title'),
          summary: R.s('check_remote_tlscert'),
          checked: this.expectTLSCert,
          rowEnabled: !this.isStaticKeys(),
          onChange: (v: boolean) => {
            this.expectTLSCert = v;
            this.profile.mExpectTLSCert = v;
          }
        })
        CheckRow({
          title: R.s('remote_tlscn_check_title'),
          summary: R.s('remote_tlscn_check_summary'),
          checked: this.checkRemoteCN,
          rowEnabled: !this.isStaticKeys(),
          onChange: (v: boolean) => {
            this.checkRemoteCN = v;
            this.profile.mCheckRemoteCN = v;
          }
        })
        if (this.checkRemoteCN) {
          TapRow({
            title: R.s('enter_tlscn_title'),
            summary: this.remotecnSummary(),
            onRowClick: () => {
              this.openRemoteCnDialog();
            }
          })
          TapRow({
            title: R.s('x509_username_field'),
            summary: this.x509UserField === '' ? 'CN (default)' : this.x509UserField,
            onRowClick: () => {
              this.promptEdit('x509_username_field', 'x509_username_field_summary', this.x509UserField,
                (v: string) => {
                  this.x509UserField = v;
                  this.profile.mx509UsernameField = v === '' ? undefined : v;
                });
            }
          })
        }

        PrefCategory({ title: R.s('tls_authentication') })
        SwitchRow({
          title: R.s('useTLSAuth'),
          summary: R.s('tls_key_auth'),
          checked: this.useTLSAuth,
          onChange: (v: boolean) => {
            this.useTLSAuth = v;
            this.profile.mUseTLSAuth = v;
          }
        })
        if (this.useTLSAuth) {
          FileSelectRow({
            title: R.s('tls_auth_file'),
            value: this.tlsAuthFile,
            onSelect: (v: string) => {
              this.tlsAuthFile = v;
              this.profile.mTLSAuthFilename = v === '' ? undefined : v;
            }
          })
          TapRow({
            title: R.s('tls_direction'),
            summary: tlsDirectionEntries()[tlsDirectionValues().indexOf(this.tlsDirection)],
            onRowClick: () => {
              let values = tlsDirectionValues();
              showSingleChoice(R.s('tls_direction'), tlsDirectionEntries(), values.indexOf(this.tlsDirection),
                (i: number) => {
                  this.tlsDirection = values[i];
                  this.profile.mTLSAuthDirection = values[i];
                });
            }
          })
        }

        PrefCategory({ title: R.s('encryption') })
        TapRow({
          title: R.s('encryption_cipher'),
          summary: this.dataCiphers,
          onRowClick: () => {
            this.promptEdit('encryption_cipher', 'chipher_dialog_message', this.dataCiphers, (v: string) => {
              this.dataCiphers = v;
              this.profile.mDataCiphers = v;
            });
          }
        })
        TapRow({
          title: R.s('packet_auth'),
          summary: this.auth,
          onRowClick: () => {
            this.promptEdit('packet_auth', 'auth_dialog_message', this.auth, (v: string) => {
              this.auth = v;
              this.profile.mAuth = v;
            });
          }
        })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
