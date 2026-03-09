@preconcurrency import AVFAudio
@preconcurrency import CoreAudio
import os

nonisolated(unsafe) private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "SystemAudioCapture")

nonisolated protocol SystemAudioCaptureProtocol: Sendable {
    var audioStream: AsyncStream<AVAudioPCMBuffer> { get }
    func start(processObjectID: AudioObjectID?) throws(RecordingError)
    func stop()
    func isTapHealthy() -> Bool
    func pause()
    func resume() throws(RecordingError)
}

nonisolated final class SystemAudioCapture: SystemAudioCaptureProtocol, @unchecked Sendable {
    let audioStream: AsyncStream<AVAudioPCMBuffer>
    private let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation

    private var tapUUIDString: String?
    private var processTapID: AudioObjectID = 0
    private var aggregateDeviceID: AudioObjectID = 0
    private var deviceProcID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "com.kuamatzin.meet-notes.system-audio-io", qos: .userInteractive)

    private let _lastBufferLockPtr: UnsafeMutablePointer<os_unfair_lock>
    private let _lastBufferTimePtr: UnsafeMutablePointer<UInt64>

    init() {
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.audioStream = stream
        self.continuation = continuation

        _lastBufferLockPtr = .allocate(capacity: 1)
        _lastBufferLockPtr.initialize(to: os_unfair_lock())
        _lastBufferTimePtr = .allocate(capacity: 1)
        _lastBufferTimePtr.initialize(to: 0)
    }

    func start(processObjectID: AudioObjectID?) throws(RecordingError) {
        let tapDesc: CATapDescription
        if let processObjectID {
            tapDesc = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        } else {
            tapDesc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        }
        tapDesc.muteBehavior = .unmuted
        self.tapUUIDString = tapDesc.uuid.uuidString

        // Create process tap
        var tapID = AudioObjectID()
        var status = AudioHardwareCreateProcessTap(tapDesc, &tapID)
        guard status == noErr else {
            logger.error("AudioHardwareCreateProcessTap failed: \(status)")
            throw .audioTapCreationFailed
        }
        self.processTapID = tapID

        // Read tap format
        let tapFormat = try readTapFormat(tapID: tapID)

        // Get system output device UID
        let outputDeviceUID = try getDefaultOutputDeviceUID()

        // Create aggregate device
        let aggDeviceID = try createAggregateDevice(tapUUID: tapDesc.uuid.uuidString, outputDeviceUID: outputDeviceUID)
        self.aggregateDeviceID = aggDeviceID

        // Install IOProc
        let cont = self.continuation
        let lockPtr = _lastBufferLockPtr
        let timePtr = _lastBufferTimePtr
        var procID: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggDeviceID, ioQueue) {
            _, inInputData, _, _, _ in
            // REAL-TIME THREAD — timestamp + yield only
            let now = mach_absolute_time()
            os_unfair_lock_lock(lockPtr)
            timePtr.pointee = now
            os_unfair_lock_unlock(lockPtr)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: tapFormat,
                bufferListNoCopy: inInputData,
                deallocator: nil
            ) else { return }
            cont.yield(buffer)
        }
        guard status == noErr, let procID else {
            logger.error("AudioDeviceCreateIOProcIDWithBlock failed: \(status)")
            teardown()
            throw .audioTapCreationFailed
        }
        self.deviceProcID = procID

        // Start device
        status = AudioDeviceStart(aggDeviceID, procID)
        guard status == noErr else {
            logger.error("AudioDeviceStart failed: \(status)")
            teardown()
            throw .audioTapCreationFailed
        }

        logger.info("System audio capture started (tap ID: \(tapID), aggregate: \(aggDeviceID))")
    }

    func stop() {
        teardown()
        continuation.finish()
        logger.info("System audio capture stopped")
    }

    func isTapHealthy() -> Bool {
        os_unfair_lock_lock(_lastBufferLockPtr)
        let lastTime = _lastBufferTimePtr.pointee
        os_unfair_lock_unlock(_lastBufferLockPtr)
        guard lastTime > 0 else { return true }
        let elapsed = Self.machTimeToSeconds(mach_absolute_time() - lastTime)
        return elapsed < 2.0
    }

    func pause() {
        guard let procID = deviceProcID, aggregateDeviceID != 0 else { return }
        AudioDeviceStop(aggregateDeviceID, procID)
        logger.info("System audio capture paused")
    }

    func resume() throws(RecordingError) {
        guard let procID = deviceProcID, aggregateDeviceID != 0 else {
            throw .audioTapCreationFailed
        }
        let status = AudioDeviceStart(aggregateDeviceID, procID)
        guard status == noErr else {
            logger.error("AudioDeviceStart failed on resume: \(status)")
            throw .audioTapCreationFailed
        }
        logger.info("System audio capture resumed")
    }

    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func machTimeToSeconds(_ elapsed: UInt64) -> Double {
        let nanos = Double(elapsed) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom)
        return nanos / 1_000_000_000
    }

    // MARK: - Private

    private func readTapFormat(tapID: AudioObjectID) throws(RecordingError) -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr else {
            logger.error("Failed to read tap format: \(status)")
            throw .audioFormatError
        }
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            logger.error("Failed to create AVAudioFormat from tap ASBD")
            throw .audioFormatError
        }
        return format
    }

    private func getDefaultOutputDeviceUID() throws(RecordingError) -> String {
        var deviceID = AudioObjectID()
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr else {
            logger.error("Failed to get default output device: \(status)")
            throw .aggregateDeviceCreationFailed
        }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        status = AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &size, &uid)
        guard status == noErr else {
            logger.error("Failed to get output device UID: \(status)")
            throw .aggregateDeviceCreationFailed
        }
        return uid as String
    }

    private func createAggregateDevice(tapUUID: String, outputDeviceUID: String) throws(RecordingError) -> AudioObjectID {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MeetNotes-Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUUID
                ]
            ]
        ]

        var aggDeviceID = AudioObjectID()
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggDeviceID)
        guard status == noErr else {
            logger.error("AudioHardwareCreateAggregateDevice failed: \(status)")
            throw .aggregateDeviceCreationFailed
        }
        return aggDeviceID
    }

    private func teardown() {
        if let procID = deviceProcID, aggregateDeviceID != 0 {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            deviceProcID = nil
        }
        if aggregateDeviceID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = 0
        }
        if processTapID != 0 {
            AudioHardwareDestroyProcessTap(processTapID)
            processTapID = 0
        }
        tapUUIDString = nil
    }

    deinit {
        teardown()
        _lastBufferLockPtr.deinitialize(count: 1)
        _lastBufferLockPtr.deallocate()
        _lastBufferTimePtr.deinitialize(count: 1)
        _lastBufferTimePtr.deallocate()
    }
}
