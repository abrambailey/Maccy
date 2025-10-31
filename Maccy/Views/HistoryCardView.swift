import Defaults
import SwiftUI

struct HistoryCardView: View {
  @Bindable var item: HistoryItemDecorator
  let searchQuery: String

  @Environment(AppState.self) private var appState
  @Default(.imageMaxHeight) private var imageMaxHeight

  private var highlightedContent: AttributedString {
    highlightSearchMatches(in: textAroundMatch, query: searchQuery)
  }

  private var firstMatchRange: Range<String.Index>? {
    guard !searchQuery.isEmpty else { return nil }
    return item.text.range(of: searchQuery, options: .caseInsensitive)
  }

  private var textAroundMatch: String {
    guard let matchRange = firstMatchRange else {
      return String(item.text.prefix(500)) // Show first 500 chars when not searching
    }

    // Calculate start position (show some context before match)
    let matchStart = matchRange.lowerBound
    let contextChars = 200

    let startIndex: String.Index
    if let newlineBeforeMatch = item.text[..<matchStart].lastIndex(of: "\n") {
      // Start from the line containing the match
      startIndex = item.text.index(after: newlineBeforeMatch)
    } else if matchStart > item.text.startIndex {
      // Or go back contextChars
      startIndex = item.text.index(matchStart, offsetBy: -min(contextChars, item.text.distance(from: item.text.startIndex, to: matchStart)))
    } else {
      startIndex = item.text.startIndex
    }

    // Show match + context after (about 800 chars total)
    let endOffset = min(800, item.text.distance(from: startIndex, to: item.text.endIndex))
    let endIndex = item.text.index(startIndex, offsetBy: endOffset, limitedBy: item.text.endIndex) ?? item.text.endIndex

    return String(item.text[startIndex..<endIndex])
  }

  private var cardWidth: CGFloat { 280 }
  private var cardHeight: CGFloat { 200 }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Header with app icon
      HStack(spacing: 6) {
        Image(nsImage: item.applicationImage.nsImage)
          .resizable()
          .frame(width: 16, height: 16)

        if let app = item.application {
          Text(app)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        // Character count badge
        Text("\(item.text.count) chars")
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(.quaternary.opacity(0.5))
          .clipShape(Capsule())
      }
      .padding(.horizontal, 12)
      .padding(.top, 10)

      // Content area - either image or text
      if let thumbnailImage = item.thumbnailImage {
        // Image content
        Image(nsImage: thumbnailImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(maxWidth: .infinity, maxHeight: cardHeight - 80)
          .clipped()
      } else {
        // Text content with highlighting
        ScrollView {
          Text(highlightedContent)
            .font(.system(size: 11))
            .lineLimit(searchQuery.isEmpty ? 8 : 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: cardHeight - 80)
      }

      Spacer()

      // Footer with shortcuts
      if !item.shortcuts.isEmpty {
        HStack(spacing: 4) {
          ForEach(Array(item.shortcuts.enumerated()), id: \.offset) { _, shortcut in
            Text(shortcut.description)
              .font(.caption2)
              .padding(.horizontal, 4)
              .padding(.vertical, 2)
              .background(.blue.opacity(0.2))
              .clipShape(RoundedRectangle(cornerRadius: 3))
          }
          Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
      }
    }
    .frame(width: cardWidth, height: cardHeight)
    .background {
      RoundedRectangle(cornerRadius: 12)
        .fill(item.isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
        .shadow(color: .black.opacity(0.1), radius: item.isSelected ? 6 : 3, y: 2)
    }
    .overlay {
      if item.isSelected {
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.accentColor, lineWidth: 2)
      }
    }
    .onTapGesture {
      appState.history.select(item)
    }
    .onAppear {
      // Lazy load images when card becomes visible
      item.ensureImagesGenerated()
    }
    .animation(.easeInOut(duration: 0.15), value: item.isSelected)
  }

  private func highlightSearchMatches(in text: String, query: String) -> AttributedString {
    guard !query.isEmpty else {
      return AttributedString(text)
    }

    var attributedString = AttributedString(text)

    // Find all matches using case-insensitive search
    var searchRange = text.startIndex..<text.endIndex
    while let range = text.range(of: query, options: .caseInsensitive, range: searchRange) {
      let nsRange = NSRange(range, in: text)
      if let attributedRange = Range<AttributedString.Index>(nsRange, in: attributedString) {
        attributedString[attributedRange].backgroundColor = .yellow.opacity(0.4)
        attributedString[attributedRange].foregroundColor = .primary
      }

      // Move past this match
      searchRange = range.upperBound..<text.endIndex
      if searchRange.isEmpty {
        break
      }
    }

    return attributedString
  }
}
