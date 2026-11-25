import ActivityKit

struct LyricActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let title: String
        let line: String
        let themeID: String
        let fontID: String
    }
}
