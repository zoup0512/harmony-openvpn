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
    env.mgmtSocketDir = '/data/cache';
    env.guiVer = 'com.razor.tools.openvpn 1.0.0';
    env.platVer = `${deviceInfo.sdkApiVersion} HarmonyOS`;
    env.hwaddr = '';
    env.useSystemProxy = true;
    try {
      this.configText = generateConfigFile(p, env) + '\n\n\n';
    } catch (e) {
      this.configText = `${e}`;
    }
  }

  private share(): void {
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
