//
//  MusicPicker.swift
//  AudioTest
//
//  SwiftUI wrapper around MPMediaPickerController — the native Apple Music /
//  library song picker.
//

import SwiftUI
import MediaPlayer

struct MusicPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onPick: (MPMediaItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onPick: onPick)
    }

    func makeUIViewController(context: Context) -> MPMediaPickerController {
        let picker = MPMediaPickerController(mediaTypes: .music)
        picker.allowsPickingMultipleItems = false
        picker.showsCloudItems = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: MPMediaPickerController, context: Context) {}

    final class Coordinator: NSObject, MPMediaPickerControllerDelegate {
        private var isPresented: Binding<Bool>
        private let onPick: (MPMediaItem) -> Void

        init(isPresented: Binding<Bool>, onPick: @escaping (MPMediaItem) -> Void) {
            self.isPresented = isPresented
            self.onPick = onPick
        }

        func mediaPicker(_ mediaPicker: MPMediaPickerController,
                         didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
            if let item = mediaItemCollection.items.first {
                onPick(item)
            }
            isPresented.wrappedValue = false
        }

        func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
            isPresented.wrappedValue = false
        }
    }
}
