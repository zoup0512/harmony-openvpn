/**
 * General settings page — hosts the generic settings list (SettingsTab),
 * opened from the toolbar settings icon on the main page.
 */

import { router } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { R } from '../common/Res';
import { SettingsTab } from '../components/tabs/SettingsTab';

@Entry
@Component
struct Settings {
  build() {
    Column() {
      // ---- Toolbar ----
      Row() {
        Image($r('app.media.ic_back'))
          .width(24).height(24).fillColor(Color.White)
          .margin({ left: 12 })
          .onClick(() => {
            router.back();
          })
        Text(R.s('generalsettings'))
          .fontSize(18)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .layoutWeight(1)
          .padding({ left: 12 })
      }
      .width('100%')
      .height(56)
      .backgroundColor(Theme.PRIMARY)
      .alignItems(VerticalAlign.Center)

      // ---- Content ----
      SettingsTab()
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
