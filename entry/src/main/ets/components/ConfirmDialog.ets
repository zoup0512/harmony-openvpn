/**
 * Confirmation dialog used by the dark VPN profile preference screens.
 */

import { Theme } from '../common/Theme';

export class ConfirmDialogModel {
  title: string = '';
  message: string = '';
  cancelText: string = 'Cancel';
  confirmText: string = 'OK';
  showCancel: boolean = true;
  dangerous: boolean = false;
  onConfirm: () => void = () => {
  };
  onCancel: () => void = () => {
  };
}

@CustomDialog
export struct ConfirmDialog {
  controller?: CustomDialogController;
  model: ConfirmDialogModel = new ConfirmDialogModel();
  @Prop darkMode: boolean = true;

  build() {
    Column() {
      Text(this.model.title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.darkMode ? Theme.DARK_TEXT_PRIMARY : Theme.TEXT_PRIMARY)
        .width('100%')
        .padding({ bottom: 8 })
      if (this.model.message !== '') {
        Text(this.model.message)
          .fontSize(14)
          .fontColor(this.darkMode ? Theme.DARK_TEXT_SECONDARY : Theme.TEXT_SECONDARY)
          .width('100%')
          .lineHeight(20)
          .padding({ bottom: 8 })
          .textAlign(TextAlign.Start)
      }
      Row() {
        if (this.model.showCancel) {
          Button(this.model.cancelText)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .height(Theme.DIALOG_BUTTON_HEIGHT)
            .constraintSize({ minWidth: Theme.DIALOG_BUTTON_MIN_WIDTH })
            .padding({ left: 16, right: 16 })
            .backgroundColor(this.darkMode ? Theme.DARK_SURFACE_ALT : Theme.CARD_BG)
            .fontColor(this.darkMode ? Theme.DARK_ACCENT : Theme.PRIMARY)
            .border({ width: 1, color: this.darkMode ? Theme.DARK_ACCENT : Theme.PRIMARY })
            .borderRadius(Theme.DIALOG_BUTTON_RADIUS)
            .onClick(() => {
              this.controller?.close();
              this.model.onCancel();
            })
        }
        Blank()
        Button(this.model.confirmText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .height(Theme.DIALOG_BUTTON_HEIGHT)
          .constraintSize({ minWidth: Theme.DIALOG_BUTTON_MIN_WIDTH })
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.model.dangerous
            ? (this.darkMode ? Theme.DARK_DANGER_SURFACE : Theme.CARD_BG)
            : (this.darkMode ? Theme.DARK_ACTION : Theme.PRIMARY))
          .fontColor(this.model.dangerous
            ? (this.darkMode ? Theme.DARK_DANGER : Theme.WARNING_RED)
            : Theme.WHITE)
          .border(this.model.dangerous ? {
            width: 1,
            color: this.darkMode ? Theme.DARK_DANGER : Theme.WARNING_RED
          } : { width: 0 })
          .borderRadius(Theme.DIALOG_BUTTON_RADIUS)
          .margin({ left: this.model.showCancel ? Theme.DIALOG_BUTTON_GAP : 0 })
          .onClick(() => {
            this.controller?.close();
            this.model.onConfirm();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .padding(20)
    .backgroundColor(this.darkMode ? Theme.DARK_SURFACE : Theme.CARD_BG)
    .borderRadius(this.darkMode ? Theme.DARK_CARD_RADIUS : 4)
  }
}
