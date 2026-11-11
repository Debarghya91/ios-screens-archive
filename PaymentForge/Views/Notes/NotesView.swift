// NotesView.swift
// PaymentForge iOS - Learner notes and collections.
// White cards on the soft blue-grey background, royal blue primary,
// matching the mockup's general language. Notes are the learner's own
// text about real lessons, stored locally. Search covers note text,
// lesson title and collection. The composer lives here, not in
// LessonView, and picks a lesson from completed lessons.
// No em dashes in any user-facing text.

import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @ObservedObject private var notesStore = NotesStore.shared

    @State private var searchText = ""
    @State private var selectedCollection: String? = nil
    @State private var showComposer = false
    @State private var showNewCollection = false
    @State private var newCollectionName = ""

    private var filteredNotes: [NotesStore.Note] {
        let searched = notesStore.searchNotes(query: searchText)
        guard let selectedCollection else { return searched }
        return searched.filter { $0.collection == selectedCollection }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PFSpacing.lg) {
                searchField
                collectionsRow
                notesList
            }
            .padding(PFSpacing.lg)
        }
        .background(Color.pfBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: PFSpacing.xl)
        }
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
        .alert("New collection", isPresented: $showNewCollection) {
            TextField("Collection name", text: $newCollectionName)
            Button("Create") {
                if notesStore.createCollection(newCollectionName) {
                    selectedCollection = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                newCollectionName = ""
            }
            Button("Cancel", role: .cancel) {
                newCollectionName = ""
            }
        } message: {
            Text("Name a new collection for your notes.")
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

    // MARK: - Collections

    private var collectionsRow: some View {
        VStack(alignment: .leading, spacing: PFSpacing.sm) {
            Text("Collections")
                .font(.pfCaptionBold)
                .foregroundColor(.pfSecondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PFSpacing.sm) {
                    PFChip(text: "All notes", isSelected: selectedCollection == nil) {
                        selectedCollection = nil
                    }
                    ForEach(notesStore.collections(), id: \.self) { collection in
                        PFChip(text: collection, isSelected: selectedCollection == collection) {
                            selectedCollection = collection
                        }
                    }
                    PFChip(text: "+ New collection", isSelected: false) {
                        showNewCollection = true
                    }
                }
            }
        }
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
                            : "Try a different search or collection.")
                            .font(.pfBody)
                            .foregroundColor(.pfSecondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        PFSecondaryButton(title: "Write a note") {
                            showComposer = true
                        }
                    }
                }
            } else {
                ForEach(filteredNotes) { note in
                    NavigationLink(destination: NoteDetailView(note: note)) {
                        NoteRow(note: note)
                    }
                    .buttonStyle(PFCardButtonStyle())
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
                    HStack(spacing: PFSpacing.sm) {
                        PFPill(text: note.collection)
                        Text(Self.dateFormatter.string(from: note.createdAt))
                            .font(.pfCaption)
                            .foregroundColor(.pfSecondaryText)
                    }
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
                            PFPill(text: note.collection)
                            Spacer()
                            Text(Self.dateFormatter.string(from: note.createdAt))
                                .font(.pfCaption)
                                .foregroundColor(.pfSecondaryText)
                        }
                        Text(note.text)
                            .font(.pfBody)
                            .foregroundColor(.pfNavy)
                            .fixedSize(horizontal: false, vertical: true)
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

/// The note composer: pick a completed lesson, a collection, and write
/// the note. Lessons are real completed lessons from ProgressStore.
private struct NoteComposerSheet: View {
    @EnvironmentObject private var contentService: ContentService
    @EnvironmentObject private var progressStore: ProgressStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notesStore = NotesStore.shared

    @State private var selectedLessonID: String = ""
    @State private var selectedCollection: String = NotesStore.defaultCollections[0]
    @State private var newCollectionName = ""
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
                        Text("Collection")
                            .font(.pfCaptionBold)
                            .foregroundColor(.pfSecondaryText)
                        Picker("Collection", selection: $selectedCollection) {
                            ForEach(notesStore.collections(), id: \.self) { collection in
                                Text(collection).tag(collection)
                            }
                        }
                        .pickerStyle(.segmented)
                        HStack(spacing: PFSpacing.sm) {
                            TextField("Or a new collection name", text: $newCollectionName)
                                .font(.pfBody)
                                .padding(PFSpacing.sm)
                                .background(Color.pfCard)
                                .cornerRadius(PFSpacing.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PFSpacing.cornerRadius)
                                        .stroke(Color.pfBorder, lineWidth: 1)
                                )
                            Button("Add") {
                                if notesStore.createCollection(newCollectionName) {
                                    selectedCollection = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                                newCollectionName = ""
                            }
                            .font(.pfBody.weight(.semibold))
                            .foregroundColor(.pfRoyal)
                            .disabled(newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                            highlightedText: highlighted.isEmpty ? nil : highlighted,
                            collection: selectedCollection
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
