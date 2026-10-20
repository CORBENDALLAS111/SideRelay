use serde::Serialize;
use std::{collections::HashSet, fs::File, io::Read, path::Path};

#[derive(Clone, Serialize)]
pub struct AppInfo {
    pub name: String,
    pub bundle_id: String,
    pub version: String,
    pub bytes: u64,
}

/// Validate every entry before the upstream engine extracts the archive.
pub fn inspect(path: &Path) -> Result<AppInfo, String> {
    let file = File::open(path).map_err(|_| "Не удалось открыть IPA")?;
    let bytes = file
        .metadata()
        .map_err(|_| "Не удалось прочитать IPA")?
        .len();
    let mut archive = zip::ZipArchive::new(file).map_err(|_| "IPA должен быть ZIP-архивом")?;
    if archive.len() > 30_000 {
        return Err("Слишком много файлов в IPA".into());
    }
    let mut total = 0u64;
    let mut names = HashSet::new();
    let mut bundles = HashSet::new();
    let mut info_path = None;
    for i in 0..archive.len() {
        let entry = archive.by_index(i).map_err(|_| "Повреждённый ZIP")?;
        let name = entry.name();
        if !safe_name(name) || !names.insert(name.to_lowercase()) {
            return Err("Небезопасный или повторяющийся путь в IPA".into());
        }
        if entry.is_symlink() {
            return Err("IPA с символическими ссылками не поддерживается".into());
        }
        total = total
            .checked_add(entry.size())
            .ok_or("Слишком большой IPA")?;
        if total > 512 * 1024 * 1024 || entry.size() > 256 * 1024 * 1024 {
            return Err("Распакованный IPA превышает лимит".into());
        }
        let parts: Vec<_> = name.split('/').collect();
        if parts.len() >= 2 && parts[0] == "Payload" && parts[1].ends_with(".app") {
            bundles.insert(parts[1].to_owned());
            if parts.len() == 3 && parts[2] == "Info.plist" {
                info_path = Some(name.to_owned());
            }
        }
    }
    if bundles.len() != 1 {
        return Err("Нужен ровно один Payload/*.app".into());
    }
    let info_path = info_path.ok_or("В IPA нет Info.plist")?;
    let entry = archive.by_name(&info_path).map_err(|_| "Нет Info.plist")?;
    if entry.size() > 1024 * 1024 {
        return Err("Слишком большой Info.plist".into());
    }
    let mut data = Vec::new();
    entry
        .take(1024 * 1024 + 1)
        .read_to_end(&mut data)
        .map_err(|_| "Повреждён Info.plist")?;
    let info =
        plist::Value::from_reader(std::io::Cursor::new(data)).map_err(|_| "Неверный Info.plist")?;
    let dict = info.as_dictionary().ok_or("Неверный Info.plist")?;
    let get = |key: &str| dict.get(key).and_then(|v| v.as_string()).map(str::to_owned);
    Ok(AppInfo {
        name: get("CFBundleDisplayName")
            .or_else(|| get("CFBundleName"))
            .unwrap_or_else(|| "iOS App".into()),
        bundle_id: get("CFBundleIdentifier").ok_or("Нет bundle identifier")?,
        version: get("CFBundleShortVersionString").unwrap_or_else(|| "—".into()),
        bytes,
    })
}

fn safe_name(name: &str) -> bool {
    !name.is_empty()
        && !name.starts_with('/')
        && !name.contains(['\\', ':', '\0'])
        && name
            .trim_end_matches('/')
            .split('/')
            .all(|p| !p.is_empty() && p != ".." && p != ".")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    #[test]
    fn rejects_paths_that_can_escape_or_alias() {
        for name in [
            "../secret",
            "/etc/passwd",
            "C:/a",
            "a\\b",
            "a/../b",
            "a//b",
            "./a",
            "a\0b",
        ] {
            assert!(!safe_name(name), "{name}");
        }
        assert!(safe_name("Payload/Example.app/Frameworks/"));
    }
    #[test]
    fn reads_binary_plist_and_rejects_duplicate_entries() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("test.ipa");
        let create = |duplicate| {
            let mut zip = zip::ZipWriter::new(File::create(&path).unwrap());
            let mut dict = plist::Dictionary::new();
            dict.insert("CFBundleIdentifier".into(), "com.example.test".into());
            let mut bytes = Vec::new();
            plist::to_writer_binary(&mut bytes, &dict).unwrap();
            zip.start_file(
                "Payload/Test.app/Info.plist",
                zip::write::SimpleFileOptions::default(),
            )
            .unwrap();
            zip.write_all(&bytes).unwrap();
            if duplicate {
                zip.start_file(
                    "Payload/Test.app/INFO.plist",
                    zip::write::SimpleFileOptions::default(),
                )
                .unwrap();
                zip.write_all(&bytes).unwrap();
            }
            zip.finish().unwrap();
        };
        create(false);
        assert_eq!(inspect(&path).unwrap().bundle_id, "com.example.test");
        create(true);
        assert!(inspect(&path).is_err());
    }
}
