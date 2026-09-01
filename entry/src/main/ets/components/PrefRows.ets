/**
 * Preference-style rows replicating the Android preference UI.
 */

import { Theme } from '../common/Theme';

@Component
export struct PrefCategory {
  @Prop title: string = '';
  @Prop darkMode: boolean = false;

  build() {
    Column() {
      Text(this.title)
        .fontSize(14)
        .fontColor(this.darkMode ? Theme.DARK_ACCENT : Theme.PRIMARY)
        .fontWeight(FontWeight.Medium)
        .padding({ left: this.darkMode ? 0 : 16, right: this.darkMode ? 0 : 16, top: 16, bottom: 8 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .backgroundColor(this.darkMode ? Theme.DARK_BACKGROUND : Theme.TRANSPARENT)
  }
}

@Component
export struct SwitchRow {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop checked: boolean = false;
  @Prop rowEnabled: boolean = true;
  @Prop showDivider: boolean = true;
  @Prop darkMode: boolean = false;
  onChange: (value: boolean) => void = () => {
  };

  build() {
    Column() {
      Row() {
        Column() {
          Text(this.title)
            .fontSize(16)
            .fontColor(this.rowEnabled ?
            (this.darkMode ? Theme.DARK_TEXT_PRIMARY : Theme.TEXT_PRIMARY) :
            (this.darkMode ? Theme.DARK_TEXT_DISABLED : Theme.TEXT_DISABLED))
            .maxLines(2)
            .textAlign(TextAlign.Start)
          if (this.summary !== '') {
            Text(this.summary)
              .fontSize(13)
              .fontColor(this.darkMode ? Theme.DARK_TEXT_SECONDARY : Theme.TEXT_SECONDARY)
              .maxLines(4)
              .textAlign(TextAlign.Start)
              .margin({ top: 2 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.checked })
          .selectedColor(this.darkMode ? Theme.DARK_ACCENT : Theme.ACCENT)
          .enabled(this.rowEnabled)
          .onChange((value: boolean) => {
            this.onChange(value);
          })
          .margin({ left: 12 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .border(this.showDivider ? {
        width: { bottom: 1 },
        color: this.darkMode ? Theme.DARK_BORDER : Theme.DIVIDER
      } : { width: 0 })
      .backgroundColor(this.darkMode ? Theme.DARK_SURFACE : Theme.CARD_BG)
      .borderRadius(this.darkMode ? Theme.DARK_ROW_RADIUS : 0)
    }
    .width('100%')
    .padding(0)
    .backgroundColor(this.darkMode ? Theme.DARK_BACKGROUND : Theme.TRANSPARENT)
  }
}

@Component
export struct CheckRow {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop checked: boolean = false;
  @Prop rowEnabled: boolean = true;
  @Prop showDivider: boolean = true;
  @Prop darkMode: boolean = false;
  onChange: (value: boolean) => void = () => {
  };

  build() {
    Column() {
      Row() {
        Column() {
          Text(this.title)
            .fontSize(16)
            .fontColor(this.rowEnabled ?
            (this.darkMode ? Theme.DARK_TEXT_PRIMARY : Theme.TEXT_PRIMARY) :
            (this.darkMode ? Theme.DARK_TEXT_DISABLED : Theme.TEXT_DISABLED))
            .maxLines(2)
            .textAlign(TextAlign.Start)
          if (this.summary !== '') {
            Text(this.summary)
              .fontSize(13)
              .fontColor(this.darkMode ? Theme.DARK_TEXT_SECONDARY : Theme.TEXT_SECONDARY)
              .maxLines(4)
              .textAlign(TextAlign.Start)
              .margin({ top: 2 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Checkbox()
          .select(this.checked)
          .selectedColor(this.darkMode ? Theme.DARK_ACCENT : Theme.ACCENT)
          .enabled(this.rowEnabled)
          .onChange((value: boolean) => {
            this.onChange(value);
          })
          .margin({ left: 12 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .border(this.showDivider ? {
        width: { bottom: 1 },
        color: this.darkMode ? Theme.DARK_BORDER : Theme.DIVIDER
      } : { width: 0 })
      .backgroundColor(this.darkMode ? Theme.DARK_SURFACE : Theme.CARD_BG)
      .borderRadius(this.darkMode ? Theme.DARK_ROW_RADIUS : 0)
    }
    .width('100%')
    .padding(0)
    .backgroundColor(this.darkMode ? Theme.DARK_BACKGROUND : Theme.TRANSPARENT)
  }
}

@Component
export struct TapRow {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop rowEnabled: boolean = true;
  @Prop showDivider: boolean = true;
  @Prop darkMode: boolean = false;
  onRowClick: () => void = () => {
  };

  build() {
    Column() {
      Row() {
        Column() {
          Text(this.title)
            .fontSize(16)
            .fontColor(this.rowEnabled ?
            (this.darkMode ? Theme.DARK_TEXT_PRIMARY : Theme.TEXT_PRIMARY) :
            (this.darkMode ? Theme.DARK_TEXT_DISABLED : Theme.TEXT_DISABLED))
            .maxLines(2)
            .textAlign(TextAlign.Start)
          if (this.summary !== '') {
            Text(this.summary)
              .fontSize(13)
              .fontColor(this.darkMode ? Theme.DARK_TEXT_SECONDARY : Theme.TEXT_SECONDARY)
              .maxLines(6)
              .textAlign(TextAlign.Start)
              .margin({ top: 2 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('›')
          .fontSize(22)
          .fontColor(this.rowEnabled ?
          (this.darkMode ? Theme.DARK_TEXT_SECONDARY : Theme.TEXT_SECONDARY) :
          (this.darkMode ? Theme.DARK_TEXT_DISABLED : Theme.TEXT_DISABLED))
          .margin({ left: 8 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .border(this.showDivider ? {
        width: { bottom: 1 },
        color: this.darkMode ? Theme.DARK_BORDER : Theme.DIVIDER
      } : { width: 0 })
      .backgroundColor(this.darkMode ? Theme.DARK_SURFACE : Theme.CARD_BG)
      .borderRadius(this.darkMode ? Theme.DARK_ROW_RADIUS : 0)
      .onClick(() => {
        if (this.rowEnabled) {
          this.onRowClick();
        }
      })
    }
    .width('100%')
    .padding(0)
    .backgroundColor(this.darkMode ? Theme.DARK_BACKGROUND : Theme.TRANSPARENT)
  }
}
