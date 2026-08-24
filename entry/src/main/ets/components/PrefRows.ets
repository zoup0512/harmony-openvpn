/**
 * Preference-style rows replicating the Android preference UI.
 */

import { Theme } from '../common/Theme';

@Component
export struct PrefCategory {
  @Prop title: string = '';

  build() {
    Column() {
      Text(this.title)
        .fontSize(14)
        .fontColor(Theme.PRIMARY)
        .fontWeight(FontWeight.Medium)
        .padding({ left: 16, right: 16, top: 16, bottom: 8 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

@Component
export struct SwitchRow {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop checked: boolean = false;
  @Prop rowEnabled: boolean = true;
  @Prop showDivider: boolean = true;
  onChange: (value: boolean) => void = () => {
  };

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize(16)
          .fontColor(this.rowEnabled ? Theme.TEXT_PRIMARY : Theme.TEXT_DISABLED)
          .maxLines(2)
          .textAlign(TextAlign.Start)
        if (this.summary !== '') {
          Text(this.summary)
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .maxLines(4)
            .textAlign(TextAlign.Start)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.checked }) 
        .selectedColor(Theme.ACCENT)
        .enabled(this.rowEnabled)
        .onChange((value: boolean) => {
          this.onChange(value);
        })
        .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .border(this.showDivider ? { width: { bottom: 1 }, color: '1F000000' } : { width: 0 })
    .backgroundColor(Theme.CARD_BG)
  }
}

@Component
export struct CheckRow {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop checked: boolean = false;
  @Prop rowEnabled: boolean = true;
  @Prop showDivider: boolean = true;
  onChange: (value: boolean) => void = () => {
  };

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize(16)
          .fontColor(this.rowEnabled ? Theme.TEXT_PRIMARY : Theme.TEXT_DISABLED)
          .maxLines(2)
          .textAlign(TextAlign.Start)
        if (this.summary !== '') {
          Text(this.summary)
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .maxLines(4)
            .textAlign(TextAlign.Start)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Checkbox()
        .select(this.checked)
        .selectedColor(Theme.PRIMARY)
        .enabled(this.rowEnabled)
        .onChange((value: boolean) => {
          this.onChange(value);
        })
        .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .border(this.showDivider ? { width: { bottom: 1 }, color: '1F000000' } : { width: 0 })
    .backgroundColor(Theme.CARD_BG)
  }
}

@Component
export struct TapRow {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop rowEnabled: boolean = true;
  @Prop showDivider: boolean = true;
  onRowClick: () => void = () => {
  };

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize(16)
          .fontColor(this.rowEnabled ? Theme.TEXT_PRIMARY : Theme.TEXT_DISABLED)
          .maxLines(2)
          .textAlign(TextAlign.Start)
        if (this.summary !== '') {
          Text(this.summary)
            .fontSize(13)
            .fontColor(Theme.TEXT_SECONDARY)
            .maxLines(6)
            .textAlign(TextAlign.Start)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('›')
        .fontSize(22)
        .fontColor(Theme.TEXT_SECONDARY)
        .margin({ left: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .border(this.showDivider ? { width: { bottom: 1 }, color: '1F000000' } : { width: 0 })
    .backgroundColor(Theme.CARD_BG)
    .onClick(() => {
      if (this.rowEnabled) {
        this.onRowClick();
      }
    })
  }
}
