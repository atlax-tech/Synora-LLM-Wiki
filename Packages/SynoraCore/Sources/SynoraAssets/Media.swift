import AVFoundation
import Foundation
import PDFKit
import QuickLookUI
import SynoraDomain

#if canImport(AVKit) && canImport(AppKit) && canImport(SwiftUI)
import AVKit
import AppKit
import SwiftUI
#endif

public enum MediaAssetError: Error, Equatable, Sendable {
  case missingOriginal
  case unsupportedMedia
  case unreadableMedia
}

public enum MediaPreviewFailure: String, Codable, Hashable, Sendable {
  case missingOriginal
  case unreadableOriginal
  case unsupportedMedia
  case cancelled

  public var message: String {
    switch self {
    case .missingOriginal: "Original file is unavailable"
    case .unreadableOriginal: "Original file could not be previewed"
    case .unsupportedMedia: "This media type has no preview"
    case .cancelled: "Preview cancelled"
    }
  }
}

public enum MediaPreviewState: Codable, Hashable, Sendable {
  case ready(AssetPreview)
  case failed(MediaPreviewFailure)
}

public struct MediaPreviewRequest: Hashable, Sendable {
  public let blockID: UUID
  public let blockRevision: Int
  public let asset: Asset
  public let thumbnailPixelSize: Int

  public init(
    blockID: UUID,
    blockRevision: Int,
    asset: Asset,
    thumbnailPixelSize: Int = 320
  ) {
    self.blockID = blockID
    self.blockRevision = blockRevision
    self.asset = asset
    self.thumbnailPixelSize = max(thumbnailPixelSize, 1)
  }
}

public struct MediaPreviewResult: Hashable, Sendable {
  public let blockID: UUID
  public let blockRevision: Int
  public let assetID: UUID
  public let state: MediaPreviewState

  public init(
    blockID: UUID,
    blockRevision: Int,
    assetID: UUID,
    state: MediaPreviewState
  ) {
    self.blockID = blockID
    self.blockRevision = blockRevision
    self.assetID = assetID
    self.state = state
  }
}

public actor MediaPreviewCoordinator {
  private struct RequestKey: Hashable {
    let blockID: UUID
    let assetID: UUID
  }

  private let store: AssetStore
  private let prefetchLimit: Int
  private var activeRequests: [RequestKey: MediaPreviewRequest] = [:]

  public init(store: AssetStore, prefetchLimit: Int = 2) {
    self.store = store
    self.prefetchLimit = max(prefetchLimit, 0)
  }

  public func cancel(blockID: UUID) {
    activeRequests = activeRequests.filter { $0.value.blockID != blockID }
  }

  public func load(_ request: MediaPreviewRequest) async -> MediaPreviewResult? {
    let key = RequestKey(blockID: request.blockID, assetID: request.asset.id)
    activeRequests[key] = request
    let state: MediaPreviewState
    do {
      try Task.checkCancellation()
      guard store.hasOriginal(for: request.asset) else {
        state = .failed(.missingOriginal)
        return finish(request, state: state)
      }

      let expectedKind = store.mediaKind(for: request.asset)
      var preview = store.preview(for: request.asset)
      guard preview.kind == expectedKind || expectedKind == .file else {
        return finish(request, state: .failed(.unreadableOriginal))
      }
      switch preview.kind {
      case .image, .pdf, .video, .file:
        if preview.thumbnailURL == nil,
          let thumbnailURL = await store.thumbnailURL(
            for: request.asset,
            size: CGSize(width: request.thumbnailPixelSize, height: request.thumbnailPixelSize))
        {
          preview = AssetPreview(
            kind: preview.kind,
            pixelWidth: preview.pixelWidth,
            pixelHeight: preview.pixelHeight,
            pageCount: preview.pageCount,
            thumbnailURL: thumbnailURL)
        }
      case .audio:
        break
      }
      if (preview.kind == .image || preview.kind == .pdf) && preview.thumbnailURL == nil {
        state = .failed(.unreadableOriginal)
      } else {
        state = .ready(preview)
      }
    } catch is CancellationError {
      state = .failed(.cancelled)
    } catch {
      state = .failed(.unreadableOriginal)
    }
    return finish(request, state: state)
  }

  public func load(
    visible: [MediaPreviewRequest],
    prefetch: [MediaPreviewRequest] = []
  ) async -> [MediaPreviewResult] {
    var results: [MediaPreviewResult] = []
    results.reserveCapacity(visible.count + min(prefetch.count, prefetchLimit))
    for request in visible + Array(prefetch.prefix(prefetchLimit)) {
      if let result = await load(request) { results.append(result) }
    }
    return results
  }

  private func finish(
    _ request: MediaPreviewRequest,
    state: MediaPreviewState
  ) -> MediaPreviewResult? {
    let key = RequestKey(blockID: request.blockID, assetID: request.asset.id)
    guard activeRequests[key] == request else { return nil }
    activeRequests.removeValue(forKey: key)
    return MediaPreviewResult(
      blockID: request.blockID,
      blockRevision: request.blockRevision,
      assetID: request.asset.id,
      state: state)
  }
}

