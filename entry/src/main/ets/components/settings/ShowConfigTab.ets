/**
 * Generated Config tab — port of ShowConfigFragment.
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import { VpnProfile, ProfileError } from '../../core/VpnProfile';
import { generateConfigFile, GenEnvInfo } from '../../core/ConfigGenerator';
import { profileErrorText } from '../../common/ProfileChecks';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import deviceInfo from '@ohos.deviceInfo';
import { App } from '../../common/App';

@Component
export struct ShowConfigTab {
  profile: VpnProfile = new VpnProfile('unset');
  @State configText: string = '';
  @State generated: boolean = false;

  aboutToAppear(): void {
    let err = this.profile.checkProfile(false);
    if (err !== ProfileError.NO_ERROR) {
      this.configText = profileErrorText(err);
      return;
    }
    this.configText = R.s('building_config');
    this.generate();
  }

  private generate(): void {
    let p = this.profile;
    let env = new GenEnvInfo();
    env.openVpn3 = true;
    env.guiVer = 'com.razor.tools.openvpn 1.0.0';
    env.platVer = `${deviceInfo.sdkApiVersion} HarmonyOS`;
    env.hwaddr = '';
    env.useSystemProxy = false;
    try {
      this.configText = generateConfigFile(VpnProfile.fromJson(p.toJson()), env);
      this.generated = true;
    } catch (e) {
      this.configText = `${e}`;
    }
  }

  private share(): void {
    if (!this.generated) {
      return;
    }
    AlertDialog.show({
      title: '复制配置原文',
      message: '配置可能包含内嵌证书、私钥、静态密钥或自定义凭据。复制后其他应用可能读取剪贴板，请勿粘贴到不可信服务。此操作不会自动发送配置。',
      primaryButton: { value: R.s('cancel'), action: () => {} },
      secondaryButton: { value: '确认复制', action: () => this.copyConfig() }
    });
  }

  private copyConfig(): void {
    let pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.configText);
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      promptAction.showToast({ message: R.s('config_copied_clipboard') });
    }).catch(() => {
      promptAction.showToast({ message: R.s('import_error_message') });
    });
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Scroll() {
        Column({ space: 12 }) {
          Text('本地分享预览：以下为生成的 OpenVPN 配置原文，可能含证书、私钥等敏感内容；不会自动上传。外部证书文件不会打包，换设备可能需要重新选择。')
            .fontSize(13).fontColor(Theme.DARK_TEXT_SECONDARY).padding(12).width('100%')
          Text(this.configText)
          .fontSize(12)
          .fontColor(Theme.DARK_TEXT_PRIMARY)
          .fontFamily('monospace')
          .lineHeight(19)
          .padding(16)
          .width('100%')
          .textAlign(TextAlign.Start)
          .backgroundColor(Theme.DARK_SURFACE)
          .border({ width: 1, color: Theme.DARK_BORDER })
          .borderRadius(Theme.DARK_CARD_RADIUS)
        }.width('100%')
      }
      .width('100%')
      .height('100%')
      .padding({ left: 12, right: 12, top: 12, bottom: 84 })
      .backgroundColor(Theme.DARK_BACKGROUND)

      Button() {
        Image($r('app.media.ic_copy'))
          .width(24)
          .height(24)
          .fillColor(Theme.DARK_BACKGROUND)
      }
      .enabled(this.generated)
      .accessibilityText('复制 OpenVPN 配置原文')
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor(Theme.DARK_ACCENT)
      .margin(16)
      .shadow({ radius: 8, color: '#99000000', offsetX: 0, offsetY: 4 })
      .onClick(() => {
        this.share();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.DARK_BACKGROUND)
  }
}
