import { router, promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { Theme } from '../common/Theme';
import { R } from '../common/Res';
import { FaqContent } from '../components/tabs/FaqContent';

const ABOUT_BACKGROUND: string = '#F5F7FB';
const ABOUT_CARD_BACKGROUND: string = '#FFFFFF';
const ABOUT_TEXT_PRIMARY: string = '#111827';
const ABOUT_TEXT_SECONDARY: string = '#334155';
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
      promptAction.showToast({ message: R.s('about_email_copy_failed') });
    });
  }

  @Builder
  UsageStepItem(index: number, text: string, topMargin: number) {
    Row() {
      Text(`${index}.`)
        .fontSize(15)
        .fontColor(ABOUT_TEXT_SECONDARY)
        .lineHeight(24)
      Text(text)
        .fontSize(15)
        .fontColor(ABOUT_TEXT_SECONDARY)
        .lineHeight(24)
        .layoutWeight(1)
        .padding({ left: 6 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: topMargin })
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

      this.UsageStepItem(1, R.s('about_usage_step1'), 0)
      this.UsageStepItem(2, R.s('about_usage_step2'), 4)
      this.UsageStepItem(3, R.s('about_usage_step3'), 4)

      Text(R.s('about_usage_warning'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.WARNING_RED)
        .lineHeight(24)
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
  FaqCard() {
    Column() {
      Text(R.s('faq'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(ABOUT_TEXT_PRIMARY)
        .width('100%')
        .margin({ bottom: 8 })

      FaqContent()
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 24, bottom: 14 })
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
        .fontSize(15)
        .fontColor(ABOUT_TEXT_SECONDARY)
        .lineHeight(24)
        .width('100%')
        .margin({ top: 20 })

      Text(R.s('about_feedback_email'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(FEEDBACK_TEXT)
        .width('100%')
        .padding({ left: 20, right: 20, top: 22, bottom: 22 })
        .margin({ top: 20 })
        .backgroundColor(FEEDBACK_BACKGROUND)
        .borderRadius(24)
        .priorityGesture(LongPressGesture().onAction(() => {
          this.copyEmail();
        }))

      Text(R.s('about_feedback_copy_hint'))
        .fontSize(15)
        .fontColor(FEEDBACK_TEXT)
        .width('100%')
        .margin({ top: 14 })
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
          this.FaqCard()
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
