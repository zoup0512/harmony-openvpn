/**
 * Main page — replicates MainActivity: toolbar + ViewPager with the tabs
 * Profiles / Graph / Settings. FAQ content is available from About.
 */

import { router, promptAction } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { R } from '../common/Res';
import { GP } from '../common/GP';
import { FileUtil } from '../common/FileUtil';
import { ImportASDialog } from '../components/dialogs/ImportASDialog';
import { ImportSourceDialog } from '../components/dialogs/ImportSourceDialog';
import { ProfilesTab } from '../components/tabs/ProfilesTab';
import { GraphTab } from '../components/tabs/GraphTab';
import { SettingsTab } from '../components/tabs/SettingsTab';
import { InputDialog, InputDialogModel } from '../components/InputDialog';
import { CredentialsDialog, CredentialsDialogModel } from '../components/CredentialsDialog';
import { VpnController, PendingAuthChallenge } from '../vpn/VpnController';
import { VpnStatus } from '../core/VpnStatus';
import { ConnectionStatus, LogLevel } from '../core/LogItem';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State sortTick: number = 0;
  private authTimerId: number = -1;
  private activeAuthExpiresAt: number = 0;
  private authDialogOpen: boolean = false;
  private credentialsDialogOpen: boolean = false;
  private authModel: InputDialogModel = new InputDialogModel();
  private credentialsModel: CredentialsDialogModel = new CredentialsDialogModel();
  private authDialogController: CustomDialogController = new CustomDialogController({
    builder: InputDialog({ model: this.authModel }),
    autoCancel: false,
    customStyle: true
  });
  private credentialsDialogController: CustomDialogController = new CustomDialogController({
    builder: CredentialsDialog({ model: this.credentialsModel }),
    autoCancel: false,
    customStyle: true
  });
  private asDialogController: CustomDialogController = new CustomDialogController({
    builder: ImportASDialog({}),
    autoCancel: true,
    customStyle: true
  });
  private importSourceDialogController: CustomDialogController = new CustomDialogController({
    builder: ImportSourceDialog({
      onLocal: () => {
        this.importConfigFile();
      },
      onCloud: () => {
        this.asDialogController.open();
      }
    }),
    autoCancel: true,
    customStyle: true,
    alignment: DialogAlignment.Center
  });

  aboutToAppear(): void {
    let ctx = this.getUIContext().getHostContext();
    if (ctx !== undefined) {
      R.init(ctx);
    }
    this.authTimerId = setInterval(() => {
      this.checkPendingAuth();
    }, 500) as number;
  }

  aboutToDisappear(): void {
    if (this.authTimerId !== -1) {
      clearInterval(this.authTimerId);
      this.authTimerId = -1;
    }
  }

  private checkPendingAuth(): void {
    let challenge = VpnController.readPendingAuthChallenge();
    if (challenge === undefined || challenge.expiresAt <= Date.now()) {
      if (this.activeAuthExpiresAt !== 0) {
        if (this.authDialogOpen) {
          this.authDialogController.close();
          this.authDialogOpen = false;
        }
        if (this.credentialsDialogOpen) {
          this.credentialsDialogController.close();
          this.credentialsDialogOpen = false;
        }
        this.activeAuthExpiresAt = 0;
        VpnController.clearPendingAuthChallenge();
        VpnStatus.updateStateString('NOPROCESS', R.s('otp_expired'), ConnectionStatus.LEVEL_NOTCONNECTED);
        VpnController.stopVpn().catch(() => {
        });
      }
      return;
    }
    if (this.activeAuthExpiresAt === challenge.expiresAt) {
      return;
    }
    if (challenge.kind === 'credentials') {
      this.activeAuthExpiresAt = challenge.expiresAt;
      VpnStatus.logMessage(LogLevel.INFO,
        `[auth-ui] showing credentials dialog (hasResponse=${challenge.response !== ''}, ` +
        `hasCookie=${challenge.cookie !== ''}).`);
      this.showCredentialsDialog(challenge);
      return;
    }
    let pending = new PendingAuthChallenge();
    pending.uuid = challenge.uuid;
    pending.kind = challenge.kind;
    pending.challenge = challenge.challenge;
    pending.echo = challenge.echo;
    pending.responseRequired = challenge.responseRequired;
    pending.cookie = challenge.cookie;
    pending.expiresAt = challenge.expiresAt;
    this.activeAuthExpiresAt = pending.expiresAt;
    VpnStatus.logMessage(LogLevel.INFO,
      `[auth-ui] showing OTP dialog (kind=${challenge.kind}, hasCookie=${challenge.cookie !== ''}).`);
    this.authModel.title = R.s('otp_title');
    this.authModel.message = pending.challenge === '' ? R.s('otp_message') : pending.challenge;
    this.authModel.placeholder = R.s('otp_placeholder');
    this.authModel.initial = '';
    this.authModel.isPassword = !pending.echo;
    this.authModel.okText = R.s('submit');
    this.authModel.cancelText = R.s('cancel');
    this.authModel.neutralText = '';
    this.authModel.validate = (value: string): boolean => {
      if (pending.responseRequired && value.trim() === '') {
        promptAction.showToast({ message: R.s('otp_required') });
        return false;
      }
      return true;
    };
    this.authModel.onOk = (value: string) => {
      this.authDialogOpen = false;
      this.submitPendingAuth(pending, value);
    };
    this.authModel.onCancel = () => {
      this.authDialogOpen = false;
      VpnController.clearPendingAuthChallenge();
      this.activeAuthExpiresAt = 0;
      VpnStatus.updateStateString('NOPROCESS', R.s('state_disconnected'), ConnectionStatus.LEVEL_NOTCONNECTED);
      VpnController.stopVpn().catch(() => {
      });
    };
    this.authDialogOpen = true;
    this.authDialogController.open();
  }

  private showCredentialsDialog(challenge: PendingAuthChallenge): void {
    this.credentialsModel.title = R.s('credentials_title');
    this.credentialsModel.message = R.s('credentials_message');
    this.credentialsModel.username = challenge.username;
    this.credentialsModel.password = '';
    this.credentialsModel.usernamePlaceholder = R.s('credentials_username_placeholder');
    this.credentialsModel.passwordPlaceholder = R.s('credentials_password_placeholder');
    this.credentialsModel.okText = R.s('submit');
    this.credentialsModel.cancelText = R.s('cancel');
    this.credentialsModel.onOk = (username: string, password: string): boolean => {
      let trimmedUsername = username.trim();
      if (trimmedUsername === '' || password === '') {
        promptAction.showToast({ message: R.s('credentials_required') });
        return false;
      }
      this.credentialsDialogOpen = false;
      VpnController.clearPendingAuthChallenge();
      this.activeAuthExpiresAt = 0;
      // An OTP collected before the password was available rides back with
      // the credentials so the same challenge round completes.
      VpnController.startVpn(challenge.uuid, 'credentials', challenge.response, challenge.cookie, '',
        trimmedUsername, password).catch(() => {
        VpnController.writePendingAuthChallenge(challenge);
        this.activeAuthExpiresAt = 0;
        promptAction.showToast({ message: R.s('auth_submit_failed') });
      });
      return true;
    };
    this.credentialsModel.onCancel = () => {
      this.credentialsDialogOpen = false;
      VpnController.clearPendingAuthChallenge();
      this.activeAuthExpiresAt = 0;
      VpnStatus.updateStateString('NOPROCESS', R.s('state_disconnected'), ConnectionStatus.LEVEL_NOTCONNECTED);
      VpnController.stopVpn().catch(() => {
      });
    };
    this.credentialsDialogOpen = true;
    this.credentialsDialogController.open();
  }

  private submitPendingAuth(challenge: PendingAuthChallenge, value: string): void {
    // Authenticator apps often render codes with grouping spaces ("123 456");
    // an OTP never contains whitespace, so strip all of it.
    let response = value.replace(/\s/g, '');
    VpnController.clearPendingAuthChallenge();
    this.activeAuthExpiresAt = 0;
    promptAction.showToast({ message: R.s('otp_retrying') });
    let reason = challenge.kind === 'cr_text' ? 'otp-cr-text' : 'otp';
    let cookie = challenge.kind === 'cr_text' ? '' : challenge.cookie;
    VpnController.startVpn(challenge.uuid, reason, response, cookie, challenge.kind).catch(() => {
      if (challenge.expiresAt <= Date.now()) {
        VpnStatus.updateStateString('NOPROCESS', R.s('otp_expired'), ConnectionStatus.LEVEL_NOTCONNECTED);
        return;
      }
      VpnController.writePendingAuthChallenge(challenge);
      this.activeAuthExpiresAt = 0;
      promptAction.showToast({ message: R.s('auth_submit_failed') });
    });
  }

  private changeSorting(): void {
    let byLru = !GP.getBool('sortProfilesByLRU', false);
    GP.setBool('sortProfilesByLRU', byLru);
    promptAction.showToast({
      message: byLru ? R.s('sorted_lru') : R.s('sorted_az')
    });
    this.sortTick++;
  }

  private importConfigFile(): void {
    FileUtil.pickAndRead(['.ovpn', '.conf']).then((f) => {
      let params: Record<string, Object> = {
        'text': f.content,
        'fileName': f.name
      };
      let opt: router.RouterOptions = {
        url: 'pages/ConfigConverter',
        params: params
      };
      router.pushUrl(opt);
    }).catch(() => {
    });
  }

  private showImportChoices(): void {
    this.importSourceDialogController.open();
  }

  private tabTitle(i: number): string {
    switch (i) {
      case 0:
        return R.s('vpn_list_title');
      case 1:
        return R.s('graph');
      case 2:
        return R.s('generalsettings');
      default:
        return '';
    }
  }

  build() {
    Column() {
      // ---- Toolbar (replicates ActionBar + fragment menus) ----
      Row() {
        Text(R.s('app_name'))
          .fontSize(20)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .layoutWeight(1)
          .padding({ left: 16 })

        if (this.currentIndex === 0) {
          Image($r('app.media.ic_import'))
            .width(24).height(24).fillColor(Color.White)
            .margin({ left: 16 })
            .onClick(() => {
              this.showImportChoices();
            })
          Image($r('app.media.ic_sort'))
            .width(24).height(24).fillColor(Color.White)
            .margin({ left: 16 })
            .onClick(() => {
              this.changeSorting();
            })
        }

        Image($r('app.media.ic_receipt'))
          .width(24).height(24).fillColor(Color.White)
          .margin({ left: 16 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/LogWindow' });
          })

        Image($r('app.media.ic_info'))
          .width(24)
          .height(24)
          .fillColor(Color.White)
          .margin({ left: 16, right: 16 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/About' });
          })
      }
      .width('100%')
      .height(56)
      .backgroundColor(Theme.PRIMARY)
      .alignItems(VerticalAlign.Center)

      // ---- Tab bar ----
      Row() {
        ForEach([0, 1, 2], (i: number) => {
          Column() {
            Text(this.tabTitle(i))
              .fontSize(14)
              .fontColor(Color.White)
              .maxLines(1)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            Divider()
              .color(this.currentIndex === i ? Theme.ACCENT : '#00000000')
              .strokeWidth(4)
          }
          .onClick(() => {
            this.currentIndex = i;
          })
          .layoutWeight(1)
        }, (i: number) => `${i}`)
      }
      .width('100%')
      .backgroundColor(Theme.PRIMARY)
      .alignItems(VerticalAlign.Bottom)

      // ---- Content ----
      Tabs({ index: this.currentIndex, barPosition: BarPosition.Start }) {
        TabContent() {
          ProfilesTab({
            sortTick: this.sortTick,
            onImportProfile: () => {
              this.importConfigFile();
            }
          })
        }
        .tabBar('')

        TabContent() {
          GraphTab()
        }
        .tabBar('')

        TabContent() {
          SettingsTab()
        }
        .tabBar('')
      }
      .scrollable(true)
      .barHeight(0)
      .onChange((index: number) => {
        this.currentIndex = index;
      })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
