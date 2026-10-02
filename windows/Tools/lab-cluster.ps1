# Doyah Studio · Windows 侧：起停「专用实验集群」（开发/自测用，不属于产品）
#
# 为什么有它：契约要求"主链要在真库上真跑一遍"，而用户现有那台 PostgreSQL 18（5432）
# 本机回环是 scram-sha-256、没有可用口令。本脚本起**另一台**独立集群（端口 5433、trust 认证、
# 数据目录在临时区）—— **不动用户现有那台**，也不改它的任何配置。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File Tools\lab-cluster.ps1 start|stop|status
#
# 数据目录：$env:DOYAH_LAB_DATA（缺省 D:\AIProjects\_tmp_face2\pglab\data）
# 端口：    $env:DOYAH_LAB_PORT（缺省 5433）· 用户 doyah · 库 doyah_lab（夹具见 start 的输出）

param(
  [Parameter(Position = 0)][ValidateSet('start', 'stop', 'status', 'fixtures')][string]$Action = 'status'
)

$ErrorActionPreference = 'Continue'
$PgBin = 'C:\Program Files\PostgreSQL\18\bin'
$Data = if ($env:DOYAH_LAB_DATA) { $env:DOYAH_LAB_DATA } else { 'D:\AIProjects\_tmp_face2\pglab\data' }
$Port = if ($env:DOYAH_LAB_PORT) { [int]$env:DOYAH_LAB_PORT } else { 5433 }
$Log = Join-Path (Split-Path $Data -Parent) 'server.log'
$PgCtl = Join-Path $PgBin 'pg_ctl.exe'
$Psql = Join-Path $PgBin 'psql.exe'

function Test-LabUp {
  (Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue) -eq $true
}

switch ($Action) {
  'status' {
    Write-Host ("实验集群 端口 {0} · 数据目录 {1}" -f $Port, $Data)
    if (Test-LabUp) { Write-Host '  状态：在听（可连）' } else { Write-Host '  状态：没在听（未起或已停）' }
  }
  'start' {
    if (-not (Test-Path (Join-Path $Data 'PG_VERSION'))) {
      Write-Host ("数据目录不存在或不是集群：{0}" -f $Data)
      Write-Host "  先造它：& '$PgBin\initdb.exe' -D '$Data' -U doyah -A trust -E UTF8"
      exit 2
    }
    if (Test-LabUp) { Write-Host '已在听，不重复起'; exit 0 }
    # 端口写进 postgresql.conf（幂等：已有就不再加）
    $conf = Join-Path $Data 'postgresql.conf'
    $text = Get-Content $conf -Raw
    if ($text -notmatch "(?m)^port\s*=\s*$Port") {
      Add-Content -Path $conf -Value "`nport = $Port`nlisten_addresses = '127.0.0.1'"
      Write-Host ("已把 port = {0} 写进 postgresql.conf" -f $Port)
    }
    & $PgCtl -D $Data -l $Log -w start | Out-Null
    if (Test-LabUp) {
      Write-Host ("✅ 实验集群已起：127.0.0.1:{0}（用户 doyah / 库 doyah_lab / trust 认证）" -f $Port)
      Write-Host "   真库端到端判据：`$env:DOYAH_LAB='1'; cargo test -p doyah-studio-shell --test live_lab"
    } else {
      Write-Host ("❌ 起不来，看日志：{0}" -f $Log); exit 1
    }
  }
  'stop' {
    & $PgCtl -D $Data -m fast stop | Out-Null
    Write-Host '已停'
  }
  'fixtures' {
    # 夹具：订单表引客户表，含 NULL（note 有三分之一是 NULL）与真实数值
    $sql = @'
CREATE SCHEMA IF NOT EXISTS app;
CREATE TABLE IF NOT EXISTS app.accounts (id serial PRIMARY KEY, name text NOT NULL, balance numeric(12,2) NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE IF NOT EXISTS app.orders (id serial PRIMARY KEY, account_id int NOT NULL REFERENCES app.accounts(id), sku text NOT NULL, qty int NOT NULL, note text);
INSERT INTO app.accounts (name, balance) SELECT 'user-' || g, g * 1.5 FROM generate_series(1, 50) g;
INSERT INTO app.orders (account_id, sku, qty, note) SELECT (g % 50) + 1, 'SKU-' || lpad(g::text, 4, '0'), (g % 7) + 1, CASE WHEN g % 3 = 0 THEN NULL ELSE 'note ' || g END FROM generate_series(1, 500) g;
'@
    & $Psql -h 127.0.0.1 -p $Port -U doyah -d doyah_lab -v ON_ERROR_STOP=1 -c $sql | Select-Object -Last 3
    Write-Host '夹具就位（app.accounts 50 行 / app.orders 500 行）'
  }
}
