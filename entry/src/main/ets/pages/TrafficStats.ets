/**
 * Traffic statistics page — hosts the per-profile traffic cards (GraphTab),
 * opened from the toolbar chart icon on the main page.
 */

import { router } from '@kit.ArkUI';
import { Theme } from '../common/Theme';
import { R } from '../common/Res';
import { GraphTab } from '../components/tabs/GraphTab';

@Entry
@Component
struct TrafficStats {
  build() {
    Column() {
      // ---- Toolbar ----
      Row() {
        Button() {
          Image($r('app.media.ic_back'))
            .width(24)
            .height(24)
            .fillColor(Color.White)
        }
        .width(48)
        .height(48)
        .padding(0)
        .borderRadius(24)
        .backgroundColor(Theme.TRANSPARENT)
        .margin({ left: 4 })
        .accessibilityText(R.s('back'))
        .onClick(() => {
          router.back();
        })
        Text(R.s('traffic_stats_title'))
          .fontSize(18)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .layoutWeight(1)
          .padding({ left: 4, right: 16 })
      }
      .width('100%')
      .height(56)
      .backgroundColor(Theme.PRIMARY)
      .alignItems(VerticalAlign.Center)

      // ---- Content ----
      GraphTab()
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
