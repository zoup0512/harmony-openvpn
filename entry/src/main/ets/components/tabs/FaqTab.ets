import { Theme } from '../../common/Theme';
import { FaqContent } from './FaqContent';

@Component
export struct FaqTab {
  build() {
    Scroll() {
      FaqContent()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
