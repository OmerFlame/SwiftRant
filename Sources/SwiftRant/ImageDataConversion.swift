//
//  ImageDataConversion.swift
//
//  Created by Wilhelm Oks on 18.11.22.
//

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private struct ImageHeaderData {
    static let png: UInt8 = 0x89
    static let jpeg: UInt8 = 0xFF
    static let gif: UInt8 = 0x47
    static let tiff_01: UInt8 = 0x49
    static let tiff_02: UInt8 = 0x4D
}

enum ImageFormat {
    case png
    case jpeg
    case gif
    case tiff
}

extension Data {
    var imageFormat: ImageFormat? {
        let buffer = self.first
        if buffer == ImageHeaderData.png {
            return .png
        } else if buffer == ImageHeaderData.jpeg {
            return .jpeg
        } else if buffer == ImageHeaderData.gif {
            return .gif
        } else if buffer == ImageHeaderData.tiff_01 || buffer == ImageHeaderData.tiff_02 {
            return .tiff
        } else {
            return nil
        }
    }
}

public protocol ImageDataConverter {
    /// Converts the image `data` to another format and returns the resulting Data.
    func convert(_ data: Data) -> Data
}

public extension ImageDataConverter {
    #if os(macOS)
    func jpegData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .jpeg, properties: [:])
    }
    #endif
}

extension Collection where Element == ImageDataConverter {
    /// Applies all converters to the provided `data` sequentially and returns the result.
    func convert(_ data: Data) -> Data {
        var result = data
        for converter in self {
            result = converter.convert(result)
        }
        return result
    }
}

/// An `ImageDataConverter` that converts image formats which are not supported by devRant to jpeg.
/// Data of supported formats is just returned without any conversion.
/// If the conversion fails, the original Data is returned.
public struct UnsupportedToJpegImageDataConverter: ImageDataConverter {
    public func convert(_ data: Data) -> Data {
        switch data.imageFormat {
        case nil: // Format not recognized so it's probably not supported by devRant.
            #if os(iOS)
            return UIImage(data: data)?.jpegData(compressionQuality: 1) ?? data
            #elseif os(macOS)
            return NSImage(data: data).flatMap(jpegData) ?? data
            #endif
        default: // Supported format recognized. No conversion needed.
            return data
        }
    }
}

public extension ImageDataConverter where Self == UnsupportedToJpegImageDataConverter {
    static var unsupportedToJpeg: Self { Self() }
}
