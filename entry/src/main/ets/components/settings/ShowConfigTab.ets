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
          .fontColor(Theme.TEXT_PRIMARY)
          .fontFamily('monospace')
          .padding(16)
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.CARD_BG)

      Button() {
        Image($r('app.media.ic_share'))
          .width(24).height(24).fillColor(Color.White)
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor(Theme.ACCENT)
      .margin(16)
      .shadow({ radius: 4, color: '#66000000', offsetX: 2, offsetY: 4 })
      .onClick(() => {
        this.share();
      })
    }
    .width('100%')
    .height('100%')
  }
}
