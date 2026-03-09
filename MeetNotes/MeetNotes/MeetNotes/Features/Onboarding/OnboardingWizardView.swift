import SwiftUI

struct OnboardingWizardView: View {
    @Environment(OnboardingViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 32) {
            ProgressDotsView(currentStep: viewModel.currentStep)
                .padding(.top, 48)

            Spacer()

            switch viewModel.currentStep {
            case .welcome:
                WelcomeStepView()
            case .permissions:
                PermissionsStepView()
            case .ready:
                ReadyStepView()
            }

            Spacer()
        }
        .padding(.horizontal, 48)
        .frame(minWidth: 600, minHeight: 500)
    }
}

// MARK: - Progress Dots

private struct ProgressDotsView: View {
    let currentStep: OnboardingStep

    private var stepIndex: Int {
        switch currentStep {
        case .welcome: 0
        case .permissions: 1
        case .ready: 2
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == stepIndex ? Color.accent : Color.cardBorder)
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel("Step \(stepIndex + 1) of 3")
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStepView: View {
    @Environment(OnboardingViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accent)

            Text("meet-notes")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text("Local only — your audio never leaves this Mac")
                .font(.title3)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Button {
                if reduceMotion {
                    viewModel.advanceStep()
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.advanceStep()
                    }
                }
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: 280, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .controlSize(.large)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 16)
        }
        .accessibilityLabel("Step 1 of 3")
    }
}

// MARK: - Step 2: Permissions

private struct PermissionsStepView: View {
    @Environment(OnboardingViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Text("Permissions")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text("meet-notes needs a couple of permissions to work")
                .font(.title3)
                .foregroundStyle(.primary)

            VStack(spacing: 16) {
                MicrophonePermissionCard()

                if viewModel.micPermissionGranted {
                    ScreenRecordingPermissionCard()
                        .transition(reduceMotion ? .identity : .opacity)
                }

                if viewModel.allPermissionsGranted {
                    TestRecordingCard()
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viewModel.micPermissionGranted)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viewModel.allPermissionsGranted)
            .padding(.top, 8)

            Button {
                if reduceMotion {
                    viewModel.advanceStep()
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        viewModel.advanceStep()
                    }
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: 280, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .controlSize(.large)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(!viewModel.allPermissionsGranted)
            .padding(.top, 8)
        }
        .accessibilityLabel("Step 2 of 3")
    }
}

private struct MicrophonePermissionCard: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundStyle(Color.accent)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("Microphone")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("meet-notes needs microphone access to hear and transcribe your meetings")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            Spacer()

            if viewModel.micPermissionGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.onDeviceGreen)
                    .font(.title2)
            } else {
                Button("Grant Microphone Access") {
                    Task {
                        await viewModel.requestMicrophonePermission()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cardBorder, lineWidth: 1)
        )
        .accessibilityLabel(viewModel.micPermissionGranted
            ? "Microphone permission granted"
            : "Grant microphone permission")
    }
}

private struct ScreenRecordingPermissionCard: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.title2)
                .foregroundStyle(Color.accent)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("Screen Recording")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("meet-notes uses Screen Recording to capture system audio from Zoom, Google Meet, and other apps. No screen is ever recorded.")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            Spacer()

            if viewModel.screenPermissionGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.onDeviceGreen)
                    .font(.title2)
            } else {
                VStack(spacing: 6) {
                    Button("Open System Settings") {
                        viewModel.requestScreenRecordingPermission()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .foregroundStyle(.primary)

                    Button("I've granted it") {
                        viewModel.confirmScreenRecordingGranted()
                    }
                    .buttonStyle(.plain)
                    .controlSize(.small)
                    .font(.caption)
                    .foregroundStyle(Color.accent)
                }
            }
        }
        .padding(16)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cardBorder, lineWidth: 1)
        )
        .accessibilityLabel(viewModel.screenPermissionGranted
            ? "Screen recording permission granted"
            : "Grant screen recording permission")
    }
}

private struct TestRecordingCard: View {
    @Environment(OnboardingViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(Color.accent)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text("Test Recording")
                    .font(.headline)
                    .foregroundStyle(.primary)

                switch viewModel.testRecordingState {
                case .idle:
                    Text("Try a quick test to make sure everything works")
                        .font(.caption)
                        .foregroundStyle(.primary)
                case .recording:
                    Text("Recording...")
                        .font(.caption)
                        .foregroundStyle(.primary)
                case .completed(let snippet):
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(Color.onDeviceGreen)
                case .unavailable(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }

            Spacer()

            switch viewModel.testRecordingState {
            case .idle:
                Button("Test Recording") {
                    Task {
                        await viewModel.runTestRecording()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.primary)
            case .recording:
                ProgressView()
                    .controlSize(.small)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.onDeviceGreen)
                    .font(.title2)
            case .unavailable:
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.title2)
            }
        }
        .padding(16)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cardBorder, lineWidth: 1)
        )
        .accessibilityLabel(testRecordingAccessibilityLabel)
    }

    private var testRecordingAccessibilityLabel: String {
        switch viewModel.testRecordingState {
        case .idle: "Test recording, ready to start"
        case .recording: "Test recording in progress"
        case .completed(let snippet): "Test recording completed: \(snippet)"
        case .unavailable(let message): "Test recording unavailable: \(message)"
        }
    }
}

// MARK: - Step 3: You're Ready

private struct ReadyStepView: View {
    @Environment(OnboardingViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.onDeviceGreen)

            Text("You're ready!")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text("meet-notes is set up and ready to capture your meetings")
                .font(.title3)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.completeOnboarding()
            } label: {
                Text("Start your first meeting")
                    .font(.headline)
                    .frame(maxWidth: 280, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accent)
            .controlSize(.large)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 16)
        }
        .accessibilityLabel("Step 3 of 3")
    }
}
