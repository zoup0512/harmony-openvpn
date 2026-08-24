/**
 * About tab — replicates AboutFragment.
 */

import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';
import bundleManager from '@ohos.bundle.bundleManager';

@Component
export struct AboutTab {
  @State versionName: string = '';

  aboutToAppear(): void {
    try {
      let info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.versionName = info.versionName;
    } catch (e) {
      this.versionName = 'unknown';
    }
  }

  build() {
    Scroll() {
      Column() {
        Text(R.s('version_info', 'OpenVPN for Harmony', this.versionName))
          .fontSize(22)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')
          .padding({ top: 16, bottom: 8 })
        Text(R.s('copyright_port'))
          .fontSize(14)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .padding({ bottom: 16 })

        Text(R.s('copyright_guicode'))
          .fontSize(14)
          .fontColor(Theme.PRIMARY)
          .width('100%')
          .padding({ bottom: 16 })

        Text(R.s('translationby'))
          .fontSize(14)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .padding({ bottom: 16 })

        Text(R.s('privpolicy'))
          .fontSize(16)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')
          .padding({ top: 8, bottom: 4 })
        Text(R.s('privacy_policy'))
          .fontSize(13)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')

        Text(R.s('eol_notice_header'))
          .fontSize(16)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')
          .padding({ top: 16, bottom: 4 })
        Text(R.s('eol_notice'))
          .fontSize(13)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')

        Text(R.s('copyright_others'))
          .fontSize(14)
          .fontColor(Theme.TEXT_PRIMARY)
          .width('100%')
          .padding({ top: 16, bottom: 8 })

        Text(R.s('copyright_openvpn'))
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .padding({ bottom: 8 })
        Text(R.s('copyright_file_dialog'))
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .padding({ bottom: 8 })
        Text(R.s('copyright_lzo'))
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .padding({ bottom: 8 })
        Text(R.s('copyright_openssl'))
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .padding({ bottom: 8 })
        Text(R.s('copyright_bouncycastle'))
          .fontSize(12)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .padding({ bottom: 8 })
      }
      .padding({ left: 16, right: 16 })
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
