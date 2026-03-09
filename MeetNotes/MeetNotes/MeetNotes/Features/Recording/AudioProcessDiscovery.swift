@preconcurrency import CoreAudio
import os

nonisolated(unsafe) private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "AudioProcessDiscovery")

nonisolated struct AudioProcessDiscovery {
    static let knownMeetingAppBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.google.Chrome",
        "com.brave.Browser",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.cisco.webex.meetings",
        "com.tinyspeck.slackmacgap",
        "com.discord.discord"
    ]

    static func translatePID(_ pid: pid_t) -> AudioObjectID? {
        var pid = pid
        var objectID = AudioObjectID()
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &pid,
            &size,
            &objectID
        )
        guard status == noErr else {
            logger.warning("Failed to translate PID \(pid) to AudioObjectID: \(status)")
            return nil
        }
        return objectID
    }

    static func discoverRunningAudioProcesses() -> [(pid: pid_t, bundleID: String?, objectID: AudioObjectID)] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard status == noErr, size > 0 else {
            logger.warning("Failed to get process object list size: \(status)")
            return []
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objectIDs = [AudioObjectID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &objectIDs
        )
        guard status == noErr else {
            logger.warning("Failed to get process object list: \(status)")
            return []
        }

        var results: [(pid: pid_t, bundleID: String?, objectID: AudioObjectID)] = []
        for objectID in objectIDs {
            let pid = pidForProcessObject(objectID)
            let bundleID = bundleIDForProcessObject(objectID)
            results.append((pid: pid, bundleID: bundleID, objectID: objectID))
        }
        return results
    }

    static func findMeetingAppProcess() -> AudioObjectID? {
        let processes = discoverRunningAudioProcesses()
        for process in processes where process.bundleID != nil {
            if knownMeetingAppBundleIDs.contains(process.bundleID!) {
                let isRunning = isProcessRunningAudio(process.objectID)
                if isRunning {
                    logger.info("Found meeting app: \(process.bundleID!) (objectID: \(process.objectID))")
                    return process.objectID
                }
            }
        }
        logger.info("No known meeting app found among \(processes.count) audio processes")
        return nil
    }

    // MARK: - Private Helpers

    private static func pidForProcessObject(_ objectID: AudioObjectID) -> pid_t {
        var pid = pid_t()
        var size = UInt32(MemoryLayout<pid_t>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &pid)
        return pid
    }

    private static func bundleIDForProcessObject(_ objectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var bundleID: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &bundleID)
        guard status == noErr else { return nil }
        return bundleID as String
    }

    private static func isProcessRunningAudio(_ objectID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunning,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunning: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &isRunning)
        guard status == noErr else { return false }
        return isRunning != 0
    }

    private init() {}
}
