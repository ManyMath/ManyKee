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

#define KPXC_ERR_PARSE -9

#define KPXC_ERR_PANIC -10

#define KPXC_ERR_RECYCLE_BIN_DISABLED -11

 const char *kpxc_last_error(void) ;

/**
 * Frees a string returned by this library. The bytes are overwritten with
 * zeros before the allocation is released, since these buffers can carry
 * plaintext secrets (e.g. a password from `kpxc_entry_get_field`).
 *
 * # Safety
 *
 * `ptr` must be null or a string returned by this library that has not already
 * been freed. It must not be used after this call.
 */
 void kpxc_string_free(char *ptr) ;

/**
 * # Safety
 *
 * `path` and `password` must each be null or point to a NUL-terminated string
 * that stays valid for the duration of the call.
 */
 struct KpxcDatabase *kpxc_database_open(const char *path, const char *password) ;

/**
 * Create a new, empty KDBX4 database in memory (not yet saved to disk).
 * Mirrors the sensible-defaults `DatabaseConfig` (`keepass-rs`'s own
 * `Default` impl: KDBX4, AES256 outer cipher, ChaCha20 inner cipher,
 * Argon2 KDF) that `kpxc_database_save`'s own test coverage already
 * exercises, with the recycle bin enabled as KeePassXC does, so a caller
 * can create, soft-delete in, then save a fresh database via the existing
 * `kpxc_database_save`/`_with_keyfile` functions rather than needing a
 * template file to open first.
 */
 struct KpxcDatabase *kpxc_database_create(void) ;

/**
 * # Safety
 *
 * `path`, `password` and `keyfile_path` must each be null or point to a
 * NUL-terminated string that stays valid for the duration of the call.
 */

struct KpxcDatabase *kpxc_database_open_with_keyfile(const char *path,
                                                     const char *password,
                                                     const char *keyfile_path)
;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `path` and `password` must each be null or point to a NUL-terminated
 * string that stays valid for the duration of the call.
 */
 int kpxc_database_save(struct KpxcDatabase *db, const char *path, const char *password) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `path`, `password` and `keyfile_path` must each be null or point to a
 * NUL-terminated string that stays valid for the duration of the call.
 */

int kpxc_database_save_with_keyfile(struct KpxcDatabase *db,
                                    const char *path,
                                    const char *password,
                                    const char *keyfile_path)
;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not already
 * been freed, and no other call may be using it. It must not be used after
 * this call.
 */
 void kpxc_database_free(struct KpxcDatabase *db) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time.
 */
 char *kpxc_database_root_uuid(struct KpxcDatabase *db) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `entry_uuid` and `field_name` must each be null or point to a
 * NUL-terminated string that stays valid for the duration of the call.
 */

char *kpxc_entry_get_field(struct KpxcDatabase *db,
                           const char *entry_uuid,
                           const char *field_name)
;

/**
 * Return the safe list summary for one entry as JSON.
 *
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `entry_uuid` must be null or point to a NUL-terminated string that
 * stays valid for the duration of the call.
 */
 char *kpxc_entry_get_info(struct KpxcDatabase *db, const char *entry_uuid) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `entry_uuid` must be null or point to a NUL-terminated string that
 * stays valid for the duration of the call.
 */
 char *kpxc_entry_read_fields(struct KpxcDatabase *db, const char *entry_uuid) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `entry_uuid` must be null or point to a NUL-terminated string that
 * stays valid for the duration of the call.
 */
 char *kpxc_entry_get_totp(struct KpxcDatabase *db, const char *entry_uuid) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `entry_uuid`, `field_name` and `value` must each be null or point to a
 * NUL-terminated string that stays valid for the duration of the call.
 */

int kpxc_entry_set_field(struct KpxcDatabase *db,
                         const char *entry_uuid,
                         const char *field_name,
                         const char *value,
                         int protected_)
;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `group_uuid` must be null or point to a NUL-terminated string that
 * stays valid for the duration of the call.
 */
 char *kpxc_entry_get_uuid(struct KpxcDatabase *db, const char *group_uuid, uintptr_t index) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `group_uuid` must be null or point to a NUL-terminated string that
 * stays valid for the duration of the call.
 */
 char *kpxc_entry_create(struct KpxcDatabase *db, const char *group_uuid) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `entry_uuid` must be null or point to a NUL-terminated string that
 * stays valid for the duration of the call.
 */
 int kpxc_entry_delete(struct KpxcDatabase *db, const char *entry_uuid, int permanent) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `entry_uuid` and `target_group_uuid` must each be null or point to a
 * NUL-terminated string that stays valid for the duration of the call.
 */

int kpxc_entry_move(struct KpxcDatabase *db,
                    const char *entry_uuid,
                    const char *target_group_uuid)
