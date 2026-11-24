using System;
using System.Collections.Generic;
using System.Linq;

namespace ValheimAdminMenu
{
    internal sealed class WorldEditHistory
    {
        private const int Capacity = 24;
        private readonly Plugin app;
        private readonly List<Entry> applied = new List<Entry>();
        private readonly Stack<Entry> reverted = new Stack<Entry>();

        internal sealed class Change
        {
            private readonly Action checkUndo, undo, checkRedo, redo;

            internal Change(Action checkUndo, Action undo, Action checkRedo, Action redo)
            {
                this.checkUndo = checkUndo;
                this.undo = undo;
                this.checkRedo = checkRedo;
                this.redo = redo;
            }

            internal void Undo() { checkUndo(); undo(); }
            internal void Redo() { checkRedo(); redo(); }

            internal static Change Combine(Change first, Change second)
            {
                if (first == null) return second;
                if (second == null) return first;
                return new Change(
                    () => { second.checkUndo(); first.checkUndo(); },
                    () => { second.undo(); first.undo(); },
                    () => { first.checkRedo(); second.checkRedo(); },
                    () => { first.redo(); second.redo(); });
            }
        }

        private sealed class Entry
        {
            internal string Label;
            internal Change Change;
        }

        internal WorldEditHistory(Plugin app) { this.app = app; }
        internal int UndoCount => applied.Count;
        internal int RedoCount => reverted.Count;
        internal IEnumerable<string> RecentLabels => applied.AsEnumerable().Reverse().Take(5).Select(entry => entry.Label);

        internal string LabelAt(int position)
        {
            if (position == 0) return "Before retained edits";
            return position <= applied.Count ? applied[position - 1].Label : reverted.ElementAt(position - applied.Count - 1).Label;
        }

        internal void GoTo(int position)
        {
            if (position < 0 || position > UndoCount + RedoCount)
                throw new InvalidOperationException("That history position is no longer available.");
            while (UndoCount > position) Undo();
            while (UndoCount < position) Redo();
        }

        internal void Record(string label, Change change)
        {
            if (change == null) return;
            reverted.Clear();
            applied.Add(new Entry { Label = label, Change = change });
            if (applied.Count > Capacity) applied.RemoveAt(0);
        }

        internal void Undo()
        {
            app.RequireWorld();
            if (applied.Count == 0) throw new InvalidOperationException("There is no world edit to undo.");
            var entry = applied[applied.Count - 1];
            entry.Change.Undo();
            applied.RemoveAt(applied.Count - 1);
            reverted.Push(entry);
            app.Report("Undid " + entry.Label + ".");
        }

        internal void Redo()
        {
            app.RequireWorld();
            if (reverted.Count == 0) throw new InvalidOperationException("There is no world edit to redo.");
            var entry = reverted.Peek();
            entry.Change.Redo();
            reverted.Pop();
            applied.Add(entry);
            app.Report("Redid " + entry.Label + ".");
        }

        internal void Clear()
        {
            applied.Clear();
            reverted.Clear();
        }
    }
}
