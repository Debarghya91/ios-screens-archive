// NotesView.swift
// PaymentForge iOS - Learner notes, one flat list.
// White cards on the soft blue-grey background, royal blue primary,
// matching the mockup's general language. Notes are the learner's own
// text about real lessons, stored locally. Search covers note text
// and lesson title. The composer lives here, not in LessonView, and
// picks a lesson from completed lessons.
// No em dashes in any user-facing text.

import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @ObservedObject private var notesStore = NotesStore.shared

    @State private var searchText = ""
    @State private var showComposer = false
    @State private var visibleCount: Int = 20

    private static let pageSize = 20

    private var filteredNotes: [NotesStore.Note] {
        notesStore.searchNotes(query: searchText)
    }

    private var visibleNotes: [NotesStore.Note] {
        Array(filteredNotes.prefix(visibleCount))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                deviceOnlyLabel
                searchField
                notesList
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("My Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showComposer = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New note")
            }
        }
        .sheet(isPresented: $showComposer) {
            NoteComposerSheet()
        }
        .onChange(of: searchText) { _, _ in
            visibleCount = Self.pageSize
        }
    }

    // MARK: - Device-only label

    /// Notes are stored only on this device and never sync. The
    /// label stays visible above the list so the learner is never
    /// left assuming notes follow their account.
    private var deviceOnlyLabel: some View {
        HStack(spacing: PFSpacing.sm) {
            Image(systemName: "iphone")
                .foregroundColor(.pfSecondaryText)
            Text("Notes are stored only on this device. They do not sync to other devices.")
                .font(.pfCaption)
                .foregroundColor(.pfSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: PFSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.pfSecondaryText)
            TextField("Search notes", text: $searchText)
                .font(.pfBody)
                .foregroundColor(.pfNavy)
        }
        .padding(PFSpacing.md)
        .background(Color.pfCard)
        .cornerRadius(PFSpacing.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                .stroke(Color.pfBorder, lineWidth: 1)
        )
    }

    // MARK: - List

    private var notesList: some View {
        VStack(alignment: .leading, spacing: PFSpacing.md) {
            if filteredNotes.isEmpty {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text(notesStore.allNotes().isEmpty ? "No notes yet" : "No notes match")
                            .font(.pfCardTitle)
                            .foregroundColor(.pfNavy)
                        Text(notesStore.allNotes().isEmpty
                            ? "Write your first note about a lesson you completed. Notes stay on this device."
                            : "Try a different search.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        PFSecondaryButton(title: "Write a note") {
                            showComposer = true
                        }
                    }
                }
            } else {
                ForEach(visibleNotes) { note in
                    NavigationLink(destination: NoteDetailView(note: note)) {
                        NoteRow(note: note)
                    }
                    .buttonStyle(PFCardButtonStyle())
                }
                if filteredNotes.count > visibleNotes.count {
                    Text("Showing \(visibleNotes.count) of \(filteredNotes.count) notes")
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PFSecondaryButton(title: "Load more notes") {
                        visibleCount += Self.pageSize
                    }
                }
            }
        }
    }
}

// MARK: - Note row

private struct NoteRow: View {
    let note: NotesStore.Note

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        PFCard {
            HStack(alignment: .top, spacing: PFSpacing.md) {
                PFIconTile(systemImage: "note.text", size: 44)
                VStack(alignment: .leading, spacing: PFSpacing.xs) {
                    Text(note.text)
                        .font(.pfCardTitle)
                        .foregroundColor(.pfNavy)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(note.lessonTitle)
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                        .lineLimit(1)
                    Text(Self.dateFormatter.string(from: note.createdAt))
                        .font(.pfCaption)
                        .foregroundColor(.pfSecondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.pfSecondaryText)
                    .padding(.top, PFSpacing.xs)
            }
        }
    }
}

// MARK: - Note detail

struct NoteDetailView: View {
    @ObservedObject private var notesStore = NotesStore.shared
    @Environment(\.dismiss) private var dismiss
    let note: NotesStore.Note

    @State private var showDeleteConfirmation = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                PFCard {
                    VStack(alignment: .leading, spacing: PFSpacing.md) {
                        HStack(spacing: PFSpacing.sm) {
                            Spacer()
                            Text(Self.dateFormatter.string(from: note.createdAt))
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                        }
                        PFBodyText(text: note.text)
                        if let highlighted = note.highlightedText, !highlighted.isEmpty {
                            VStack(alignment: .leading, spacing: PFSpacing.xs) {
                                Text("Highlighted from the lesson")
                                    .font(.pfCaptionBold)
                                    .foregroundColor(.pfSecondaryText)
                                Text(highlighted)
                                    .font(.pfBody)
                                    .foregroundColor(.pfNavy)
                                    .italic()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text("Lesson: \(note.lessonTitle)")
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete note")
                        .font(.pfBody.weight(.semibold))
                        .foregroundColor(.pfError)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .pfTabBarClearance()
        .navigationTitle("Note")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this note?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete note", role: .destructive) {
                notesStore.deleteNote(id: note.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
    }
}

// MARK: - Note composer

/// The note composer: pick a completed lesson and write the note.
/// Lessons are real completed lessons from ProgressStore.
private struct NoteComposerSheet: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notesStore = NotesStore.shared

    @State private var selectedLessonID: String = ""
    @State private var noteText = ""
    @State private var highlightedText = ""

    private var completedLessons: [SearchEntry] {
        contentService.allLessons.filter { progressStore.isLessonComplete($0.id) }
    }

    private var selectedLesson: SearchEntry? {
        completedLessons.first { $0.id == selectedLessonID }
    }

    private var canSave: Bool {
        selectedLesson != nil && !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PFSpacing.lg) {
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Lesson")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                        if completedLessons.isEmpty {
                            Text("No completed lessons yet. Complete a lesson first, then write a note about it.")
                                .font(.pfBody)
                                .foregroundColor(.pfSecondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Picker("Lesson", selection: $selectedLessonID) {
                                Text("Choose a lesson").tag("")
                                ForEach(completedLessons) { lesson in
                                    Text(lesson.title).tag(lesson.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(PFSpacing.sm)
                            .background(Color.pfCard)
                            .cornerRadius(PFSpacing.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                                    .stroke(Color.pfBorder, lineWidth: 1)
                            )
                        }
                    }
                    VStack(alignment: .leading, spacing: PFSpacing.sm) {
                        Text("Note")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                        TextEditor(text: $noteText)
                            .font(.pfBody)
                            .frame(minHeight: 140)
                            .padding(PFSpacing.sm)
                            .background(Color.pfCard)
                            .cornerRadius(PFSpacing.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                                    .stroke(Color.pfBorder, lineWidth: 1)
                            )
                        Text("Highlighted text from the lesson (optional)")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                        TextField("Paste a line from the lesson", text: $highlightedText)
                            .font(.pfBody)
                            .padding(PFSpacing.sm)
                            .background(Color.pfCard)
                            .cornerRadius(PFSpacing.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                                    .stroke(Color.pfBorder, lineWidth: 1)
                            )
                    }
                    PFPrimaryButton(title: "Save note") {
                        guard let lesson = selectedLesson else { return }
                        let highlighted = highlightedText.trimmingCharacters(in: .whitespacesAndNewlines)
                        notesStore.addNote(
                            lessonID: lesson.id,
                            lessonTitle: lesson.title,
                            text: noteText,
                            highlightedText: highlighted.isEmpty ? nil : highlighted
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
                }
                .padding(PFSpacing.lg)
            }
            .background(Color.pfBackground)
            .navigationTitle("New note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
