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

 const char *kpxc_last_error(void) ;

 void kpxc_string_free(char *ptr) ;

 struct KpxcDatabase *kpxc_database_open(const char *path, const char *password) ;


struct KpxcDatabase *kpxc_database_open_bytes(const uint8_t *bytes,
                                              uintptr_t len,
                                              const char *password)
;


struct KpxcDatabase *kpxc_database_open_with_keyfile(const char *path,
                                                     const char *password,
                                                     const char *keyfile_path)
;


struct KpxcDatabase *kpxc_database_open_bytes_with_keyfile(const uint8_t *bytes,
                                                           uintptr_t len,
                                                           const char *password,
                                                           const uint8_t *keyfile_bytes,
                                                           uintptr_t keyfile_len)
;

 int kpxc_database_save(struct KpxcDatabase *db, const char *path, const char *password) ;


int kpxc_database_save_bytes(struct KpxcDatabase *db,
                             const char *password,
                             uint8_t **out_ptr,
                             uintptr_t *out_len)
;


int kpxc_database_save_with_keyfile(struct KpxcDatabase *db,
                                    const char *path,
                                    const char *password,
                                    const char *keyfile_path)
;


int kpxc_database_save_bytes_with_keyfile(struct KpxcDatabase *db,
                                          const char *password,
                                          const uint8_t *keyfile_bytes,
                                          uintptr_t keyfile_len,
                                          uint8_t **out_ptr,
                                          uintptr_t *out_len)
;

 void kpxc_bytes_free(uint8_t *ptr, uintptr_t len) ;

 void kpxc_database_free(struct KpxcDatabase *db) ;

 char *kpxc_database_root_uuid(struct KpxcDatabase *db) ;


char *kpxc_entry_get_field(struct KpxcDatabase *db,
                           const char *entry_uuid,
                           const char *field_name)
;

 char *kpxc_entry_read_fields(struct KpxcDatabase *db, const char *entry_uuid) ;

 char *kpxc_entry_get_totp(struct KpxcDatabase *db, const char *entry_uuid) ;


int kpxc_entry_set_field(struct KpxcDatabase *db,
                         const char *entry_uuid,
                         const char *field_name,
                         const char *value,
                         int protected_)
;

 char *kpxc_entry_get_uuid(struct KpxcDatabase *db, const char *group_uuid, uintptr_t index) ;

 char *kpxc_entry_create(struct KpxcDatabase *db, const char *group_uuid) ;

 int kpxc_entry_delete(struct KpxcDatabase *db, const char *entry_uuid, int permanent) ;


int kpxc_entry_move(struct KpxcDatabase *db,
                    const char *entry_uuid,
                    const char *target_group_uuid)
;

 char *kpxc_group_get_name(struct KpxcDatabase *db, const char *group_uuid) ;

 int kpxc_group_set_name(struct KpxcDatabase *db, const char *group_uuid, const char *name) ;

 char *kpxc_group_get_uuid(struct KpxcDatabase *db, const char *parent_uuid, uintptr_t index) ;

 int kpxc_group_entries_count(struct KpxcDatabase *db, const char *group_uuid) ;

 int kpxc_group_groups_count(struct KpxcDatabase *db, const char *group_uuid) ;

 char *kpxc_group_create(struct KpxcDatabase *db, const char *parent_uuid, const char *name) ;

 int kpxc_group_delete(struct KpxcDatabase *db, const char *group_uuid, int permanent) ;

 char *kpxc_group_root_uuid(struct KpxcDatabase *db) ;


int kpxc_group_move(struct KpxcDatabase *db,
                    const char *group_uuid,
                    const char *target_parent_uuid)
;

 char *kpxc_database_merge(struct KpxcDatabase *db, struct KpxcDatabase *other) ;


struct KpxcDatabase *kpxc_database_open_with_yubikey(const char *path,
                                                     const char *password,
                                                     const char *slot,
                                                     uint32_t serial)
;

 char *kpxc_yubikey_list(void) ;

#endif  /* KEEPASSXC_FFI_H */
