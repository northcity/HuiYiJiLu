//
//  RecordingToolbar.swift
//  Huiyijilu
//
//  录音页底部工具栏 — 打点 / 添加笔记 / 拍照

import SwiftUI
import PhotosUI

/// 录音页底部工具栏组件
struct RecordingToolbar: View {
    let currentTime: TimeInterval
    let onBookmark: (RecordingBookmark) -> Void

    @State private var showNoteInput = false
    @State private var noteText = ""
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showBookmarkLabel = false
    @State private var bookmarkLabel = ""

    // 打点反馈
    @State private var justBookmarked = false

    var body: some View {
        HStack(spacing: 0) {
            // 🚩 打点
            Button {
                addBookmark()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: justBookmarked ? "flag.fill" : "flag")
                        .font(.system(size: 20))
                        .foregroundStyle(justBookmarked ? .orange : .primary)
                    Text("打点")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    showBookmarkLabel = true
                }
            )

            // 📝 笔记
            Button {
                showNoteInput = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.system(size: 20))
                    Text("添加笔记")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            // 📷 拍照
            Menu {
                Button {
                    showCamera = true
                } label: {
                    Label("拍照", systemImage: "camera")
                }
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "camera")
                        .font(.system(size: 20))
                    Text("拍照")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)

        // 笔记输入弹窗
        .alert("添加笔记", isPresented: $showNoteInput) {
            TextField("输入笔记内容", text: $noteText)
            Button("取消", role: .cancel) { noteText = "" }
            Button("添加") {
                if !noteText.isEmpty {
                    let bookmark = RecordingBookmark(
                        timestamp: currentTime,
                        label: noteText,
                        type: .note
                    )
                    onBookmark(bookmark)
                    noteText = ""
                }
            }
        }

        // 打点标签输入弹窗
        .alert("打点标签", isPresented: $showBookmarkLabel) {
            TextField("输入标签（可选）", text: $bookmarkLabel)
            Button("取消", role: .cancel) { bookmarkLabel = "" }
            Button("添加") {
                let bookmark = RecordingBookmark(
                    timestamp: currentTime,
                    label: bookmarkLabel,
                    type: .flag
                )
                onBookmark(bookmark)
                bookmarkLabel = ""
            }
        }

        // 相册选择
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, item in
            if let item = item {
                handlePhotoPick(item: item)
            }
        }

        // 相机
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { image in
                if let image = image {
                    savePhotoBookmark(image: image)
                }
            }
        }
    }

    // MARK: - Actions

    private func addBookmark() {
        let bookmark = RecordingBookmark(
            timestamp: currentTime,
            label: "",
            type: .flag
        )
        onBookmark(bookmark)

        // 视觉反馈
        withAnimation(.easeInOut(duration: 0.2)) { justBookmarked = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation { justBookmarked = false }
        }
    }

    private func handlePhotoPick(item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            savePhotoBookmark(image: image)
        }
    }

    private func savePhotoBookmark(image: UIImage) {
        // 保存照片到 Documents/MeetingPhotos/
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let photosDir = docs.appendingPathComponent("MeetingPhotos")
        try? FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

        let fileName = "photo_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
        let fileURL = photosDir.appendingPathComponent(fileName)

        if let jpegData = image.jpegData(compressionQuality: 0.8) {
            try? jpegData.write(to: fileURL)

            let bookmark = RecordingBookmark(
                timestamp: currentTime,
                label: "",
                type: .photo,
                photoFileName: fileName
            )
            onBookmark(bookmark)
        }
    }
}

// MARK: - Simple Camera View (UIImagePickerController wrapper)

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onCapture(image)
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
            picker.dismiss(animated: true)
        }
    }
}
