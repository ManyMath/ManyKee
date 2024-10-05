import 'package:ffi/ffi.dart';
import 'database.dart';
import 'error.dart';
import 'ffi_helpers.dart';

/// An entry (credential) within a KeePass database.
///
/// Entries are accessed by UUID through the parent database.
class Entry {
 final Database _db;

 /// The UUID of this entry.
 final String uuid;

 Entry(this._db, this.uuid);

 String? getField(String fieldName) {
 final uuidPtr = toNativeString(uuid);
 final fieldPtr = toNativeString(fieldName);
 try {
 final valuePtr =
 bindings.kpxc_entry_get_field(_db.handle, uuidPtr, fieldPtr);
 return readAndFreeString(valuePtr);
 } finally {
 malloc.free(uuidPtr);
 malloc.free(fieldPtr);
 }
 }

 void setField(String fieldName, String value, {bool protected = false}) {
 final uuidPtr = toNativeString(uuid);
 final fieldPtr = toNativeString(fieldName);
 final valuePtr = toNativeString(value);
 try {
 KeePassError.checkResult(
 bindings.kpxc_entry_set_field(
 _db.handle,
 uuidPtr,
 fieldPtr,
 valuePtr,
 protected ? 1 : 0,
 ),
 'Failed to set field $fieldName',
 );
 } finally {
 malloc.free(uuidPtr);
 malloc.free(fieldPtr);
 malloc.free(valuePtr);
 }
 }

 String? get title => getField('Title');
 String? get userName => getField('UserName');
 String? get password => getField('Password');
 String? get url => getField('URL');
 String? get notes => getField('Notes');

 void delete({bool permanent = false}) {
 final uuidPtr = toNativeString(uuid);
 try {
 KeePassError.checkResult(
 bindings.kpxc_entry_delete(_db.handle, uuidPtr, permanent ? 1 : 0),
 'Failed to delete entry',
 );
 } finally {
 malloc.free(uuidPtr);
 }
 }

 @override
 String toString() => 'Entry($uuid, title: $title)';
}
