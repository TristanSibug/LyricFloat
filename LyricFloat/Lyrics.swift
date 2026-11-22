import Foundation

struct LyricCue: Sendable {
    let time: TimeInterval
    let text: String
}

struct Lyrics: Sendable {
    let title: String
    let cues: [LyricCue]

    var duration: TimeInterval { (cues.last?.time ?? 0) + 5 }

    func index(at time: TimeInterval) -> Int? {
        var lower = 0
        var upper = cues.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if cues[middle].time <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower == 0 ? nil : lower - 1
    }

    static func parse(_ lrc: String, fallbackTitle: String) throws -> Lyrics {
        let lineStamp = #/\[(\d{1,4}):([0-5]\d)(?:[.:](\d{1,3}))?\]/#
        let wordStamp = #/<\d{1,4}:[0-5]\d(?:[.:]\d{1,3})?>/#
        var title = fallbackTitle
        var offset = 0.0
        var cues: [LyricCue] = []

        for raw in lrc.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{FEFF}")))
            let prefix = line.prefix(8).lowercased()
            if prefix.hasPrefix("[ti:"), line.hasSuffix("]") {
                let value = line.dropFirst(4).dropLast().trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { title = value }
                continue
            }
            if prefix == "[offset:", line.hasSuffix("]"),
               let milliseconds = Int(line.dropFirst(8).dropLast().trimmingCharacters(in: .whitespaces)) {
                offset = Double(milliseconds) / 1000
                continue
            }

            let stamps = line.matches(of: lineStamp)
            guard stamps.first?.range.lowerBound == line.startIndex else { continue }
            var textStart = line.startIndex
            var times: [TimeInterval] = []

            for stamp in stamps {
                guard stamp.range.lowerBound == textStart else { break }
                textStart = stamp.range.upperBound
                let (_, minutes, seconds, fraction) = stamp.output
                guard let minuteValue = Double(minutes), let secondValue = Double(seconds) else { continue }
                let fractionalSeconds = fraction.flatMap { Double("0." + String($0)) } ?? 0
                times.append(minuteValue * 60 + secondValue + fractionalSeconds)
            }

            let text = String(line[textStart...])
                .replacing(wordStamp, with: "")
                .trimmingCharacters(in: .whitespaces)
            cues.append(contentsOf: times.map { LyricCue(time: $0, text: text) })
        }

        guard cues.contains(where: { !$0.text.isEmpty }) else { throw LRCError.noTimedLyrics }
        let timeline = cues.map { LyricCue(time: max(0, $0.time - offset), text: $0.text) }
            .sorted { $0.time < $1.time }
        return Lyrics(title: title, cues: timeline)
    }

    enum LRCError: LocalizedError {
        case noTimedLyrics

        var errorDescription: String? { "This file needs at least one timestamped lyric line." }
    }
}
