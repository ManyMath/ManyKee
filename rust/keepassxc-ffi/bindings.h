#ifndef KEEPASSXC_FFI_H
#define KEEPASSXC_FFI_H

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#define KPXC_OK 0

#define KPXC_ERR_IO -1

#define KPXC_ERR_OPEN -2

#define KPXC_ERR_SAVE -3

#define KPXC_ERR_NOT_FOUND -4

#define KPXC_ERR_MERGE -5

#define KPXC_ERR_YUBIKEY -6

#define KPXC_ERR_NULL_PTR -7

#define KPXC_ERR_INVALID_UTF8 -8

/**
 * Return a pointer to the last error message string (UTF-8, null-terminated).
 *
 * The returned pointer is valid until the next FFI call on the same thread.
 * Returns null if no error has occurred.
 */
 const char *kpxc_last_error(void) ;

/**
 * Free a string that was returned by an FFI function.
 *
 * The caller must pass only pointers that were returned by kpxc_* functions
 * (e.g., `kpxc_entry_get_field`, `kpxc_database_merge`).
 * Passing null is a no-op.
 */
 void kpxc_string_free(char *ptr) ;

/**
 * Open a KDBX database with a password.
 *
 * Returns a heap-allocated `KpxcDatabase` handle, or null on error.
 * The caller must free the handle with `kpxc_database_free`.
 */
 struct KpxcDatabase *kpxc_database_open(const char *path, const char *password) ;

/**
 * Open a KDBX database with a password and key file.
 *
 * Returns a heap-allocated `KpxcDatabase` handle, or null on error.
 * The caller must free the handle with `kpxc_database_free`.
 */

struct KpxcDatabase *kpxc_database_open_with_keyfile(const char *path,
                                                     const char *password,
                                                     const char *keyfile_path)
;

/**
 * Save a database to a file path with a password.
 *
 * Returns `KPXC_OK` on success, negative error code on failure.
 */
 int kpxc_database_save(struct KpxcDatabase *db, const char *path, const char *password) ;

/**
 * Free a database handle.
 *
 * Passing null is a no-op.
 */
 void kpxc_database_free(struct KpxcDatabase *db) ;

/**
 * Return the UUID string of the root group.
 *
 * Returns a heap-allocated string (caller frees with `kpxc_string_free`),
 * or null on error.
 */
 char *kpxc_database_root_uuid(struct KpxcDatabase *db) ;

/**
 * Get a field value from an entry identified by UUID.
 *
 * Returns a heap-allocated string (caller frees with `kpxc_string_free`),
 * or null if the entry/field is not found.
 */

char *kpxc_entry_get_field(struct KpxcDatabase *db,
                           const char *entry_uuid,
                           const char *field_name)
;

/**
 * Set a field value on an entry identified by UUID (with history tracking).
 *
 * `protected`: 1 for protected (e.g., Password), 0 for unprotected.
 * Returns `KPXC_OK` on success.
 */

int kpxc_entry_set_field(struct KpxcDatabase *db,
                         const char *entry_uuid,
                         const char *field_name,
                         const char *value,
                         int protected_)
;

/**
 * Get the UUID of an entry at the given index within a group.
 *
 * Returns a heap-allocated UUID string (caller frees with `kpxc_string_free`),
 * or null on error.
 */
 char *kpxc_entry_get_uuid(struct KpxcDatabase *db, const char *group_uuid, uintptr_t index) ;

/**
 * Create a new entry in the specified group.
 *
 * Returns the new entry's UUID string (caller frees with `kpxc_string_free`),
 * or null on error.
 */
 char *kpxc_entry_create(struct KpxcDatabase *db, const char *group_uuid) ;

/**
 * Delete an entry by UUID.
 *
 * If `permanent` is 0, soft-deletes (moves to recycle bin).
 * If `permanent` is 1, hard-deletes (removes entirely).
 * Returns `KPXC_OK` on success.
 */
 int kpxc_entry_delete(struct KpxcDatabase *db, const char *entry_uuid, int permanent) ;

/**
 * Get the name of a group identified by UUID.
 *
 * Returns a heap-allocated string (caller frees with `kpxc_string_free`),
 * or null if the group is not found.
 */
 char *kpxc_group_get_name(struct KpxcDatabase *db, const char *group_uuid) ;

/**
 * Set the name of a group identified by UUID.
 *
 * Returns `KPXC_OK` on success.
 */
 int kpxc_group_set_name(struct KpxcDatabase *db, const char *group_uuid, const char *name) ;

/**
 * Get the UUID of a child group at the given index within a parent group.
 *
 * Returns a heap-allocated UUID string (caller frees with `kpxc_string_free`),
 * or null on error.
 */
 char *kpxc_group_get_uuid(struct KpxcDatabase *db, const char *parent_uuid, uintptr_t index) ;

/**
 * Get the number of direct entries in a group.
 *
 * Returns the count (>= 0) on success, or a negative error code.
 */
 int kpxc_group_entries_count(struct KpxcDatabase *db, const char *group_uuid) ;

/**
 * Get the number of direct child groups in a group.
 *
 * Returns the count (>= 0) on success, or a negative error code.
 */
 int kpxc_group_groups_count(struct KpxcDatabase *db, const char *group_uuid) ;

/**
 * Create a new child group under the specified parent.
 *
 * Returns the new group's UUID string (caller frees with `kpxc_string_free`),
 * or null on error.
 */
 char *kpxc_group_create(struct KpxcDatabase *db, const char *parent_uuid, const char *name) ;

/**
 * Delete a group by UUID.
 *
 * If `permanent` is 0, soft-deletes (moves to recycle bin).
 * If `permanent` is 1, hard-deletes (removes entirely).
 * Returns `KPXC_OK` on success.
 */
 int kpxc_group_delete(struct KpxcDatabase *db, const char *group_uuid, int permanent) ;

/**
 * Return the root group UUID string.
 *
 * Returns a heap-allocated string (caller frees with `kpxc_string_free`),
 * or null on error. This is a convenience alias for `kpxc_database_root_uuid`.
 */
 char *kpxc_group_root_uuid(struct KpxcDatabase *db) ;

/**
 * Merge `other` into `db`, returning a JSON string with merge statistics.
 *
 * `db` is mutated in place. `other` is read-only.
 * Returns a heap-allocated JSON string (caller frees with `kpxc_string_free`),
 * or null on error.
 *
 * IMPORTANT: Both `db` and `other` must be valid, distinct pointers.
 */
 char *kpxc_database_merge(struct KpxcDatabase *db, struct KpxcDatabase *other) ;

/**
 * Open a KDBX database with password + YubiKey challenge-response.
 *
 * `slot` is the YubiKey slot ("1" or "2").
 * `serial` is the YubiKey serial number; pass 0 to use the first detected YubiKey.
 *
 * Returns a heap-allocated `KpxcDatabase` handle, or null on error.
 */

struct KpxcDatabase *kpxc_database_open_with_yubikey(const char *path,
                                                     const char *password,
                                                     const char *slot,
                                                     uint32_t serial)
;

/**
 * List all connected YubiKey devices capable of challenge-response.
 *
 * Returns a JSON array string like `[{"serial_number":12345,"name":"YubiKey 5"}]`.
 * Caller frees with `kpxc_string_free`. Returns null on error.
 */
 char *kpxc_yubikey_list(void) ;

#endif  /* KEEPASSXC_FFI_H */
