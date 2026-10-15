import SwiftUI

struct MemoryMomentMarker: View {
    let moment: MemoryMomentCatalog.Entry

    var body: some View {
        VStack(spacing: 3) {
            Image(moment.thumbnailAsset)
                .resizable()
                .scaledToFill()
                .frame(width: 46, height: 38)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(moment.title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 58)
        }
        .padding(.horizontal, 5)
        .padding(.top, 5)
        .padding(.bottom, 4)
        .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Image(systemName: "camera.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(
                    LinearGradient(colors: [.birthdayPurple, .skyBlue], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .offset(x: 4, y: -4)
        }
        .shadow(color: Color.birthdayPurple.opacity(0.28), radius: 6, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(moment.title), Memory Moment, \(moment.locationName)")
    }
}

struct MemoryMomentViewer: View {
    let moment: MemoryMomentCatalog.Entry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var scale: CGFloat = 1
    @State private var appeared = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 16) {
                header
                if moment.photos.count > 1 {
                    storyProgress
                }
                photoStage
                captionBlock
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .opacity(appeared || reduceMotion ? 1 : 0)
        }
        .offset(y: dragOffset)
        .gesture(dismissGesture)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.28)) { appeared = true }
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(moment.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text(moment.locationName)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .accessibilityLabel("Close photo")
        }
    }

    private var storyProgress: some View {
        HStack(spacing: 4) {
            ForEach(Array(moment.photos.enumerated()), id: \.element.id) { index, _ in
                Capsule()
                    .fill(index <= page ? Color.white : Color.white.opacity(0.28))
                    .frame(height: 3)
            }
        }
        .accessibilityLabel("Photo \(page + 1) of \(moment.photos.count)")
    }

    private var photoStage: some View {
        TabView(selection: $page) {
            ForEach(Array(moment.photos.enumerated()), id: \.element.id) { index, photo in
                Image(photo.assetName)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .scaleEffect(scale)
                    .gesture(zoomGesture)
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: reduceMotion ? 0.01 : 0.2)) {
                            scale = scale > 1 ? 1 : 2
                        }
                    }
                    .padding(.horizontal, 4)
                    .tag(index)
                    .accessibilityLabel(moment.title)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: moment.photos.count > 1 ? .automatic : .never))
        .frame(maxHeight: .infinity)
    }

    private var captionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let caption = moment.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
            }
            if let date = moment.date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 20)
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(value.magnification, 1), 4)
            }
            .onEnded { _ in
                if scale < 1.05 {
                    withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.18)) { scale = 1 }
                }
            }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard scale <= 1.05, value.translation.height > 0, abs(value.translation.height) > abs(value.translation.width) else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 140, scale <= 1.05 {
                    dismiss()
                } else {
                    withAnimation(.easeOut(duration: reduceMotion ? 0.01 : 0.2)) { dragOffset = 0 }
                }
            }
    }
}
