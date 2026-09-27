import receive_sharing_intent

final class ShareViewController: RSIShareViewController {
  override func shouldAutoRedirect() -> Bool { false }
  override var placeholder: String { "Mesaja not ekleyin…" }
  override var sendButtonTitle: String { "KaydetMail ile gönder" }
}
