# Claude Legacy

A small iOS app for phones stuck on an old iOS (built for iOS 15 and up, so it runs on 16.4.1). It has two tabs:

- **Claude.ai**: the Claude website in a full-screen web view with back, forward, reload and home buttons. It uses your normal claude.ai login, so your chats and subscription are the same as on the web. It depends on how well the iOS 16 web engine handles the site, so a page may misbehave.
- **API chat**: a native chat screen that talks straight to the Anthropic API with your own API key (stored in the iPhone Keychain, sent only to api.anthropic.com). Replies stream in as they are written. This works whatever the website does, but API usage is billed separately from a Claude subscription. The model id is editable in settings.

## Getting the IPA

The IPA is built by GitHub Actions on a Mac runner, unsigned.

1. Open the **Actions** tab, pick the latest "Build IPA" run, and download the `ClaudeLegacy-ipa` artifact. It contains `ClaudeLegacy.ipa`. (Tagged builds such as `v1.0.0` also attach it to a release.)
2. Install it on the phone. An unsigned IPA has to be signed on your side:
   - **TrollStore** (iOS 16.4.1 is supported): installs it permanently with no expiry.
   - **AltStore** or **Sideloadly**: sign it with your Apple ID. A free account expires after 7 days and needs a refresh.

## Building it yourself

Needs a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen): `xcodegen generate`, open `ClaudeLegacy.xcodeproj`, run.
