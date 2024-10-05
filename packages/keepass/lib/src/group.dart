import 'package:ffi/ffi.dart';
import 'database.dart';
import 'entry.dart';
import 'error.dart';
import 'ffi_helpers.dart';

/// A group (folder) within a KeePass database.
///
/// Groups are accessed by UUID through the parent database.
/// They do not own native memory and do not need finalization.
class Group {
 final Database _db;

 /// The UUID of this group.
 final String uuid;

 Group(this._db, this.uuid);

 String get name {
 final uuidPtr = toNativeString(uuid);
 try {
 final namePtr = bindings.kpxc_group_get_name(_db.handle, uuidPtr);
 return readAndFreeStringOrThrow(namePtr, 'Failed to get group name');
 } finally {
 malloc.free(uuidPtr);
 }
 }

 set name(String value) {
 final uuidPtr = toNativeString(uuid);
 final namePtr = toNativeString(value);
 try {
 KeePassError.checkResult(
 bindings.kpxc_group_set_name(_db.handle, uuidPtr, namePtr),
 'Failed to set group name',
 );
 } finally {
 malloc.free(uuidPtr);
 malloc.free(namePtr);
 }
 }

 int get entryCount {
 final uuidPtr = toNativeString(uuid);
 try {
 final count = bindings.kpxc_group_entries_count(_db.handle, uuidPtr);
 if (count < 0) {
 throw KeePassError.fromLastError('Failed to get entry count');
 }
 return count;
 } finally {
 malloc.free(uuidPtr);
 }
 }

 int get groupCount {
 final uuidPtr = toNativeString(uuid);
 try {
 final count = bindings.kpxc_group_groups_count(_db.handle, uuidPtr);
 if (count < 0) {
 throw KeePassError.fromLastError('Failed to get group count');
 }
 return count;
 } finally {
 malloc.free(uuidPtr);
 }
 }

 Entry entryAt(int index) {
 final uuidPtr = toNativeString(uuid);
 try {
 final entryUuid = readAndFreeStringOrThrow(
 bindings.kpxc_entry_get_uuid(_db.handle, uuidPtr, index),
 'Failed to get entry at index $index',
 );
 return Entry(_db, entryUuid);
 } finally {
 malloc.free(uuidPtr);
 }
 }

 List<Entry> get entries {
 final count = entryCount;
 return List.generate(count, entryAt);
 }

 Group groupAt(int index) {
 final uuidPtr = toNativeString(uuid);
 try {
 final groupUuid = readAndFreeStringOrThrow(
 bindings.kpxc_group_get_uuid(_db.handle, uuidPtr, index),
 'Failed to get group at index $index',
 );
 return Group(_db, groupUuid);
 } finally {
 malloc.free(uuidPtr);
 }
 }

 List<Group> get groups {
 final count = groupCount;
 return List.generate(count, groupAt);
 }

 Entry createEntry() {
 final uuidPtr = toNativeString(uuid);
 try {
 final entryUuid = readAndFreeStringOrThrow(
 bindings.kpxc_entry_create(_db.handle, uuidPtr),
 'Failed to create entry',
 );
 return Entry(_db, entryUuid);
 } finally {
 malloc.free(uuidPtr);
 }
 }

 Group createGroup(String groupName) {
 final uuidPtr = toNativeString(uuid);
 final namePtr = toNativeString(groupName);
 try {
 final groupUuid = readAndFreeStringOrThrow(
 bindings.kpxc_group_create(_db.handle, uuidPtr, namePtr),
 'Failed to create group',
 );
 return Group(_db, groupUuid);
 } finally {
 malloc.free(uuidPtr);
 malloc.free(namePtr);
 }
 }

 void delete({bool permanent = false}) {
 final uuidPtr = toNativeString(uuid);
 try {
 KeePassError.checkResult(
 bindings.kpxc_group_delete(_db.handle, uuidPtr, permanent ? 1 : 0),
 'Failed to delete group',
 );
 } finally {
 malloc.free(uuidPtr);
 }
 }

 @override
 String toString() => 'Group($uuid)';
}
