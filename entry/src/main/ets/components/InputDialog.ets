/**
 * Generic text input dialog (Add Profile / password queries / field edits ...).
 * Content is provided via a mutable model so a single dialog controller can
 * be reused for different prompts.
 */

import { Theme } from '../common/Theme';

export class InputDialogModel {
  title: string = '';
  message: string = '';
  placeholder: string = '';
  initial: string = '';
  multiLine: boolean = false;
  isPassword: boolean = false;
  okText: string = 'OK';
  cancelText: string = 'Cancel';
  neutralText: string = '';
  onOk: (text: string) => void = () => {
  };
  validate: (text: string) => boolean = () => true;
  onCancel: () => void = () => {
  };
  onNeutral: () => void = () => {
  };
}

@CustomDialog
export struct InputDialog {
  controller?: CustomDialogController;
  model: InputDialogModel = new InputDialogModel();
  @State text: string = '';

  aboutToAppear(): void {
    this.text = this.model.initial;
  }

  build() {
    Column() {
      Text(this.model.title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.TEXT_PRIMARY)
        .width('100%')
        .padding({ bottom: 8 })
      if (this.model.message !== '') {
        Text(this.model.message)
          .fontSize(14)
          .fontColor(Theme.TEXT_SECONDARY)
          .width('100%')
          .padding({ bottom: 8 })
          .textAlign(TextAlign.Start)
      }
      if (this.model.multiLine) {
        TextArea({ text: this.text, placeholder: this.model.placeholder })
          .onChange((value: string) => {
            this.text = value;
          })
          .height(120)
          .width('100%')
      } else {
        TextInput({ text: this.text, placeholder: this.model.placeholder })
          .type(this.model.isPassword ? InputType.Password : InputType.Normal)
          .onChange((value: string) => {
            this.text = value;
          })
          .width('100%')
      }
      Row() {
        if (this.model.neutralText !== '') {
          Button(this.model.neutralText)
            .fontSize(14)
            .backgroundColor(0)
            .fontColor(Theme.PRIMARY)
            .onClick(() => {
              this.controller?.close();
              this.model.onNeutral();
            })
        }
        Blank()
        Button(this.model.cancelText)
          .fontSize(14)
          .backgroundColor(0)
          .fontColor(Theme.PRIMARY)
          .onClick(() => {
            this.controller?.close();
            this.model.onCancel();
          })
        Button(this.model.okText)
          .fontSize(14)
          .backgroundColor(0)
          .fontColor(Theme.PRIMARY)
          .margin({ left: 8 })
          .onClick(() => {
            if (!this.model.validate(this.text)) {
              return;
            }
            this.controller?.close();
            this.model.onOk(this.text);
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(4)
  }
}
