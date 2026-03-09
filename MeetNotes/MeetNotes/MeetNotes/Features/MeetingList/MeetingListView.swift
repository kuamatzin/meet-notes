import AppKit
import SwiftUI

struct MeetingListView: View {
    @Environment(MeetingListViewModel.self) private var viewModel
    @Environment(PermissionService.self) private var permissionService
    @Environment(RecordingViewModel.self) private var recordingVM
    @Environment(NavigationState.self) private var navigationState
    @Environment(MeetingDetailViewModel.self) private var meetingDetailVM

    @State private var meetingToDelete: Meeting?
    @State private var meetingToRename: Meeting?
    @State private var renameText = ""

    private var allPermissionsGranted: Bool {
        permissionService.microphoneStatus.isGranted && permissionService.screenRecordingStatus.isGranted
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationSplitView {
            Group {
                if !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && viewModel.sections.isEmpty {
                    EmptySearchResultsView(query: viewModel.searchQuery)
                } else if viewModel.sections.isEmpty {
                    EmptyMeetingListView(
                        allPermissionsGranted: allPermissionsGranted,
                        onStartRecording: { Task { await recordingVM.startRecording() } },
                        onSetUp: {
                        if !permissionService.microphoneStatus.isGranted {
                            Task { await permissionService.requestMicrophone() }
                        } else if !permissionService.screenRecordingStatus.isGranted {
                            permissionService.requestScreenRecording()
                        }
                    }
                    )
                } else {
                    List(selection: $viewModel.selectedMeetingID) {
                        ForEach(viewModel.sections) { section in
                            Section(section.title) {
                                ForEach(section.meetings) { meeting in
                                    MeetingRowView(
                                        title: meeting.title,
                                        date: meeting.startedAt,
                                        durationSeconds: meeting.durationSeconds,
                                        pipelineStatus: meeting.pipelineStatus,
                                        onExport: { exportMeeting(meeting) },
                                        onCopySummary: { copySummary(meeting) },
                                        onDelete: { meetingToDelete = meeting }
                                    )
                                    .tag(meeting.id)
                                    .contextMenu {
                                        contextMenuItems(for: meeting)
                                    }
                                }
                            }
                        }
                    }
                    .onDeleteCommand {
                        guard let id = viewModel.selectedMeetingID,
                              let meeting = viewModel.sections.flatMap(\.meetings).first(where: { $0.id == id })
                        else { return }
                        meetingToDelete = meeting
                    }
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "Search transcripts...")
            .frame(minWidth: 240)
        } detail: {
            if let selectedID = viewModel.selectedMeetingID {
                MeetingDetailView()
                    .onChange(of: selectedID) { _, newID in
                        meetingDetailVM.load(meetingID: newID)
                        updateDetailSearchContext(for: newID)
                    }
                    .onAppear {
                        meetingDetailVM.load(meetingID: selectedID)
                        updateDetailSearchContext(for: selectedID)
                    }
                    .onChange(of: viewModel.searchResults) { _, _ in
                        if let id = viewModel.selectedMeetingID {
                            updateDetailSearchContext(for: id)
                        }
                    }
            } else {
                EmptyMeetingSelectionView()
            }
        }
        .onChange(of: navigationState.selectedMeetingID) { _, newValue in
            if let newValue, viewModel.selectedMeetingID != newValue {
                viewModel.selectedMeetingID = newValue
            }
        }
        .onChange(of: viewModel.selectedMeetingID) { _, newValue in
            navigationState.selectedMeetingID = newValue
        }
        .alert("Delete Meeting?", isPresented: Binding(
            get: { meetingToDelete != nil },
            set: { if !$0 { meetingToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { meetingToDelete = nil }
            Button("Delete", role: .destructive) {
                if let meeting = meetingToDelete {
                    Task { await viewModel.deleteMeeting(id: meeting.id) }
                    meetingToDelete = nil
                }
            }
        } message: {
            if let meeting = meetingToDelete {
                Text("This will permanently delete \"\(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)\" and all its data.")
            }
        }
        .alert("Rename Meeting", isPresented: Binding(
            get: { meetingToRename != nil },
            set: { if !$0 { meetingToRename = nil } }
        )) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { meetingToRename = nil }
            Button("Rename") {
                if let meeting = meetingToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    Task { await viewModel.renameMeeting(id: meeting.id, newTitle: trimmed) }
                }
                meetingToRename = nil
            }
        } message: {
            Text("Enter a new name for this meeting.")
        }
    }

    private func updateDetailSearchContext(for meetingID: String) {
        let query = viewModel.searchQuery
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meetingDetailVM.matchedSegmentIDs = []
            meetingDetailVM.activeSearchQuery = ""
        } else {
            let ids = viewModel.searchResults[meetingID] ?? []
            meetingDetailVM.matchedSegmentIDs = Set(ids)
            meetingDetailVM.activeSearchQuery = query
        }
    }

    @ViewBuilder
    private func contextMenuItems(for meeting: Meeting) -> some View {
        Button("Copy Transcript") { copyTranscript(meeting) }
        Button("Copy Summary") { copySummary(meeting) }
        Divider()
        Button("Export as Markdown") { exportMeeting(meeting) }
        Divider()
        Button("Rename") {
            renameText = meeting.title
            meetingToRename = meeting
        }
        Button("Delete", role: .destructive) { meetingToDelete = meeting }
    }

    private func exportMeeting(_ meeting: Meeting) {
        // Stub: will be implemented in a future story
    }

    private func copySummary(_ meeting: Meeting) {
        if let summary = meeting.summaryMd, !summary.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(summary, forType: .string)
        }
    }

    private func copyTranscript(_ meeting: Meeting) {
        // Stub: will be implemented when transcript access is available
    }
}

struct EmptyMeetingListView: View {
    let allPermissionsGranted: Bool
    var onStartRecording: (() -> Void)?
    var onSetUp: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Meetings Yet")
                .font(.title3)
                .fontWeight(.semibold)
            if allPermissionsGranted {
                Button(action: { onStartRecording?() }) {
                    Label("Start Recording", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: { onSetUp?() }) {
                    Label("Set Up meet-notes", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptySearchResultsView: View {
    let query: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No meetings found for '\(query)'")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct EmptyMeetingSelectionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Select a meeting to view details")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
