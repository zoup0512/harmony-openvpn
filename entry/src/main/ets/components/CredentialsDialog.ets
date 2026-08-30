import { Theme } from '../common/Theme';

export class CredentialsDialogModel {
  title: string = '';
  message: string = '';
  username: string = '';
  password: string = '';
  usernamePlaceholder: string = '';
  passwordPlaceholder: string = '';
  okText: string = 'OK';
  cancelText: string = 'Cancel';
  onOk: (username: string, password: string) => boolean = () => true;
  onCancel: () => void = () => {
  };
}

@CustomDialog
export struct CredentialsDialog {
  controller?: CustomDialogController;
  model: CredentialsDialogModel = new CredentialsDialogModel();
  @State private username: string = '';
  @State private password: string = '';

  aboutToAppear(): void {
    this.username = this.model.username;
    this.password = this.model.password;
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
      TextInput({ text: this.username, placeholder: this.model.usernamePlaceholder })
        .width('100%')
        .onChange((value: string) => {
          this.username = value;
        })
      TextInput({ text: this.password, placeholder: this.model.passwordPlaceholder })
        .type(InputType.Password)
        .width('100%')
        .margin({ top: 10 })
        .onChange((value: string) => {
          this.password = value;
        })
      Row() {
        Blank()
        Button(this.model.cancelText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .height(Theme.DIALOG_BUTTON_HEIGHT)
          .constraintSize({ minWidth: Theme.DIALOG_BUTTON_MIN_WIDTH })
          .padding({ left: 16, right: 16 })
          .backgroundColor(Theme.CARD_BG)
          .fontColor(Theme.PRIMARY)
          .border({ width: 1, color: Theme.PRIMARY })
          .borderRadius(Theme.DIALOG_BUTTON_RADIUS)
          .onClick(() => {
            this.controller?.close();
            this.model.onCancel();
          })
        Button(this.model.okText)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .height(Theme.DIALOG_BUTTON_HEIGHT)
          .constraintSize({ minWidth: Theme.DIALOG_BUTTON_MIN_WIDTH })
          .padding({ left: 16, right: 16 })
          .backgroundColor(Theme.PRIMARY)
          .fontColor(Theme.WHITE)
          .borderRadius(Theme.DIALOG_BUTTON_RADIUS)
          .margin({ left: Theme.DIALOG_BUTTON_GAP })
          .onClick(() => {
            if (!this.model.onOk(this.username, this.password)) {
              return;
            }
            this.controller?.close();
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