;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `group_uuid` must be null or point to a NUL-terminated string that
 * stays valid for the duration of the call.
 */
 char *kpxc_group_get_name(struct KpxcDatabase *db, const char *group_uuid) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `group_uuid` and `name` must each be null or point to a NUL-terminated
 * string that stays valid for the duration of the call.
 */
 int kpxc_group_set_name(struct KpxcDatabase *db, const char *group_uuid, const char *name) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `parent_uuid` must be null or point to a NUL-terminated string that
 * stays valid for the duration of the call.
 */
 char *kpxc_group_get_uuid(struct KpxcDatabase *db, const char *parent_uuid, uintptr_t index) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `group_uuid` must be null or point to a NUL-terminated string that
 * stays valid for the duration of the call.
 */
 int kpxc_group_entries_count(struct KpxcDatabase *db, const char *group_uuid) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `group_uuid` must be null or point to a NUL-terminated string that
 * stays valid for the duration of the call.
 */
 int kpxc_group_groups_count(struct KpxcDatabase *db, const char *group_uuid) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `parent_uuid` and `name` must each be null or point to a
 * NUL-terminated string that stays valid for the duration of the call.
 */
 char *kpxc_group_create(struct KpxcDatabase *db, const char *parent_uuid, const char *name) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `group_uuid` must be null or point to a NUL-terminated string that
 * stays valid for the duration of the call.
 */
 int kpxc_group_delete(struct KpxcDatabase *db, const char *group_uuid, int permanent) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time.
 */
 char *kpxc_group_root_uuid(struct KpxcDatabase *db) ;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `group_uuid` and `target_parent_uuid` must each be null or point to a
 * NUL-terminated string that stays valid for the duration of the call.
 */

int kpxc_group_move(struct KpxcDatabase *db,
                    const char *group_uuid,
                    const char *target_parent_uuid)
;

/**
 * # Safety
 *
 * `db` and `other` must each be null or a handle returned by this library that
 * has not been passed to `kpxc_database_free`, and no other call may use them
 * at the same time.
 */
 char *kpxc_database_merge(struct KpxcDatabase *db, struct KpxcDatabase *other) ;

/**
 * # Safety
 *
 * `path`, `password` and `slot` must each be null or point to a NUL-terminated
 * string that stays valid for the duration of the call.
 */

struct KpxcDatabase *kpxc_database_open_with_yubikey(const char *path,
                                                     const char *password,
                                                     const char *slot,
                                                     uint32_t serial)
;

/**
 * # Safety
 *
 * `path`, `password` and `hex_secret` must each be null or point to a
 * NUL-terminated string that stays valid for the duration of the call.
 */

struct KpxcDatabase *kpxc_database_open_with_local_challenge(const char *path,
                                                             const char *password,
                                                             const char *hex_secret)
;

/**
 * # Safety
 *
 * `path`, `password`, `keyfile_path` and `slot` must each be null or point to
 * a NUL-terminated string that stays valid for the duration of the call.
 */

struct KpxcDatabase *kpxc_database_open_with_keyfile_and_yubikey(const char *path,
                                                                 const char *password,
                                                                 const char *keyfile_path,
                                                                 const char *slot,
                                                                 uint32_t serial)
;

/**
 * # Safety
 *
 * `path`, `password`, `keyfile_path` and `hex_secret` must each be null or
 * point to a NUL-terminated string that stays valid for the duration of the
 * call.
 */

struct KpxcDatabase *kpxc_database_open_with_keyfile_and_local_challenge(const char *path,
                                                                         const char *password,
                                                                         const char *keyfile_path,
                                                                         const char *hex_secret)
;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `path`, `password` and `slot` must each be null or point to a
 * NUL-terminated string that stays valid for the duration of the call.
 */

int kpxc_database_save_with_yubikey(struct KpxcDatabase *db,
                                    const char *path,
                                    const char *password,
                                    const char *slot,
                                    uint32_t serial)
;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `path`, `password`, `keyfile_path` and `slot` must each be null or
 * point to a NUL-terminated string that stays valid for the duration of the
 * call.
 */

int kpxc_database_save_with_keyfile_and_yubikey(struct KpxcDatabase *db,
                                                const char *path,
                                                const char *password,
                                                const char *keyfile_path,
                                                const char *slot,
                                                uint32_t serial)
;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `path`, `password` and `hex_secret` must each be null or point to a
 * NUL-terminated string that stays valid for the duration of the call.
 */

int kpxc_database_save_with_local_challenge(struct KpxcDatabase *db,
                                            const char *path,
                                            const char *password,
                                            const char *hex_secret)
;

/**
 * # Safety
 *
 * `db` must be null or a handle returned by this library that has not been
 * passed to `kpxc_database_free`, and no other call may use it at the same
 * time. `path`, `password`, `keyfile_path` and `hex_secret` must each be null
 * or point to a NUL-terminated string that stays valid for the duration of the
 * call.
 */

int kpxc_database_save_with_keyfile_and_local_challenge(struct KpxcDatabase *db,
                                                        const char *path,
                                                        const char *password,
                                                        const char *keyfile_path,
                                                        const char *hex_secret)
;

 char *kpxc_yubikey_list(void) ;

#endif  /* KEEPASSXC_FFI_H */
