import Foundation
import Postbox
import TelegramApi

import SyncCore

func telegramMediaImageRepresentationsFromApiSizes(datacenterId: Int32, photoId: Int64, accessHash: Int64, fileReference: Data?, sizes: [Api.PhotoSize]) -> (immediateThumbnail: Data?, representations:  [TelegramMediaImageRepresentation]) {
    var immediateThumbnailData: Data?
    var representations: [TelegramMediaImageRepresentation] = []
    for size in sizes {
        switch size {
            case let .photoCachedSize(type, location, w, h, _):
                switch location {
                    case let .fileLocationToBeDeprecated(volumeId, localId):
                        let resource = CloudPhotoSizeMediaResource(datacenterId: datacenterId, photoId: photoId, accessHash: accessHash, sizeSpec: type, volumeId: volumeId, localId: localId, size: nil, fileReference: fileReference)
                        representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: w, height: h), resource: resource))
                }
            case let .photoSize(type, location, w, h, size):
                switch location {
                    case let .fileLocationToBeDeprecated(volumeId, localId):
                        let resource = CloudPhotoSizeMediaResource(datacenterId: datacenterId, photoId: photoId, accessHash: accessHash, sizeSpec: type, volumeId: volumeId, localId: localId, size: Int(size), fileReference: fileReference)
                        representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: w, height: h), resource: resource))
                }
            case let .photoStrippedSize(_, data):
                immediateThumbnailData = data.makeData()
            case .photoSizeEmpty:
                break
        }
    }
    return (immediateThumbnailData, representations)
}

func telegramMediaImageFromApiPhoto(_ photo: Api.Photo) -> TelegramMediaImage? {
    switch photo {
        case let .photo(flags, id, accessHash, fileReference, _, sizes, videoSizes, dcId):
            let (immediateThumbnailData, representations) = telegramMediaImageRepresentationsFromApiSizes(datacenterId: dcId, photoId: id, accessHash: accessHash, fileReference: fileReference.makeData(), sizes: sizes)
            var imageFlags: TelegramMediaImageFlags = []
            let hasStickers = (flags & (1 << 0)) != 0
            if hasStickers {
                imageFlags.insert(.hasStickers)
            }
            
            var videoRepresentations: [TelegramMediaImage.VideoRepresentation] = []
            if let videoSizes = videoSizes {
                for size in videoSizes {
                    switch size {
                        case let .videoSize(type, location, w, h, size):
                            let resource: TelegramMediaResource
                            switch location {
                                case let .fileLocationToBeDeprecated(volumeId, localId):
                                    resource = CloudPhotoSizeMediaResource(datacenterId: dcId, photoId: id, accessHash: accessHash, sizeSpec: type, volumeId: volumeId, localId: localId, size: Int(size), fileReference: fileReference.makeData())
                            }
                            
                            videoRepresentations.append(TelegramMediaImage.VideoRepresentation(
                                dimensions: PixelDimensions(width: w, height: h),
                                resource: resource))
                    }
                }
            }
            
            return TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: id), representations: representations, videoRepresentations: videoRepresentations, immediateThumbnailData: immediateThumbnailData, reference: .cloud(imageId: id, accessHash: accessHash, fileReference: fileReference.makeData()), partialReference: nil, flags: imageFlags)
        case .photoEmpty:
            return nil
    }
}
