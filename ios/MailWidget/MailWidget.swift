import SwiftUI
import UIKit
import WidgetKit

// Keys and group must match lib/services/home_widget_service.dart.
private let appGroupId = "group.com.kaydetmail.app"
private let unreadCountKey = "kaydet_widget_unread_count"
private let mailKeys = ["kaydet_widget_mail_1", "kaydet_widget_mail_2", "kaydet_widget_mail_3"]

// The `homeWidget` query item lets the home_widget plugin report widget taps.
private let inboxURL = URL(string: "kaydetmail://inbox?homeWidget")!
private let composeURL = URL(string: "kaydetmail://compose?homeWidget")!

struct MailEntry: TimelineEntry {
  let date: Date
  let unreadCount: Int
  let mails: [String]

  static let sample = MailEntry(
    date: Date(),
    unreadCount: 3,
    mails: [
      "Ayşe Yılmaz — Toplantı notları",
      "Mehmet Kaya — Haftalık rapor",
      "KAYDET — Hoş geldiniz",
    ])

  static func load() -> MailEntry {
    let defaults = UserDefaults(suiteName: appGroupId)
    let unread = max(0, defaults?.integer(forKey: unreadCountKey) ?? 0)
    let mails = mailKeys
      .compactMap { defaults?.string(forKey: $0) }
      .filter { !$0.isEmpty }
    return MailEntry(date: Date(), unreadCount: unread, mails: mails)
  }
}

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> MailEntry {
    MailEntry.sample
  }

  func getSnapshot(in context: Context, completion: @escaping (MailEntry) -> Void) {
    let entry = MailEntry.load()
    // The widget gallery asks for a preview before the app has written any data.
    if context.isPreview && entry.unreadCount == 0 && entry.mails.isEmpty {
      completion(MailEntry.sample)
    } else {
      completion(entry)
    }
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<MailEntry>) -> Void) {
    // The app reloads this timeline whenever mail data changes.
    completion(Timeline(entries: [MailEntry.load()], policy: .never))
  }
}

struct MailWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family
  let entry: MailEntry

  var body: some View {
    Group {
      switch family {
      case .systemMedium:
        mediumBody
      default:
        smallBody
      }
    }
    .widgetURL(inboxURL)
    .widgetBackground()
  }

  private var smallBody: some View {
    VStack(alignment: .leading, spacing: 4) {
      header
      Spacer(minLength: 0)
      unreadCount
      Spacer(minLength: 0)
      if let first = entry.mails.first {
        mailLine(first, lineLimit: 2)
      } else {
        emptyState
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }

  private var mediumBody: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .center) {
        header
        Spacer(minLength: 0)
        composeButton
      }
      HStack(alignment: .top, spacing: 12) {
        unreadCount
          .frame(minWidth: 72, alignment: .leading)
        Divider()
        VStack(alignment: .leading, spacing: 6) {
          if entry.mails.isEmpty {
            emptyState
          } else {
            ForEach(Array(entry.mails.prefix(3).enumerated()), id: \.offset) { item in
              mailLine(item.element, lineLimit: 1)
            }
          }
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    HStack(spacing: 4) {
      Image(systemName: "envelope.fill")
        .font(.caption)
        .foregroundColor(.accentColor)
      Text("KAYDET")
        .font(.caption.weight(.bold))
        .foregroundColor(.primary)
    }
  }

  private var unreadCount: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(entry.unreadCount)")
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .foregroundColor(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      Text("okunmamış")
        .font(.caption)
        .foregroundColor(.secondary)
    }
  }

  private var emptyState: some View {
    Text("Yeni e-posta yok")
      .font(.caption)
      .foregroundColor(.secondary)
  }

  private var composeButton: some View {
    Link(destination: composeURL) {
      Image(systemName: "square.and.pencil")
        .font(.body.weight(.semibold))
        .foregroundColor(.accentColor)
        .frame(width: 28, height: 28)
    }
    .accessibilityLabel("Yeni e-posta")
  }

  private func mailLine(_ text: String, lineLimit: Int) -> some View {
    Text(text)
      .font(.caption)
      .foregroundColor(.primary)
      .lineLimit(lineLimit)
  }
}

extension View {
  // iOS 17 requires containerBackground and supplies its own content margins;
  // earlier versions need explicit padding and background.
  @ViewBuilder
  func widgetBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) {
        Color(UIColor.systemBackground)
      }
    } else {
      padding()
        .background(Color(UIColor.systemBackground))
    }
  }
}

@main
struct KaydetMailWidget: Widget {
  let kind: String = "MailWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      MailWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("KAYDET")
    .description("Okunmamış e-postalar ve son gelenler")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
