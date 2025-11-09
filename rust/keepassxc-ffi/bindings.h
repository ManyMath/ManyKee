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

 const char *kpxc_last_error(void) ;

 void kpxc_string_free(char *ptr) ;

 struct KpxcDatabase *kpxc_database_open(const char *path, const char *password) ;


struct KpxcDatabase *kpxc_database_open_with_keyfile(const char *path,
                                                     const char *password,
                                                     const char *keyfile_path)
;

 int kpxc_database_save(struct KpxcDatabase *db, const char *path, const char *password) ;

 void kpxc_database_free(struct KpxcDatabase *db) ;

 char *kpxc_database_root_uuid(struct KpxcDatabase *db) ;


char *kpxc_entry_get_field(struct KpxcDatabase *db,
                           const char *entry_uuid,
                           const char *field_name)
;


int kpxc_entry_set_field(struct KpxcDatabase *db,
                         const char *entry_uuid,
                         const char *field_name,
                         const char *value,
                         int protected_)
;

 char *kpxc_entry_get_uuid(struct KpxcDatabase *db, const char *group_uuid, uintptr_t index) ;

 char *kpxc_entry_create(struct KpxcDatabase *db, const char *group_uuid) ;

 int kpxc_entry_delete(struct KpxcDatabase *db, const char *entry_uuid, int permanent) ;

 char *kpxc_group_get_name(struct KpxcDatabase *db, const char *group_uuid) ;

 int kpxc_group_set_name(struct KpxcDatabase *db, const char *group_uuid, const char *name) ;

 char *kpxc_group_get_uuid(struct KpxcDatabase *db, const char *parent_uuid, uintptr_t index) ;

 int kpxc_group_entries_count(struct KpxcDatabase *db, const char *group_uuid) ;

 int kpxc_group_groups_count(struct KpxcDatabase *db, const char *group_uuid) ;

 char *kpxc_group_create(struct KpxcDatabase *db, const char *parent_uuid, const char *name) ;

 int kpxc_group_delete(struct KpxcDatabase *db, const char *group_uuid, int permanent) ;

 char *kpxc_group_root_uuid(struct KpxcDatabase *db) ;

 char *kpxc_database_merge(struct KpxcDatabase *db, struct KpxcDatabase *other) ;


struct KpxcDatabase *kpxc_database_open_with_yubikey(const char *path,
                                                     const char *password,
                                                     const char *slot,
                                                     uint32_t serial)
;

 char *kpxc_yubikey_list(void) ;

#endif  /* KEEPASSXC_FFI_H */
