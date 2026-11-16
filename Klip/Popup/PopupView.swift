import SwiftUI

/// A notch-attached copy indicator that opens a bounded preview on click.
struct PopupView: View {
    @Bindable var state: PopupState
    var onClick: () -> Void = {}

    private var surfaceHeight: CGFloat {
        state.showsPreview ? PopupLayout.previewSize.height : PopupLayout.size.height
    }

    var body: some View {
        ZStack(alignment: .top) {
            NotchExtension()
                .fill(.black)

            if state.showsPreview {
                Group {
                    if state.previewIsImage, let image = state.previewImage {
                        Image(nsImage: image)
                            .resizable()
                            .renderingMode(.original)
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        HStack(spacing: 5) {
                            Group {
                                if let image = state.previewImage {
                                    Image(nsImage: image).resizable().renderingMode(.original).scaledToFit()
                                } else {
                                    Image(systemName: state.previewSymbol)
                                        .font(.system(size: 19, weight: .regular))
                                }
                            }
                            .frame(width: state.previewImage == nil ? 20 : 32, height: 48)
                            .foregroundStyle(.white.opacity(0.65))
                            Text(state.previewText)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, state.previewIsImage && state.previewImage != nil
                    ? PopupLayout.previewHorizontalPadding : PopupLayout.previewPadding)
                .padding(.horizontal, PopupLayout.previewHorizontalPadding)
                // Keep attachment insets outside the straight black body and
                // ten points between the content box and each horizontal body edge.
                .frame(width: state.width - PopupLayout.shoulder * 2, height: PopupLayout.previewSize.height)
                .transition(.opacity)
            } else {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(height: PopupLayout.size.height)
            }
        }
        .frame(width: state.width, height: surfaceHeight, alignment: .top)
        .clipShape(NotchExtension())
        // Translate the complete black surface and content as one piece beneath
        // the hardware notch; keep the native window attachment stationary.
        .offset(y: state.isExpanded ? 0 : -surfaceHeight)
        .animation(state.reduceMotion ? nil : (state.isExpanded
            ? .spring(response: 0.38, dampingFraction: 1)
            : .easeInOut(duration: PopupLayout.retractionDuration)), value: state.isExpanded)
        .animation(state.reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 1), value: state.showsPreview)
        .frame(width: state.canvasWidth, height: state.canvasHeight, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onClick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.showsPreview ? state.previewText : "Copied")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Show copied content", onClick)
    }
}

/// An upward-curved join stays inside the notch sides, with rounded lower corners.
private struct NotchExtension: Shape {
    func path(in rect: CGRect) -> Path {
        let shoulder = min(PopupLayout.shoulder, rect.height / 2)
        let radius = min(PopupLayout.bottomRadius, rect.height / 2)
        let joinInset = min(PopupLayout.topCurveDepth, shoulder)
        var path = Path()
        path.move(to: CGPoint(x: shoulder, y: joinInset))
        // Curve upward inside the body width, without protruding side tips.
        path.addQuadCurve(to: CGPoint(x: rect.width - shoulder, y: joinInset),
                          control: CGPoint(x: rect.midX, y: -joinInset))
        path.addLine(to: CGPoint(x: rect.width - shoulder, y: rect.height - radius))
        path.addQuadCurve(to: CGPoint(x: rect.width - shoulder - radius, y: rect.height),
                          control: CGPoint(x: rect.width - shoulder, y: rect.height))
        path.addLine(to: CGPoint(x: shoulder + radius, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: shoulder, y: rect.height - radius),
                          control: CGPoint(x: shoulder, y: rect.height))
        path.addLine(to: CGPoint(x: shoulder, y: joinInset))
        path.closeSubpath()
        return path
    }
}

#Preview {
    PopupView(state: PopupState(isExpanded: true))
}
