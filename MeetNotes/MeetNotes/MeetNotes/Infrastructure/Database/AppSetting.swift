import GRDB

struct AppSetting: Codable, FetchableRecord, PersistableRecord, Sendable {
    var key: String
    var value: String

    static let databaseTableName = "settings"

    enum Columns {
        static let key = Column(CodingKeys.key)
        static let value = Column(CodingKeys.value)
    }
}
