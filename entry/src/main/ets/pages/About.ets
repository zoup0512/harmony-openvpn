import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { Theme } from '../common/Theme';
import { R } from '../common/Res';

const ABOUT_BACKGROUND: string = '#F5F7FB';
const ABOUT_CARD_BACKGROUND: string = '#FFFFFF';
const ABOUT_TEXT_PRIMARY: string = '#111827';
const ABOUT_TEXT_SECONDARY: string = '#334155';
const ABOUT_TEXT_MUTED: string = '#7C8798';
const FEEDBACK_BACKGROUND: string = '#E9FAF7';
const FEEDBACK_TEXT: string = '#0F827A';

@Entry
@Component
struct About {
  private copyEmail(): void {
    let pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, R.s('about_feedback_email'));
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      promptAction.showToast({ message: R.s('about_email_copied') });
    }).catch(() => {
    });
  }

  @Builder
  UsageCard() {
    Column() {
      Text(R.s('about_usage_title'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(ABOUT_TEXT_PRIMARY)
        .width('100%')
        .margin({ bottom: 20 })

      Text(R.s('about_usage_step1'))
        .fontSize(17)
        .fontColor(ABOUT_TEXT_SECONDARY)
        .lineHeight(29)
        .width('100%')
      Text(R.s('about_usage_step2'))
        .fontSize(17)
        .fontColor(ABOUT_TEXT_SECONDARY)
        .lineHeight(29)
        .width('100%')
        .margin({ top: 4 })
      Text(R.s('about_usage_step3'))
        .fontSize(17)
        .fontColor(ABOUT_TEXT_SECONDARY)
        .lineHeight(29)
        .width('100%')
        .margin({ top: 4 })

      Text(R.s('about_usage_warning'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.WARNING_RED)
        .lineHeight(28)
        .width('100%')
        .margin({ top: 20 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 22, right: 22, top: 24, bottom: 24 })
    .backgroundColor(ABOUT_CARD_BACKGROUND)
    .borderRadius(24)
  }

  @Builder
  PaymentCard() {
    Column() {
      Text(R.s('about_donate_title'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(ABOUT_TEXT_PRIMARY)
        .width('100%')
        .margin({ bottom: 18 })

      Image($r('app.media.donate_wx'))
        .width('100%')
        .aspectRatio(1242 / 1470)
        .objectFit(ImageFit.Contain)

      Text(R.s('about_pay_save_hint'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FF6B0B')
        .margin({ top: 14 })

      Text(R.s('about_pay_thanks'))
        .fontSize(15)
        .fontColor(ABOUT_TEXT_MUTED)
        .textAlign(TextAlign.Center)
        .lineHeight(24)
        .margin({ top: 14 })
    }
    .width('100%')
    .padding({ left: 22, right: 22, top: 24, bottom: 24 })
    .backgroundColor(ABOUT_CARD_BACKGROUND)
    .borderRadius(24)
  }

  @Builder
  FeedbackCard() {
    Column() {
      Text(R.s('about_feedback_title'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(ABOUT_TEXT_PRIMARY)
        .width('100%')

      Text(R.s('about_feedback_intro'))
        .fontSize(17)
        .fontColor(ABOUT_TEXT_SECONDARY)
        .lineHeight(29)
        .width('100%')
        .margin({ top: 20 })

      Text(R.s('about_feedback_email'))
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
        .fontColor(FEEDBACK_TEXT)
        .width('100%')
        .padding({ left: 20, right: 20, top: 22, bottom: 22 })
        .margin({ top: 20 })
        .backgroundColor(FEEDBACK_BACKGROUND)
        .borderRadius(24)
        .gesture(LongPressGesture().onAction(() => {
          this.copyEmail();
        }))

      Text(R.s('about_feedback_copy_hint'))
        .fontSize(16)
        .fontColor(FEEDBACK_TEXT)
        .width('100%')
        .margin({ top: 14 })

      Text(R.s('about_feedback_advice'))
        .fontSize(16)
        .fontColor(ABOUT_TEXT_MUTED)
        .lineHeight(27)
        .width('100%')
        .margin({ top: 18 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 22, right: 22, top: 24, bottom: 24 })
    .backgroundColor(ABOUT_CARD_BACKGROUND)
    .borderRadius(24)
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(Color.White)
          .margin({ left: 12 })
          .onClick(() => {
            router.back();
          })
        Text(R.s('about'))
          .fontSize(18)
          .fontColor(Color.White)
          .layoutWeight(1)
          .padding({ left: 12 })
      }
      .width('100%')
      .height(56)
      .backgroundColor(Theme.PRIMARY)
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 12 }) {
          this.UsageCard()
          this.PaymentCard()
          this.FeedbackCard()
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 12, bottom: 20 })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(ABOUT_BACKGROUND)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ABOUT_BACKGROUND)
  }
}
