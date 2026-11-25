import SwiftUI
import Photos
import CoreLocation

/// Reads (never changes) your photo library so the Journal can show photos from the day, and from each place.
@MainActor
final class JournalPhotos: ObservableObject {
    static let shared = JournalPhotos()

    @Published private(set) var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var allowed: Bool { status == .authorized || status == .limited }
    var undecided: Bool { status == .notDetermined }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Photos and videos taken between two times, oldest first.
    func assets(from start: Date, to end: Date) -> [PHAsset] {
        guard allowed, start < end else { return [] }
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@ AND (mediaType == %d OR mediaType == %d)",
                                     start as NSDate, end as NSDate,
                                     PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var out: [PHAsset] = []
        PHAsset.fetchAssets(with: opts).enumerateObjects { a, _, _ in out.append(a) }
        return out
    }

    /// Everything from one day.
    func assets(onDay day: Date) -> [PHAsset] {
        let start = Calendar.current.startOfDay(for: day)
        return assets(from: start, to: Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start)
    }

    /// Photos from a place: taken within ~300 m of it that day, or (with no location saved) while you were there.
    func assets(for group: PlaceGroup, radius: CLLocationDistance = 300) -> [PHAsset] {
        let place = group.visits[0].stay.location
        let windows = group.visits.map { ($0.stay.arrived.addingTimeInterval(-10 * 60), ($0.end ?? .now).addingTimeInterval(10 * 60)) }
        return assets(onDay: group.start).filter { a in
            if let loc = a.location { return loc.distance(from: place) <= radius }
            guard let d = a.creationDate else { return false }
            return windows.contains { d >= $0.0 && d <= $0.1 }
        }
    }
}

/// A square thumbnail from the photo library.
struct PhotoThumb: View {
    let asset: PHAsset
    var size: CGFloat = 72
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.08))
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            if asset.mediaType == .video {
                Image(systemName: "play.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: asset.localIdentifier) {
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .opportunistic
            opts.isNetworkAccessAllowed = true
            let scale = 3.0
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: size * scale, height: size * scale),
                                                  contentMode: .aspectFill, options: opts) { img, _ in
                if let img { Task { @MainActor in image = img } }
            }
        }
    }
}

/// A row of thumbnails; tap one to open it full screen.
struct PhotoStrip: View {
    let assets: [PHAsset]
    var size: CGFloat = 72
    @State private var open: PhotoViewerItem?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { i, a in
                    Button { open = PhotoViewerItem(index: i) } label: { PhotoThumb(asset: a, size: size) }
                        .buttonStyle(.plain)
                }
            }
        }
        .frame(height: size)
        .fullScreenCover(item: $open) { item in PhotoViewer(assets: assets, index: item.index) }
    }
}

struct PhotoViewerItem: Identifiable {
    let index: Int
    var id: Int { index }
}

/// Swipe through photos full screen.
struct PhotoViewer: View {
    let assets: [PHAsset]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(assets.enumerated()), id: \.element.localIdentifier) { i, a in
                FullPhoto(asset: a).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: assets.count > 1 ? .automatic : .never))
        .background(Color.black.ignoresSafeArea())
        .offset(y: max(0, dragY))
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { v in if abs(v.translation.height) > abs(v.translation.width) { dragY = v.translation.height } }
                .onEnded { v in
                    if v.translation.height > 120 { dismiss() } else { withAnimation(.snappy) { dragY = 0 } }
                }
        )
        // Controls sit in the safe area above the pager, so taps never go to the photo underneath.
        .safeAreaInset(edge: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .glassCircle()
                        .frame(width: 60, height: 60)      // bigger invisible tap area
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if let d = assets[safe: index]?.creationDate {
                    Text(d.formatted(date: .abbreviated, time: .shortened))
                        .font(.rounded(13, .heavy)).padding(.horizontal, 12).padding(.vertical, 8)
                        .glassCapsule()
                }
            }
            .padding(.horizontal, 10)
        }
        .preferredColorScheme(.dark)
    }

    @State private var dragY: CGFloat = 0
}

private struct FullPhoto: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
            if asset.mediaType == .video {
                Image(systemName: "video.fill").font(.title3).foregroundStyle(.white).padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .task(id: asset.localIdentifier) {
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .opportunistic
            opts.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 1600, height: 1600),
                                                  contentMode: .aspectFit, options: opts) { img, _ in
                if let img { Task { @MainActor in image = img } }
            }
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
