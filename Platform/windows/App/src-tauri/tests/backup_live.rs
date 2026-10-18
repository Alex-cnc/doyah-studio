//! **真 `pg_dump` 子进程**的端到端判据（Windows 侧 · `FR-IO-04`）。
//!
//! 跑法：设 `DOYAH_BACKUP_LIVE=1` 时启用；没设就**跳过并说明**（跳过不是通过）。
//!
//! 为什么还要这一层：`backup.rs` 的单测用 `cmd` 起子进程，证明了「抓输出 / 退出码 / 日志尾部」
//! 这条管子通；但**真 `pg_dump`** 的脾气只有它自己能告诉我们（参数名、失败文案、退出码）。
//! 这里做两件真事：
//!   ① 找得到 `pg_dump` ⇒ 拿它自己的 `--version` 说话（**程序发现那一步是活的**）；
//!   ② 按本模块拼出来的参数表，对着一个**没有服务的端口**真跑一次 ⇒ 必须失败、且回执里
//!      带的是 `pg_dump` 的原话（不是我们编的一句话）；同时证明**没有生成任何文件**
//!      （失败不留半截产物 —— 这是备份最容易出的那种"看起来成功"）。
//!
//! 成功路径要一台真库（本机实验集群 5433 起没起由 `DOYAH_LAB` 那套管），本文件不假装跑过。

use std::path::PathBuf;

use doyah_studio_shell::backup::{self, BackupFormat, BackupPlan, BackupTarget};

fn enabled() -> bool {
    std::env::var("DOYAH_BACKUP_LIVE").ok().as_deref() == Some("1")
}

#[test]
fn the_real_pg_dump_is_found_and_reports_its_own_version() {
    if !enabled() {
        eprintln!("跳过：未设 DOYAH_BACKUP_LIVE=1（本用例要真起一次本机 pg_dump）");
        return;
    }
    let program = backup::find_program(None).expect("本机应当能找到 pg_dump（装了客户端就找得到）");
    assert!(program.is_file(), "{}", program.display());

    // 用 `--version` 走一遍**同一个** run 通道（参数表换成版本查询）
    let plan = BackupPlan {
        program: Some(program),
        args: vec!["--version".to_string()],
        target: PathBuf::from("unused"),
        format: BackupFormat::Plain,
        database: "unused".to_string(),
    };
    let report = backup::run(&plan, None, None).expect("--version 应当成功");
    assert_eq!(report.exit_code, Some(0));
    assert!(
        report.log.to_lowercase().contains("pg_dump"),
        "--version 的原话里应当有 pg_dump：{}",
        report.log
    );
}

#[test]
fn a_closed_port_fails_with_pg_dumps_own_words_and_leaves_no_file() {
    if !enabled() {
        eprintln!("跳过：未设 DOYAH_BACKUP_LIVE=1（本用例要真起一次本机 pg_dump）");
        return;
    }
    let Ok(program) = backup::find_program(None) else {
        eprintln!("跳过：本机没有 pg_dump");
        return;
    };
    // 目标放在临时目录里，跑完要能确认「一个字节都没写」
    let dir = std::env::temp_dir().join(format!("doyah-backup-live-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("建临时目录");
    let target = dir.join("never.dump");
    let target_text = target.display().to_string();

    let target_spec = BackupTarget {
        host: "127.0.0.1".to_string(),
        // 5999 上没有服务（本机实验集群是 5433）
        port: 5999,
        user: "doyah".to_string(),
        database: "doyah_lab".to_string(),
    };
    let checked = backup::check_target(&target_text, BackupFormat::Custom).expect("新路径应当放行");
    let plan = BackupPlan {
        program: Some(program),
        args: backup::plan_args(&target_spec, &target_text, BackupFormat::Custom),
        target: checked,
        format: BackupFormat::Custom,
        database: target_spec.database.clone(),
    };
    let failure = backup::run(&plan, None, None).expect_err("连不上就必须失败");

    // 回执里要有 pg_dump 的原话（不是我们编的「备份失败」）
    assert!(
        failure.message.contains("pg_dump"),
        "回执应当点名 pg_dump：{}",
        failure.message
    );
    assert!(
        failure.message.contains("退出码"),
        "回执应当带退出码：{}",
        failure.message
    );
    assert!(
        failure.message.contains("127.0.0.1") || failure.message.to_lowercase().contains("connect"),
        "回执应当带子进程的原话（连不上哪儿）：{}",
        failure.message
    );
    // 失败**不留半截产物**
    assert!(!target.exists(), "失败时不许留下 {}（半截备份最危险）", target.display());
    let _ = std::fs::remove_dir_all(&dir);
}
