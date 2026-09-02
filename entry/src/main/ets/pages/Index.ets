/**
 * Main page — replicates MainActivity: toolbar + the VPN profile list.
 * Traffic statistics, the log window and the about/FAQ page open as pages
 * from the toolbar. The general settings entry is hidden while the settings
 * page has no effective options.
 */

import { router, promptAction } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { R } from '../common/Res';
import { FileUtil } from '../common/FileUtil';
import { ImportASDialog } from '../components/dialogs/ImportASDialog';
import { ImportSourceDialog } from '../components/dialogs/ImportSourceDialog';
import { ProfilesTab } from '../components/tabs/ProfilesTab';
import { FrpTab } from '../components/tabs/FrpTab';
import { FrpTemplateDialog } from '../components/dialogs/FrpTemplateDialog';
import { FrpConfigTemplate, FrpTemplateManager } from '../core/FrpTemplateManager';
import { FrpConfig } from '../core/FrpConfig';
import { FrpConfigManager } from '../core/FrpConfigManager';
import { FrpType } from '../core/FrpType';
import { FrpController } from '../frp/FrpController';
import { showSingleChoice } from '../components/settings/SettingsCommon';
import { InputDialog, InputDialogModel } from '../components/InputDialog';
import { CredentialsDialog, CredentialsDialogModel } from '../components/CredentialsDialog';
import { VpnController, PendingAuthChallenge } from '../vpn/VpnController';
import { VpnStatus } from '../core/VpnStatus';
import { ConnectionStatus, LogLevel } from '../core/LogItem';

@Entry
@Component
struct Index {
  @State private activeFeature: number = 0;
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
  private frpTemplateDialogController: CustomDialogController = new CustomDialogController({
    builder: FrpTemplateDialog({
      onSelected: (type: FrpType, template?: FrpConfigTemplate) => {
        this.openNewFrpConfig(type, template);
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
      FrpConfigManager.init(ctx);
      FrpTemplateManager.init(ctx);
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

  private importFrpConfig(): void {
    FileUtil.pickAndRead(['.toml']).then((file) => {
      showSingleChoice('选择 FRP 配置类型', ['frpc 客户端', 'frps 服务端'], 0, (index: number) => {
        let type = index === 0 ? FrpType.FRPC : FrpType.FRPS;
        try {
          let config = FrpConfigManager.importPickedFile(type, file);
          promptAction.showToast({ message: `已导入 ${config.name}` });
          router.pushUrl({ url: 'pages/FrpConfigEdit', params: { 'uuid': config.key } });
        } catch (error) {
          promptAction.showToast({ message: `导入失败：${(error as Error).message}` });
        }
      });
    }).catch(() => {
    });
  }

  private openNewFrpConfig(type: FrpType, template?: FrpConfigTemplate): void {
    let params: Record<string, Object> = {
      'new': true,
      'type': type,
      'templateFileName': template === undefined ? '' : template.fileName
    };
    router.pushUrl({ url: 'pages/FrpConfigEdit', params: params });
  }

  private showFrpTemplates(): void {
    this.frpTemplateDialogController.open();
  }

  private startFrp(config: FrpConfig): Promise<void> {
    return FrpController.start(config);
  }

  private stopFrp(config: FrpConfig): Promise<void> {
    return FrpController.stop(config);
  }

  build() {
    Column() {
      Row() {
        Text(R.s('app_name'))
          .fontSize(20)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .layoutWeight(1)
          .padding({ left: 16 })

        if (this.activeFeature === 0) {
          Image($r('app.media.ic_import'))
            .width(24).height(24).fillColor(Color.White)
            .margin({ left: 16 })
            .onClick(() => {
              this.showImportChoices();
            })
          Image($r('app.media.ic_chart'))
            .width(24).height(24).fillColor(Color.White)
            .margin({ left: 16 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/TrafficStats' });
            })
          Image($r('app.media.ic_receipt'))
            .width(24).height(24).fillColor(Color.White)
            .margin({ left: 16 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/LogWindow' });
            })
        } else {
          Image($r('app.media.ic_add'))
            .width(24).height(24).fillColor(Color.White)
            .margin({ left: 16 })
            .onClick(() => {
              this.showFrpTemplates();
            })
          Image($r('app.media.ic_import'))
            .width(24).height(24).fillColor(Color.White)
            .margin({ left: 16 })
            .onClick(() => {
              this.importFrpConfig();
            })
        }

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

      Row() {
        Column() {
          Text('OpenVPN')
            .fontSize(15)
            .fontWeight(this.activeFeature === 0 ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.activeFeature === 0 ? Theme.PRIMARY : Theme.TEXT_SECONDARY)
          Rect()
            .width(54)
            .height(3)
            .fill(this.activeFeature === 0 ? Theme.ACCENT : Theme.TRANSPARENT)
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .height(48)
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.activeFeature = 0;
        })
        Column() {
          Text('FRP')
            .fontSize(15)
            .fontWeight(this.activeFeature === 1 ? FontWeight.Bold : FontWeight.Regular)
            .fontColor(this.activeFeature === 1 ? Theme.PRIMARY : Theme.TEXT_SECONDARY)
          Rect()
            .width(54)
            .height(3)
            .fill(this.activeFeature === 1 ? Theme.ACCENT : Theme.TRANSPARENT)
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .height(48)
        .justifyContent(FlexAlign.End)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.activeFeature = 1;
        })
      }
      .width('100%')
      .height(48)
      .backgroundColor(Theme.CARD_BG)
      .border({ width: { bottom: 1 }, color: Theme.DIVIDER })

      if (this.activeFeature === 0) {
        ProfilesTab({
          onImportProfile: () => {
            this.importConfigFile();
          }
        })
          .layoutWeight(1)
      } else {
        FrpTab({
          onImport: () => {
            this.importFrpConfig();
          },
          onNew: () => {
            this.showFrpTemplates();
          },
          onStart: (config: FrpConfig) => this.startFrp(config),
          onStop: (config: FrpConfig) => this.stopFrp(config)
        })
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
