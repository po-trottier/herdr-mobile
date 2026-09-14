/// Which action the person chose in
/// `chrome_confirmation_dialog.dart`'s `showChromeConfirmationDialog`, per
/// `docs/33-platform-chrome.md` R-33-074.
library;

enum ChromeConfirmationOutcome {
  /// The destructive action.
  destructive,

  /// The cancelling action.
  cancel,
}
