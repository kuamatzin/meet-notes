import Testing
@testable import MeetNotes

struct AudioProcessDiscoveryTests {

    @Test func knownMeetingAppBundleIDsContainsExpectedEntries() {
        let ids = AudioProcessDiscovery.knownMeetingAppBundleIDs
        #expect(ids.contains("us.zoom.xos"))
        #expect(ids.contains("com.microsoft.teams"))
        #expect(ids.contains("com.microsoft.teams2"))
        #expect(ids.contains("com.google.Chrome"))
        #expect(ids.contains("com.brave.Browser"))
        #expect(ids.contains("com.apple.Safari"))
        #expect(ids.contains("org.mozilla.firefox"))
        #expect(ids.contains("com.cisco.webex.meetings"))
        #expect(ids.contains("com.tinyspeck.slackmacgap"))
        #expect(ids.contains("com.discord.discord"))
    }

    @Test func knownMeetingAppBundleIDsCountIsExpected() {
        #expect(AudioProcessDiscovery.knownMeetingAppBundleIDs.count == 10)
    }

    @Test func findMeetingAppProcessReturnsNilOrValidID() {
        let result = AudioProcessDiscovery.findMeetingAppProcess()
        // In test environments, typically no meeting app is running audio
        // If a result is returned, it must be a valid non-zero AudioObjectID
        if let objectID = result {
            #expect(objectID != 0)
        }
    }

    @Test func discoverRunningAudioProcessesReturnsValidEntries() {
        let processes = AudioProcessDiscovery.discoverRunningAudioProcesses()
        // Every discovered process must have a non-zero AudioObjectID
        for process in processes {
            #expect(process.objectID != 0)
        }
    }
}
