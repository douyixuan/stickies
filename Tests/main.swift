import Foundation

testLayoutEngine()
testNoteFile()
testPreferencesMigration()
testNoteStoreContent()
testTrash()
testLayout()
testArrangeKeepsFoldedHeights()
testReadOnlyProfiles()
try testReadOnlyWindowRecovery()

Scratch.cleanUp()
Check.summary()
