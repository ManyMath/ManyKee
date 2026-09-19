mod file_read_tests {
    use keepass::{
        db::{Database, DatabaseOpenError, Group},
        DatabaseKey,
    };

    use uuid::uuid;

    use std::{fs::File, path::Path};

    fn explore(parent: &Group) -> (usize, usize) {
        let mut total_entries = 0;
        let mut total_groups = 1;
        for entry in &parent.entries {
            let title = entry.get_title().unwrap_or("(no title)");
            let user = entry.get_username().unwrap_or("(no user)");
            let pass = entry.get_password().unwrap_or("(no password)");
            println!("Entry '{0}': '{1}' : '{2}'", title, user, pass);
            total_entries += 1;
        }

        for group in &parent.groups {
            println!("Saw group '{0}'", group.name);
            let (ee, eg) = explore(group);

            total_entries += ee;
            total_groups += eg;
        }

        (total_entries, total_groups)
    }

    #[test]
    fn open_kdbx3_with_password() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_with_password.kdbx");
        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_password("demopass"),
        )?;

        println!("{:?} DB Opened", db);
        assert_eq!(db.root.name, "sample");
        assert_eq!(db.root.groups.len(), 3);
        assert_eq!(db.root.entries.len(), 2);

        let (total_entries, total_groups) = explore(&db.root);
        assert_eq!(total_groups, 5);
        assert_eq!(total_entries, 6);

        println!("{:?}", db);

        Ok(())
    }

    #[test]
    fn open_kdbx3_with_keyfile() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_with_keyfile.kdbx");
        let kf_path = Path::new("tests/resources/test_key.key");
        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_keyfile(&mut File::open(kf_path)?)?,
        )?;

        println!("{:?} DB Opened", db);
        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 1);

        let (total_entries, total_groups) = explore(&db.root);
        assert_eq!(total_groups, 1);
        assert_eq!(total_entries, 1);

        println!("{:?}", db);

        Ok(())
    }

    #[test]
    fn open_kdbx3_with_keyfile_xml() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_with_keyfile_xml.kdbx");
        let kf_path = Path::new("tests/resources/test_key_xml.key");
        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_keyfile(&mut File::open(kf_path)?)?,
        )?;

        println!("{:?} DB Opened", db);
        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 2);
        assert_eq!(db.root.entries.len(), 2);

        let (total_entries, total_groups) = explore(&db.root);
        assert_eq!(total_groups, 5);
        assert_eq!(total_entries, 6);

        println!("{:?}", db);

        Ok(())
    }

    #[test]
    fn open_kdbx4_with_password_kdf_argon2_cipher_aes() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdbx4_with_password_argon2.kdbx");

        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_password("demopass"),
        )?;

        println!("{:?} DB Opened", db);

        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 2);

        Ok(())
    }

    #[test]
    fn open_kdbx4_with_password_kdf_argon2id_cipher_aes() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdbx4_with_password_argon2id.kdbx");

        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_password("demopass"),
        )?;

        println!("{:?} DB Opened", db);

        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 2);

        Ok(())
    }

    #[test]
    fn open_kdbx4_with_password_kdf_aes_cipher_aes() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdbx4_with_password_aes.kdbx");
        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_password("demopass"),
        )?;

        println!("{:?} DB Opened", db);

        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 1);

        Ok(())
    }

    #[test]
    fn open_kdbx4_with_password_kdf_argon2_cipher_twofish() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdbx4_with_password_argon2_twofish.kdbx");

        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_password("demopass"),
        )?;

        println!("{:?} DB Opened", db);

        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 1);

        Ok(())
    }

    #[test]
    fn open_kdbx4_with_password_kdf_argon2_cipher_chacha20() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdbx4_with_password_argon2_chacha20.kdbx");

        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_password("demopass"),
        )?;

        println!("{:?} DB Opened", db);

        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 1);

        Ok(())
    }

    #[test]
    fn open_kdbx4_with_password_kdf_argon2id_cipher_twofish() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdbx4_with_password_argon2id_twofish.kdbx");

        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_password("demopass"),
        )?;

        println!("{:?} DB Opened", db);

        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 1);

        Ok(())
    }

    #[test]
    fn open_kdbx4_with_password_kdf_argon2id_cipher_chacha20() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdbx4_with_password_argon2id_chacha20.kdbx");

        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_password("demopass"),
        )?;

        println!("{:?} DB Opened", db);

        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 1);

        Ok(())
    }

    #[test]
    fn open_kdbx4_with_keyfile() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdbx4_with_keyfile.kdbx");
        let kf_path = Path::new("tests/resources/test_key.key");

        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_keyfile(&mut File::open(kf_path)?)?,
        )?;

        println!("{:?} DB Opened", db);

        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 1);

        Ok(())
    }

    #[test]
    fn open_kdbx4_with_keyfile_v2() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdbx4_with_keyfile_v2.kdbx");
        let kf_path = Path::new("tests/resources/test_db_kdbx4_with_keyfile_v2.keyx");

        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new()
                .with_password("demopass")
                .with_keyfile(&mut File::open(kf_path)?)?,
        )?;

        println!("{:?} DB Opened", db);

        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 1);

        Ok(())
    }

    /// keyfile with tabs in the keyfile content (#284)
    #[test]
    fn open_kdbx4_with_keyfile_v2_alt() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdbx4_with_keyfile_v2_alt.kdbx");
        let kf_path = Path::new("tests/resources/test_db_kdbx4_with_keyfile_v2_alt.keyx");

        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new()
                .with_password("123123")
                .with_keyfile(&mut File::open(kf_path)?)?,
        )?;

        println!("{:?} DB Opened", db);

        assert_eq!(db.root.name, "testdb02");
        assert_eq!(db.root.groups.len(), 6);
        assert_eq!(db.root.entries.len(), 2);

        Ok(())
    }

    #[test]
    #[should_panic(expected = r#"InvalidKDBXIdentifier"#)]
    fn open_broken_random_data() {
        let path = Path::new("tests/resources/broken_random_data.kdbx");
        Database::open(
            &mut File::open(path).unwrap(),
            DatabaseKey::new().with_password(""),
        )
        .unwrap();
    }

    #[test]
    #[should_panic(expected = r#"InvalidKDBXVersion"#)]
    fn open_broken_kdbx_version() {
        let path = Path::new("tests/resources/broken_kdbx_version.kdbx");
        Database::open(
            &mut File::open(path).unwrap(),
            DatabaseKey::new().with_password(""),
        )
        .unwrap();
    }

    #[test]
    fn open_kdb_with_password() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdb_with_password.kdb");
        let db = Database::open(&mut File::open(path)?, DatabaseKey::new().with_password("foobar"))?;

        println!("{:?} DB Opened", db);
        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 3);

        let (total_entries, total_groups) = explore(&db.root);
        assert_eq!(total_groups, 12);
        assert_eq!(total_entries, 5);

        println!("{:?}", db);

        Ok(())
    }

    #[test]
    fn open_kdb_with_larger_than_1mb_file_does_not_crash() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdb3_with_file_larger_1mb.kdbx");
        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_password("samplepassword"),
        )?;

        println!("{:?} DB Opened", db);
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 1);

        let (total_entries, total_groups) = explore(&db.root);
        assert_eq!(total_groups, 1);
        assert_eq!(total_entries, 1);

        println!("{:?}", db);
        Ok(())
    }

    #[test]
    fn open_kdbx4_with_password_deleted_entry() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_kdbx4_with_password_deleted_entry.kdbx");

        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new().with_password("demopass"),
        )?;

        println!("{:?} DB Opened", db);

        assert_eq!(db.root.name, "Root");
        assert_eq!(
            db.meta.recyclebin_uuid,
            Some(uuid!("563171fe-6598-42dc-8003-f98dde32e872"))
        );

        let recycle_bin = db.root.group_by_uuid(db.meta.recyclebin_uuid.unwrap()).unwrap();
        assert_eq!(recycle_bin.name, "Recycle Bin");

        Ok(())
    }

    #[test]
    #[cfg(feature = "challenge_response")]
    fn open_kdbx4_with_challenge_response_key() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_with_challenge_response_key.kdbx");
        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new()
                .with_password("demopass")
                .with_challenge_response_key(keepass::ChallengeResponseKey::LocalChallenge(
                    "0102030405060708090a0b0c0d0e0f1011121314".to_string(),
                )),
        )?;

        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 2);
        Ok(())
    }

    #[test]
    #[ignore]
    #[cfg(feature = "challenge_response")]
    fn open_kdbx4_with_yubikey_challenge_response_key() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_with_challenge_response_key.kdbx");
        let yubikey = keepass::ChallengeResponseKey::get_yubikey(None).expect("Failed to get Yubikey");
        let db = Database::open(
            &mut File::open(path)?,
            DatabaseKey::new()
                .with_password("demopass")
                .with_challenge_response_key(keepass::ChallengeResponseKey::YubikeyChallenge(
                    yubikey,
                    "2".to_string(),
                )),
        )?;

        assert_eq!(db.root.name, "Root");
        assert_eq!(db.root.groups.len(), 0);
        assert_eq!(db.root.entries.len(), 2);
        Ok(())
    }

    #[test]
    fn test_get_version() -> Result<(), DatabaseOpenError> {
        let path = Path::new("tests/resources/test_db_with_password.kdbx");
        let version = Database::get_version(&mut File::open(path)?)?;
        assert_eq!(version.to_string(), "KDBX3.1");

        let path = Path::new("tests/resources/test_db_kdbx4_with_password_argon2.kdbx");
        let version = Database::get_version(&mut File::open(path)?)?;
        assert_eq!(version.to_string(), "KDBX4.0");

        Ok(())
    }

    #[test]
    fn open_kdbx3_fuzzing() -> Result<(), DatabaseOpenError> {
        // Regression test for a panic on truncated/malformed kdbx3 files:
        // `&payload[0..header.stream_start.len()]` used to index past the
        // end of the decrypted payload when the file was cut short.
        use std::io::Read;
        let path = Path::new("tests/resources/test_db_with_password.kdbx");
        let file_len = path.metadata()?.len() as usize;

        let mut file_as_vec = Vec::new();
        File::open(path)?.read_to_end(&mut file_as_vec)?;

        for one_len in 0..=file_len {
            let current_slice = &file_as_vec[..one_len];
            let res = Database::parse(current_slice, DatabaseKey::new().with_password("demopass"));
            match res {
                Ok(db) => {
                    assert_eq!(db.root.name, "sample");
                }
                Err(_) => {
                    // we don't care about the error, only that it didn't panic
                    continue;
                }
            }
        }

        Ok(())
    }

    #[test]
    fn open_kdbx4_fuzzing() -> Result<(), DatabaseOpenError> {
        use std::io::Read;
        let path = Path::new("tests/resources/test_db_few_rounds.kdbx");
        let file_len = path.metadata()?.len() as usize;

        let mut file_as_vec = Vec::new();
        File::open(path)?.read_to_end(&mut file_as_vec)?;

        for one_len in 0..=file_len {
            print!("Trying length: {}", one_len);
            let current_slice = &file_as_vec[..one_len];
            let res = Database::parse(current_slice, DatabaseKey::new().with_password("demopass"));
            match res {
                Ok(db) => {
                    println!(" - DB Opened");

                    assert_eq!(db.root.name, "Root");
                    assert_eq!(db.root.entries.len(), 1);
                }
                Err(_) => {
                    println!(" - failed with error");
                    continue;
                    // we don't care about error, it's normal, we just check for panic
                }
            }
        }

        Ok(())
    }

    /// Size of the KDBX signature + version header that precedes the outer
    /// header entries in both KDBX3 and KDBX4 files.
    const VERSION_HEADER_SIZE: usize = 12;

    /// Returns the offset of the type byte of the first outer header entry
    /// with type `entry_type`. `len_width` is the width of the entry length
    /// field: 2 bytes for KDBX3, 4 bytes for KDBX4.
    fn find_outer_header_entry(data: &[u8], len_width: usize, entry_type: u8) -> usize {
        let mut pos = VERSION_HEADER_SIZE;
        loop {
            let ty = data[pos];
            let len_bytes = &data[pos + 1..pos + 1 + len_width];
            let len = len_bytes
                .iter()
                .rev()
                .fold(0usize, |acc, b| (acc << 8) | *b as usize);
            if ty == entry_type {
                return pos;
            }
            assert_ne!(ty, 0, "outer header entry type {} not found", entry_type);
            pos += 1 + len_width + len;
        }
    }

    /// Rewrites the length field of the outer header entry at `entry_pos` to
    /// `new_len` so that a fixed-width field is shorter than its type.
    fn shrink_outer_header_entry(data: &[u8], len_width: usize, entry_pos: usize, new_len: usize) -> Vec<u8> {
        let mut mutated = data.to_vec();
        for (i, byte) in mutated[entry_pos + 1..entry_pos + 1 + len_width]
            .iter_mut()
            .enumerate()
        {
            *byte = ((new_len >> (8 * i)) & 0xff) as u8;
        }
        mutated
    }

    fn assert_short_outer_header_field_is_an_error(
        fixture: &str,
        len_width: usize,
        entry_type: u8,
        field_width: usize,
    ) {
        use std::io::Read;
        let mut data = Vec::new();
        File::open(Path::new(fixture))
            .unwrap()
            .read_to_end(&mut data)
            .unwrap();

        let entry_pos = find_outer_header_entry(&data, len_width, entry_type);

        for new_len in 1..field_width {
            let mutated = shrink_outer_header_entry(&data, len_width, entry_pos, new_len);
            // Must return an error rather than panic inside `byteorder`.
            // Header parsing happens before the key is verified, so this is
            // reachable without knowing the password.
            let res = Database::parse(&mutated, DatabaseKey::new().with_password("demopass"));
            assert!(
                res.is_err(),
                "{}: entry type {} with a {}-byte buffer must not parse",
                fixture,
                entry_type,
                new_len
            );
        }
    }

    const KDBX3_FIXTURE: &str = "tests/resources/test_db_with_password.kdbx";
    const KDBX4_FIXTURE: &str = "tests/resources/test_db_few_rounds.kdbx";

    #[test]
    fn kdbx3_short_compression_flags_field_is_an_error() {
        // 3 = COMPRESSIONFLAGS, stored as a u32.
        assert_short_outer_header_field_is_an_error(KDBX3_FIXTURE, 2, 3, 4);
    }

    #[test]
    fn kdbx3_short_transform_rounds_field_is_an_error() {
        // 6 = TRANSFORMROUNDS, stored as a u64.
        assert_short_outer_header_field_is_an_error(KDBX3_FIXTURE, 2, 6, 8);
    }

    #[test]
    fn kdbx3_short_inner_random_stream_id_field_is_an_error() {
        // 10 = INNERRANDOMSTREAMID, stored as a u32.
        assert_short_outer_header_field_is_an_error(KDBX3_FIXTURE, 2, 10, 4);
    }

    #[test]
    fn kdbx4_short_compression_flags_field_is_an_error() {
        // 3 = COMPRESSIONFLAGS, stored as a u32.
        assert_short_outer_header_field_is_an_error(KDBX4_FIXTURE, 4, 3, 4);
    }
}
