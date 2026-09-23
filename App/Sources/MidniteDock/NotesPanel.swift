import SwiftUI
import DockCore

/// Panel notatek i zadań po prawej. Domyślnie notatka jest globalna; prawy przycisk → „Przypisz do kolekcji”
/// przypina ją do kolekcji (widać ją wtedy tylko przy tej kolekcji, a globalne zostają widoczne wszędzie).
struct NotesPanel: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.dockAccent) private var accent
    @State private var draft = ""

    var body: some View {
        let notes = store.visibleNotes
        VStack(spacing: 0) {
            HStack {
                Text(L("Notatki", "Notes")).font(.system(size: 12, weight: .semibold))
                Spacer()
                if NoteItem.canScope(store.config.category) {
                    Text(store.categoryTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(notes) { NoteRow(store: store, note: $0) }
                    if notes.isEmpty {
                        Text(L("Brak notatek. Dopisz poniżej — zostanie zapisana jako globalna albo dla wybranej kolekcji lub folderu.", "No notes yet. Add one below — it is saved as global, or for the selected collection or folder."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 6)
                    }
                }.padding(.horizontal, 6)
            }
            HStack(spacing: 6) {
                TextField(L("Nowa notatka…", "New note…"), text: $draft, axis: .vertical).textFieldStyle(.plain).font(.system(size: 12)).lineLimit(1...4)
                    .onSubmit { store.addNote(draft); draft = "" }
                Button { store.addNote(draft); draft = "" } label: { Image(systemName: "plus.circle.fill").foregroundStyle(draft.isEmpty ? Color.secondary : accent) }
                    .buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.08))).padding(8)
        }
        .frame(width: 210)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5) }
    }
}

private struct NoteRow: View {
    @ObservedObject var store: LibraryStore
    let note: NoteItem
    @State private var hover = false

    private var scopeTitle: String? { note.scope.flatMap { store.title(for: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 4) {
                Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 3)
                    .draggable(LibraryStore.notePayloadPrefix + note.id.uuidString) {
                        Text(note.text).font(.system(size: 12)).lineLimit(2).padding(6).frame(maxWidth: 180, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
                    }
                    .help(L("Przeciągnij na kolekcję, folder lub typ w lewym panelu", "Drag onto a collection, folder or type in the left sidebar"))
                TextField("", text: Binding(get: { note.text }, set: { t in store.updateNote(note.id) { $0.text = t } }), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 12))
                Menu {
                    Button(L("Globalna (wszędzie)", "Global (everywhere)")) { store.updateNote(note.id) { $0.scope = nil } }
                    ForEach(Array(store.noteScopeGroups.enumerated()), id: \.offset) { _, g in
                        Menu(g.title) {
                            ForEach(Array(g.choices.enumerated()), id: \.offset) { _, ch in
                                Button(ch.title) { store.updateNote(note.id) { $0.scope = ch.category } }
                            }
                        }
                    }
                } label: { Image(systemName: "folder.badge.plus").font(.system(size: 11)).foregroundStyle(.secondary) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(L("Przypisz do kolekcji lub folderu", "Assign to a collection or folder"))
                Button { store.removeNote(note.id) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).padding(.top, 2).help(L("Usuń notatkę", "Delete note"))
            }
            Text(scopeTitle.map { L("Przypisana do: \($0)", "Assigned to: \($0)") } ?? L("Globalna", "Global"))
                .font(.system(size: 9.5)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover ? 0.09 : 0.06)))
        .onHover { hover = $0 }
    }
}
