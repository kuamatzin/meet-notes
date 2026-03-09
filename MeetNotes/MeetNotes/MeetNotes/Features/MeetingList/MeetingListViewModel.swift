import Foundation
import GRDB
import Observation
import os

private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "MeetingListViewModel")

struct MeetingSection: Identifiable {
    let id: String
    let title: String
    let meetings: [Meeting]
}

@Observable @MainActor final class MeetingListViewModel {
    var sections: [MeetingSection] = []
    var selectedMeetingID: String?
    var searchQuery = "" {
        didSet { performSearch() }
    }
    var searchResults: [String: [Int64]] = [:]

    private let database: AppDatabase
    private let appErrorState: AppErrorState
    private var allMeetings: [Meeting] = []
    private var cancellable: AnyDatabaseCancellable?
    private var searchTask: Task<Void, Never>?

    init(database: AppDatabase, appErrorState: AppErrorState) {
        self.database = database
        self.appErrorState = appErrorState
    }

    func startObservation() {
        let observation = ValueObservation.tracking { db in
            try Meeting.order(Meeting.Columns.startedAt.desc).fetchAll(db)
        }

        cancellable = observation.start(
            in: database.pool,
            scheduling: .immediate,
            onError: { [weak self] error in
                Task { @MainActor in
                    logger.error("Database observation error: \(error)")
                    self?.appErrorState.post(.databaseObservationFailed)
                }
            },
            onChange: { [weak self] meetings in
                Task { @MainActor in
                    self?.allMeetings = meetings
                    if self?.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                        self?.recomputeSections()
                    } else {
                        self?.performSearch()
                    }
                }
            }
        )
    }

    // TODO: Move write operations to a MeetingService actor when created (write-ownership rule)
    func deleteMeeting(id: String) async {
        do {
            try await database.deleteMeeting(id: id)
            if selectedMeetingID == id {
                selectedMeetingID = nil
            }
            logger.info("Deleted meeting \(id)")
        } catch {
            logger.error("Failed to delete meeting: \(error)")
            appErrorState.post(.meetingUpdateFailed)
        }
    }

    func renameMeeting(id: String, newTitle: String) async {
        do {
            try await database.renameMeeting(id: id, newTitle: newTitle)
            logger.info("Renamed meeting \(id)")
        } catch {
            logger.error("Failed to rename meeting: \(error)")
            appErrorState.post(.meetingUpdateFailed)
        }
    }

    private func performSearch() {
        searchTask?.cancel()
        let query = searchQuery
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResults = [:]
            recomputeSections()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await self?.executeSearch(query)
        }
    }

    private func executeSearch(_ query: String) async {
        do {
            let results = try await database.searchSegments(query: query)
            guard !Task.isCancelled else { return }
            var grouped: [String: [Int64]] = [:]
            for result in results {
                grouped[result.meetingId, default: []].append(result.segmentId)
            }
            searchResults = grouped
            let matchingIds = Set(grouped.keys)
            let filtered = allMeetings.filter { matchingIds.contains($0.id) }
            recomputeSections(from: filtered)
        } catch {
            logger.error("Search failed: \(error)")
            appErrorState.post(.searchFailed)
        }
    }

    private func recomputeSections(from meetings: [Meeting]? = nil) {
        let source = meetings ?? allMeetings
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now)!

        var todayMeetings: [Meeting] = []
        var thisWeekMeetings: [Meeting] = []
        var olderGroups: [String: [Meeting]] = [:]

        let monthYearFormatter = DateFormatter()
        monthYearFormatter.dateFormat = "MMMM yyyy"

        for meeting in source {
            if calendar.isDateInToday(meeting.startedAt) {
                todayMeetings.append(meeting)
            } else if meeting.startedAt >= sevenDaysAgo {
                thisWeekMeetings.append(meeting)
            } else {
                let key = monthYearFormatter.string(from: meeting.startedAt)
                olderGroups[key, default: []].append(meeting)
            }
        }

        var result: [MeetingSection] = []

        if !todayMeetings.isEmpty {
            result.append(MeetingSection(id: "today", title: "Today", meetings: todayMeetings))
        }
        if !thisWeekMeetings.isEmpty {
            result.append(MeetingSection(id: "this-week", title: "This Week", meetings: thisWeekMeetings))
        }

        let sortedOlderKeys = olderGroups.keys.sorted { key1, key2 in
            guard let date1 = olderGroups[key1]?.first?.startedAt,
                  let date2 = olderGroups[key2]?.first?.startedAt else { return false }
            return date1 > date2
        }

        for key in sortedOlderKeys {
            if let meetings = olderGroups[key] {
                result.append(MeetingSection(id: key, title: key, meetings: meetings))
            }
        }

        sections = result
    }
}
