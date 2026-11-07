#!/usr/bin/env python3
"""Generate synthetic fixtures with pinned PUBLIC historical writers, never an App.
Requires full repository history, macOS and Swift. CI consumes frozen fixtures and
hashes instead of downloading or rebuilding historical code. Regeneration can change
legacy-generated UUIDs; inspect the fixture/provenance diff before committing it.
"""
import hashlib
import json
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'Tests/Fixtures/HistoricalProfiles'
COMMITS = {'v01': '4b8a6b7fa467da5b2b516168c18eb3017e6c1525',
           'v02': '369e65b21cfc8176db04dd69a0c5488f881e195e',
           'v03': '171bba9efb18829c480d75aa0945ef562801e0cb'}
SOURCES = {}


def source(version, name):
    data = subprocess.check_output(['git', 'show', f'{COMMITS[version]}:{name}'], cwd=ROOT)
    SOURCES[f'{COMMITS[version]}:{name}'] = hashlib.sha256(data).hexdigest()
    return data.decode()


def compile_at(folder, sources, driver):
    folder.mkdir()
    for name, text in dict(sources, Driver=driver).items():
        (folder / (name + '.swift')).write_text(text)
    binary = folder / 'probe'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    '-module-cache-path', str(folder / 'module-cache'),
                    '-target', platform.machine() + '-apple-macosx14.0',
                    *map(str, sorted(folder.glob('*.swift'))), '-o', str(binary)], check=True)
    return binary


NOTES = '''
let notes = [StickyNote(id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                       text: "历史合成便签\\nsecond line", color: 2,
                       frame: CGRect(x: -240, y: 80, width: 310, height: 245), visible: true),
             StickyNote(id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
                       text: "hidden synthetic note", color: 1,
                       frame: CGRect(x: 30, y: -100, width: 260, height: 220), visible: false)]
'''

with tempfile.TemporaryDirectory(prefix='istk historical writers ') as temporary:
    temp = Path(temporary)
    profiles = temp / 'profiles'
    profiles.mkdir()
    for version in ('v01', 'v02'):
        directory = profiles / version
        directory.mkdir()
        if version == 'v01':
            original = source(version, 'Stickies/NoteStore.swift')
            # Exact original Codable model only; no singleton, window or App code.
            model = original[original.index('struct StickyNote:'):original.index('@MainActor')]
            model = 'import Foundation\nimport CoreGraphics\n' + model
            encode = 'JSONEncoder().encode(notes)'
            decode = 'JSONDecoder().decode([StickyNote].self, from: bytes)'
        else:
            model = source(version, 'Stickies/NoteModel.swift')
            encode = 'NotePersistence.encode(notes)'
            decode = 'NotePersistence.decode(bytes).notes'
        driver = '''import Foundation
import CoreGraphics
@main struct Driver { static func main() throws {
''' + NOTES + f'''
let bytes = try {encode}
let restored = try {decode}
precondition(restored.map(\\.text) == notes.map(\\.text))
try bytes.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}} }}
'''
        binary = compile_at(temp / (version + '-writer'), {'Model': model}, driver)
        subprocess.run([str(binary), str(directory / 'notes.json')], check=True)
        (directory / 'preferences.json').write_text('{"keepOnTop":true}\n')
    names = ('StickyNote', 'LosslessJSON', 'CompatibleNoteFile', 'LocalNoteTrash',
             'SerializedNoteCommands', 'SegmentedCommandLedger')
    sources = {name: source('v03', f'Stickies/{name}.swift') for name in names}
    driver = '''import Foundation
import Darwin
@main struct Driver { static func main() throws {
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let mode = CommandLine.arguments[2]
let fd = open(directory.appendingPathComponent("notes.lock").path, O_CREAT | O_RDWR, 0o600)
precondition(fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0)
defer { close(fd) }
let url = directory.appendingPathComponent("notes.json")
if mode == "recover" {
    try SerializedNoteCommands.recover(in: directory)
    let notes = try CompatibleNoteFile.decode(Data(contentsOf: url))
    precondition(notes[0].text == "pending historical command")
    return
}
let notes = try CompatibleNoteFile.decode(Data(contentsOf: url))
let request = SerializedNoteCommands.Request(
    id: UUID(uuidString: mode == "journal" ? "44444444-4444-4444-8444-444444444444" : "33333333-3333-4333-8333-333333333333")!,
    command: "edit", ids: [notes[0].id], text: mode == "journal" ? "pending historical command" : notes[0].text)
if mode == "journal" {
    do {
        _ = try SerializedNoteCommands.execute(request, notes: notes, trash: LocalNoteTrash(), in: directory) {
            if $0 == .prepared { throw CocoaError(.fileWriteOutOfSpace) }
        }
        fatalError("Expected interruption")
    } catch {
        precondition(FileManager.default.fileExists(atPath: directory.appendingPathComponent("command-journal.json").path))
    }
} else {
    _ = try SerializedNoteCommands.execute(request, notes: notes, trash: LocalNoteTrash(), in: directory)
    try SegmentedCommandLedger.migrate(in: directory)
    try SegmentedCommandLedger.validate(Data(contentsOf: url), in: directory)
    precondition(try CompatibleNoteFile.decode(Data(contentsOf: url)).count == 2)
}
} }
'''.replace('    precondition(try CompatibleNoteFile.decode(Data(contentsOf: url)).count == 2)',
             '    let reread = try CompatibleNoteFile.decode(Data(contentsOf: url))\n    precondition(reread.count == 2)')
    binary = compile_at(temp / 'v03-writer', sources, driver)
    shutil.copytree(profiles / 'v02', profiles / 'v03')
    subprocess.run([str(binary), str(profiles / 'v03'), 'migrate'], check=True)
    shutil.copytree(profiles / 'v03', profiles / 'v03-journal')
    subprocess.run([str(binary), str(profiles / 'v03-journal'), 'journal'], check=True)
    shutil.copytree(profiles / 'v03-journal', temp / 'recover-check')
    subprocess.run([str(binary), str(temp / 'recover-check'), 'recover'], check=True)
    for lock in profiles.rglob('notes.lock'):
        lock.unlink()
    files = {p.relative_to(profiles).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in sorted(profiles.rglob('*')) if p.is_file()}
    provenance = dict(description='Synthetic payloads emitted/read by pinned historical code; no user data. '
                     'v01/v02/v03 denote format families, not assertions of shipped marketing versions.',
                     commits=COMMITS, sourceSHA256=SOURCES, fixtureSHA256=files,
                     journal='Historical transaction interrupted after prepared; recovery verified on a separate copy.')
    OUT.mkdir(parents=True, exist_ok=True)
    for child in profiles.iterdir():
        destination = OUT / child.name
        if destination.exists():
            raise SystemExit('Refusing to replace fixtures; use a fresh output directory')
        shutil.copytree(child, destination)
    (OUT / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
print('Generated public-history fixtures and verified old writer/read/recovery paths')