public extension AssetStore {
  func player(for asset: Asset) throws -> AVPlayer {
    guard hasOriginal(for: asset) else { throw MediaAssetError.missingOriginal }
    guard mediaKind(for: asset) == .video || mediaKind(for: asset) == .audio else {
      throw MediaAssetError.unsupportedMedia
    }
    return AVPlayer(url: originalURL(for: asset))
  }

  func pdfDocument(for asset: Asset) throws -> PDFDocument {
    guard hasOriginal(for: asset) else { throw MediaAssetError.missingOriginal }
    guard mediaKind(for: asset) == .pdf else { throw MediaAssetError.unsupportedMedia }
    guard let document = PDFDocument(url: originalURL(for: asset)) else {
      throw MediaAssetError.unreadableMedia
    }
    return document
  }

  func quickLookItem(for asset: Asset) throws -> AssetQuickLookItem {
    guard hasOriginal(for: asset) else { throw MediaAssetError.missingOriginal }
    return AssetQuickLookItem(url: originalURL(for: asset), title: asset.originalFilename)
  }
}

public final class AssetQuickLookItem: NSObject, QLPreviewItem, @unchecked Sendable {
  public let previewItemURL: URL?
  public let previewItemTitle: String?

  public init(url: URL, title: String? = nil) {
    previewItemURL = url
    previewItemTitle = title
  }
}

#if canImport(AVKit) && canImport(AppKit) && canImport(SwiftUI)
public struct LocalMediaPlayerView: NSViewRepresentable {
  public let player: AVPlayer

  public init(player: AVPlayer) { self.player = player }

  public func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .inline
    view.player = player
    return view
  }

  public func updateNSView(_ nsView: AVPlayerView, context: Context) {
    if nsView.player !== player { nsView.player = player }
  }
}

public struct PDFDocumentView: NSViewRepresentable {
  public let document: PDFDocument

  public init(document: PDFDocument) { self.document = document }

  public func makeNSView(context: Context) -> PDFView {
    let view = PDFView()
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    view.document = document
    return view
  }

  public func updateNSView(_ nsView: PDFView, context: Context) {
    if nsView.document !== document { nsView.document = document }
  }
}

public struct QuickLookPreviewView: NSViewRepresentable {
  public let item: AssetQuickLookItem

  public init(item: AssetQuickLookItem) { self.item = item }

  public func makeNSView(context: Context) -> QLPreviewView {
    let view = QLPreviewView(frame: .zero, style: .normal)!
    view.previewItem = item
    return view
  }

  public func updateNSView(_ nsView: QLPreviewView, context: Context) {
    if nsView.previewItem?.previewItemURL != item.previewItemURL {
      nsView.previewItem = item
    }
  }
}
#endif
