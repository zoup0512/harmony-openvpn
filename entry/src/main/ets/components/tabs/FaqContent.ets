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

const FAQ_ITEMS: FaqEntry[] = [
  new FaqEntry('faq_howto', 'faq_howto_body'),
  new FaqEntry('faq_killswitch', 'faq_killswitch_body'),
  new FaqEntry('faq_remote_api', 'faq_remote_api_body'),
  new FaqEntry('faq_ncp_title', 'faq_ncp_body'),
  new FaqEntry('faq_md5_hashes', 'faq_md5_body'),
  new FaqEntry('faq_duplicate_notifications', 'faq_duplicate_notifications_body'),
  new FaqEntry('faq_different_clients', 'faq_different_clients_body'),
  new FaqEntry('faq_battery', 'faq_battery_body'),
  new FaqEntry('faq_tap', 'faq_tap_body'),
  new FaqEntry('faq_copying_log', 'faq_copying_log_body'),
  new FaqEntry('faq_routing', 'faq_routing_body'),
  new FaqEntry('faq_non_cidr', 'faq_non_cidr_body'),
  new FaqEntry('faq_proxy', 'faq_proxy_body'),
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
            .fontSize(18)
            .fontColor(Theme.TEXT_PRIMARY)
            .width('100%')
            .padding({ left: 10, right: 10, top: 10, bottom: 5 })
          if (this.isExpanded(index as number)) {
            Text(R.s(item.bodyKey))
              .fontSize(14)
              .fontColor(Theme.TEXT_SECONDARY)
              .width('100%')
              .padding({ left: 10, right: 10, bottom: 10 })
          }
        }
        .borderRadius(10)
        .margin(10)
        .backgroundColor(Theme.CARD_BG)
        .width('100%')
        .onClick(() => {
          this.toggle(index as number);
        })
      }, (item: FaqEntry) => item.titleKey)
    }
    .width('100%')
  }
}
