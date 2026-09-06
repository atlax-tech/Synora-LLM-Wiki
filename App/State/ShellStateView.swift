import SwiftUI
import SynoraDesignSystem

struct ShellStateView: View {
  let state: ShellContentState
  let retry: (() -> Void)?

  var body: some View {
    VStack(spacing: SynoraSpacing.sm) {
      if state == .loading {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel("Loading")
      } else {
        Image(systemName: state.systemImage)
          .font(.title2)
          .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
      }

      Text(state.title)
        .font(SynoraTypography.sectionTitle.font)
        .foregroundStyle(SynoraSemanticColor.inkPrimary.color)
        .multilineTextAlignment(.center)

      Text(state.message)
        .font(SynoraTypography.body.font)
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      if let retry {
        Button("Retry", action: retry)
          .buttonStyle(.bordered)
          .accessibilityHint("Retries loading the local record index")
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(SynoraSpacing.xl)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(state.title)
    .accessibilityValue(state.message)
    .accessibilityIdentifier("shell-state-\(state.rawValue)")
  }
}

#if DEBUG
  #Preview("Shell states") {
    VStack {
      ShellStateView(state: .offline, retry: nil)
      ShellStateView(state: .error, retry: {})
    }
    .frame(width: 360, height: 320)
    .background(SynoraSemanticColor.canvas.color)
  }
#endif
