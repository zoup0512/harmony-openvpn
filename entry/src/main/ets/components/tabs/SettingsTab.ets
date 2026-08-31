/**
 * Settings tab — replicates GeneralSettings (app behaviour + VPN behaviour).
 *
 * Every replicated option has been hidden: the keys (showlogwindow,
 * allow_translation, alwaysOnVpn, restartvpnonboot, preferencryption,
 * usesystemproxy, netchangereconnect, screenoff, disableconfirmation) are
 * stored but never read by the VPN/service code, and the ovpn3/osslspeed rows
 * were already unavailable in this build. Restore a row only once its key is
 * actually consumed somewhere (see git history for the removed rows).
 */

import { Theme } from '../../common/Theme';

@Component
export struct SettingsTab {
  build() {
    Column() {
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.WINDOW_BG)
  }
}
