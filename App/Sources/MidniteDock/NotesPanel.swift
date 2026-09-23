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
                if store.selectedCollectionID != nil {
                    Text(store.categoryTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 6)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(notes) { NoteRow(store: store, note: $0) }
                    if notes.isEmpty {
                        Text(L("Brak notatek. Dopisz poniżej — zostanie zapisana jako globalna albo dla wybranej kolekcji.", "No notes yet. Add one below — it is saved as global, or for the selected collection."))
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
    @Environment(\.dockAccent) private var accent

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button { store.updateNote(note.id) { $0.done.toggle() } } label: {
                Image(systemName: note.done ? "checkmark.circle.fill" : "circle").foregroundStyle(note.done ? accent : Color.secondary).font(.system(size: 13))
            }.buttonStyle(.plain).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                TextField("", text: Binding(get: { note.text }, set: { t in store.updateNote(note.id) { $0.text = t } }), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 12)).strikethrough(note.done).foregroundStyle(note.done ? .secondary : .primary)
                if let cid = note.collectionID, let c = store.org.collections.first(where: { $0.id == cid }) {
                    Label(c.name, systemImage: "rectangle.stack").font(.system(size: 9.5)).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                }
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        .contextMenu {
            Menu(L("Przypisz do kolekcji", "Assign to collection")) {
                Button(L("Globalna (wszędzie)", "Global (everywhere)")) { store.updateNote(note.id) { $0.collectionID = nil } }
                Divider()
                ForEach(store.org.collections) { c in Button(c.name) { store.updateNote(note.id) { $0.collectionID = c.id } } }
            }
            Button(note.done ? L("Oznacz jako do zrobienia", "Mark as to-do") : L("Oznacz jako zrobione", "Mark as done")) { store.updateNote(note.id) { $0.done.toggle() } }
            Divider()
            Button(L("Usuń", "Delete"), role: .destructive) { store.removeNote(note.id) }
        }
    }
}
