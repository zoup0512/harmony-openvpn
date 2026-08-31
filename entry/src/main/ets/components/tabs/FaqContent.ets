import { Theme } from '../../common/Theme';
import { R } from '../../common/Res';

class FaqEntry {
  titleKey: string;
  bodyKey: string;

  constructor(titleKey: string, bodyKey: string) {
    this.titleKey = titleKey;
    this.bodyKey = bodyKey;
  }
}

// Hidden entries describe features this build does not have: faq_killswitch
// (persist-tun / always-on not wired up), faq_remote_api (no remote API),
// faq_different_clients (core is OpenVPN 3, not 2.x), faq_proxy (no system
// proxy handling). Re-add an entry only once its feature actually works.
const FAQ_ITEMS: FaqEntry[] = [
  new FaqEntry('faq_howto', 'faq_howto_body'),
  new FaqEntry('faq_ncp_title', 'faq_ncp_body'),
  new FaqEntry('faq_md5_hashes', 'faq_md5_body'),
  new FaqEntry('faq_duplicate_notifications', 'faq_duplicate_notifications_body'),
  new FaqEntry('faq_battery', 'faq_battery_body'),
  new FaqEntry('faq_tap', 'faq_tap_body'),
  new FaqEntry('faq_copying_log', 'faq_copying_log_body'),
  new FaqEntry('faq_routing', 'faq_routing_body'),
  new FaqEntry('faq_non_cidr', 'faq_non_cidr_body'),
  new FaqEntry('faq_security', 'faq_security_body'),
  new FaqEntry('faq_shortcut', 'faq_shortcut_body')
];

@Component
export struct FaqContent {
  @State expanded: number[] = [];

  private isExpanded(i: number): boolean {
    return this.expanded.indexOf(i) !== -1;
  }

  private toggle(i: number): void {
    let idx = this.expanded.indexOf(i);
    if (idx === -1) {
      this.expanded.push(i);
    } else {
      this.expanded.splice(idx, 1);
    }
    this.expanded = this.expanded.slice();
  }

  build() {
    Column() {
      ForEach(FAQ_ITEMS, (item: FaqEntry, index?: number) => {
        Column() {
          Text(R.s(item.titleKey))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.TEXT_PRIMARY)
            .width('100%')
            .padding({ left: 4, right: 4, top: 12, bottom: 12 })
          if (this.isExpanded(index as number)) {
            Text(R.s(item.bodyKey))
              .fontSize(15)
              .fontColor(Theme.TEXT_SECONDARY)
              .lineHeight(24)
              .width('100%')
              .padding({ left: 4, right: 4, bottom: 12 })
          }
        }
        .width('100%')
        .onClick(() => {
          this.toggle(index as number);
        })

        if ((index as number) < FAQ_ITEMS.length - 1) {
          Divider()
            .color(Theme.DIVIDER)
            .strokeWidth(0.5)
            .margin({ left: 4, right: 4 })
        }
      }, (item: FaqEntry) => item.titleKey)
    }
    .width('100%')
  }
}
