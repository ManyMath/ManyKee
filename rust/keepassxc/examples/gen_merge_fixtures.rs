//! Generate two diverged KDBX4 databases for CLI merge E2E testing.
//!
//! Creates:
//! - merge_base_a.kdbx: base database + entry edited on side A
//! - merge_base_b.kdbx: base database + new entry added on side B
//!
//! Both files use password "demopass".

use std::fs::File;
use std::io::Cursor;
use std::thread;
use std::time::Duration;

use keepass::config::DatabaseConfig;
use keepass::db::{fields, Database, Entry, Group};
use keepass::DatabaseKey;

const PASSWORD: &str = "demopass";

fn make_key() -> DatabaseKey {
 DatabaseKey::new().with_password(PASSWORD)
}

fn round_trip(db: &Database) -> Database {
 let key = make_key();
 let mut buf = Vec::new();
 db.save(&mut buf, key.clone()).expect("save failed");
 Database::open(&mut Cursor::new(&buf), key).expect("open failed")
}

fn main() {
 let out_dir = std::env::args()
 .nth(1)
 .unwrap_or_else(|| "/tmp".to_string());

 // Create base database
 let mut db = Database::new(DatabaseConfig::default());
 db.root.name = "Root".to_string();

 let mut entry1 = Entry::new();
 entry1.set_unprotected(fields::TITLE, "Email Account");
 entry1.set_unprotected(fields::USERNAME, "user@example.com");
 db.root.entries.push(entry1);

 let mut entry2 = Entry::new();
 entry2.set_unprotected(fields::TITLE, "Bank Login");
 entry2.set_unprotected(fields::USERNAME, "banker");
 db.root.entries.push(entry2);

 let mut subgroup = Group::new("Work");
 let mut entry3 = Entry::new();
 entry3.set_unprotected(fields::TITLE, "VPN Access");
 entry3.set_unprotected(fields::USERNAME, "vpnuser");
 subgroup.entries.push(entry3);
 db.root.groups.push(subgroup);

 // Round-trip to establish proper timestamps
 let base = round_trip(&db);

 // Create side A: edit entry1's username
 let mut db_a = round_trip(&base);
 let entry1_uuid = db_a.root.entries[0].uuid;
 let entry_a = db_a.root.entry_by_uuid_mut(entry1_uuid).unwrap();
 entry_a.set_unprotected(fields::USERNAME, "updated_user@example.com");
 thread::sleep(Duration::from_secs(1));
 entry_a.update_history();

 // Create side B: add a new entry
 let mut db_b = round_trip(&base);
 let mut new_entry = Entry::new();
 new_entry.set_unprotected(fields::TITLE, "New SSH Key");
 new_entry.set_unprotected(fields::USERNAME, "sshuser");
 db_b.root.entries.push(new_entry);

 // Save both
 let path_a = format!("{}/merge_fixture_a.kdbx", out_dir);
 let path_b = format!("{}/merge_fixture_b.kdbx", out_dir);

 let key = make_key();
 db_a.save(&mut File::create(&path_a).unwrap(), key.clone())
 .expect("save A failed");
 db_b.save(&mut File::create(&path_b).unwrap(), key)
 .expect("save B failed");

 eprintln!("Created merge fixtures:");
 eprintln!(" {}", path_a);
 eprintln!(" {}", path_b);
 eprintln!("Password: {}", PASSWORD);
}
