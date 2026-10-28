#![cfg(target_os = "linux")]

use std::path::Path;
use std::process::Command;

fn repo_root() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
}

#[test]
fn deepin_package_contains_one_gui_with_legacy_command_aliases() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    let script = root.join("scripts/installer/linux/package-deb.sh");
    std::fs::create_dir_all(script.parent().unwrap()).unwrap();
    std::fs::copy(
        repo_root().join("scripts/installer/linux/package-deb.sh"),
        &script,
    )
    .unwrap();
    let icon = root.join("apps/codex-plus-manager/src-tauri/icons/icon.png");
    std::fs::create_dir_all(icon.parent().unwrap()).unwrap();
    std::fs::write(icon, b"fixture icon").unwrap();
    let binaries = root.join("binaries");
    std::fs::create_dir(&binaries).unwrap();
    std::fs::copy("/bin/true", binaries.join("codex-plus-plus")).unwrap();
    // 模拟 target 里残留的旧管理器；新包必须完全忽略它。
    std::fs::write(binaries.join("codex-plus-plus-manager"), b"stale manager").unwrap();
    let output = Command::new("bash")
        .arg(script)
        .args(["2.0.0+deepin.test", "amd64"])
        .env("BINARY_DIR", &binaries)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let deb = root.join("dist/linux/codex-plus-plus_2.0.0+deepin.test_amd64.deb");
    let listing = Command::new("dpkg-deb")
        .arg("-c")
        .arg(&deb)
        .output()
        .unwrap();
    assert!(String::from_utf8_lossy(&listing.stdout).starts_with("drwxr-xr-x root/root"));
    let extracted = root.join("extracted");
    assert!(
        Command::new("dpkg-deb")
            .arg("-x")
            .arg(&deb)
            .arg(&extracted)
            .status()
            .unwrap()
            .success()
    );
    assert_eq!(
        std::fs::read(extracted.join("usr/lib/codex-plus-plus/codex-plus-plus")).unwrap(),
        std::fs::read("/bin/true").unwrap()
    );
    assert_eq!(
        std::fs::read_link(extracted.join("usr/lib/codex-plus-plus/codex-plus-plus-manager"))
            .unwrap(),
        Path::new("codex-plus-plus")
    );
    assert_eq!(
        std::fs::read_link(extracted.join("usr/bin/codex-plus-plus-manager")).unwrap(),
        Path::new("/usr/lib/codex-plus-plus/codex-plus-plus")
    );
    let desktop =
        std::fs::read_to_string(extracted.join("usr/share/applications/codex-plus-plus.desktop"))
            .unwrap();
    assert!(desktop.contains("Exec=/usr/bin/codex-plus-plus %u"));
    assert!(desktop.contains("x-scheme-handler/codexplusplus"));
    assert!(
        !extracted
            .join("usr/share/applications/codex-plus-plus-manager.desktop")
            .exists()
    );
    let control = Command::new("dpkg-deb")
        .arg("-f")
        .arg(deb)
        .output()
        .unwrap();
    let control = String::from_utf8(control.stdout).unwrap();
    assert!(control.contains("Architecture: amd64"));
    assert!(control.contains("Version: 2.0.0+deepin.test"));
    assert!(control.contains("libc6 (>= "));
    assert!(!control.contains("t64"));
}

#[test]
fn deepin_workflow_builds_the_unified_binary_on_bookworm() {
    let workflow =
        std::fs::read_to_string(repo_root().join(".github/workflows/linux-deb.yml")).unwrap();
    assert!(workflow.contains("push:\n    branches: [main]"));
    assert!(workflow.contains("image: debian:bookworm"));
    assert!(workflow.contains("cargo build --release -p codex-plus-manager --bin codex-plus-plus"));
    assert!(workflow.contains("cargo test -p codex-plus-core --test linux_package"));
    assert!(!repo_root().join(".github/workflows/pr-build.yml").exists());
    assert!(
        !repo_root()
            .join(".github/workflows/release-assets.yml")
            .exists()
    );
}
