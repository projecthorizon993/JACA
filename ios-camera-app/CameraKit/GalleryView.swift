import SwiftUI
import Photos
import PhotosUI

/// Photo gallery view — displays saved photos from the device photo library.
struct GalleryView: View {
    @State private var assets: [PHAsset] = []
    @State private var isLoading = false
    @State private var showingImage: UIImage? = nil

    var body: some View {
        NavigationView {
            VStack {
                if assets.isEmpty && !isLoading {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("No photos yet")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                GalleryThumbnail(asset: asset)
                                    .onTapGesture {
                                        loadImage(from: asset)
                                    }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Gallery")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        loadAssets()
                    }
                }
            }
        }
        .onAppear {
            loadAssets()
        }
        .sheet(item: $showingImage) { image in
            VStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
    }

    private func loadAssets() {
        isLoading = true
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)

        let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
        assets = fetchResult.objects(at: IndexSet(integersIn: 0..<fetchResult.count))
        isLoading = false
    }

    private func loadImage(from asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, info in
            if let image = image {
                showingImage = image
            }
        }
    }
}

/// Thumbnail view for a single photo asset.
struct GalleryThumbnail: View {
    let asset: PHAsset
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.3)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray.opacity(0.5))
                    )
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 200, height: 200),
            contentMode: .aspectFill,
            options: options
        ) { image, info in
            if let image = image {
                thumbnail = image
            }
        }
    }
}
