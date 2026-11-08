# Claude Legacy

An unofficial iOS app for phones stuck on an older iOS. It needs iOS 16 or later, so it runs on 16.4.1. Pure black OLED theme, dark only. Made by Necro. Not affiliated with Anthropic.

Three tabs:

- **Claude**: the Claude site, full screen with no address bar or browser buttons. Pull down to refresh. It uses your normal claude.ai login, so chats and subscription are the same as on the web. How well it runs depends on the iOS 16 web engine.
- **Chat**: a native chat screen that talks to the Anthropic API with your own key. Replies stream in, code blocks have a copy button, and the conversation is kept on the phone. API use is billed separately from a Claude subscription.
- **Settings**: pick the Claude version (Fable 5.1, Opus 5.5, Sonnet 5.5, Haiku 5.5, or any other model id), system prompt, creativity, reply length, API key (kept in the Keychain, sent only to api.anthropic.com), and an About section.

## Getting the IPA

GitHub Actions builds an unsigned IPA on a Mac runner every time you push. Open the **Actions** tab, pick the latest "Build IPA" run, and download the `ClaudeLegacy-ipa` artifact (a zip containing `ClaudeLegacy.ipa`).

Install it with one of these, since it is unsigned:

- **TrollStore** (iOS 16.4.1 is supported): permanent, no expiry.
- **AltStore** or **Sideloadly**: sign it with your Apple ID. A free account needs a refresh every 7 days.

## Building it yourself

Needs a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen): `xcodegen generate`, open `ClaudeLegacy.xcodeproj`, run. `tools/make_icon.py` redraws the app icon.
