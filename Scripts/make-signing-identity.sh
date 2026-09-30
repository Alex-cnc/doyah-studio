#!/bin/bash
set -euo pipefail

# 建一个**自签名代码签名身份**，治 `Q53`：
#
#   ad-hoc 签名 ⇒ 每次重打包换指纹 ⇒ macOS「本地网络」授权对不上新包
#   （症状：应用连不上 217 的库，而终端里 `psql` 正常）。
#
# 有了稳定身份，授权只授一次；之后重打包既不弹密码、也不掉本地网络授权。
#
#   ./Scripts/make-signing-identity.sh
#
# 身份名默认 `DoyahStudio Local Dev`；**必须与 `build-app.sh` 用的那个一致**
# （`build-app.sh` 读同一个环境变量 `DOYAH_CODESIGN_IDENTITY`）：
#
#   DOYAH_CODESIGN_IDENTITY="Developer ID Application: …" ./Scripts/make-signing-identity.sh
#
# **为什么要你输一次密码**：`security set-key-partition-list` 要改私钥的授权列表，
# 按设计必须由钥匙串密码授权。输完之后 `codesign` 不再弹窗 —— 所以助理之后可以
# 替你反复构建、跑判据。密码只在本地读（`read -s`：不回显、不进 shell 历史）。
# **不要把密码贴进对话。**
#
# **幂等**：同名身份已存在就直接退出 —— **重建会换指纹，TCC 授权又要重授一次**。
#
# 产物：登录钥匙串里一个「代码签名」身份（私钥 + 自签证书）；全程不走网络、不上传。

IDENTITY="${DOYAH_CODESIGN_IDENTITY:-DoyahStudio Local Dev}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
DAYS=3650

echo "==> 目标身份：「${IDENTITY}」"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "${IDENTITY}"; then
  echo "    已存在同名可用身份 —— 什么都不做。"
  security find-identity -v -p codesigning 2>/dev/null | grep -F "${IDENTITY}" | sed 's/^/    /'
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT   # 私钥只在临时目录里活一次，退出即删

P12_PASS="$(openssl rand -hex 16)"   # 只用于 p12 一次性搬运，随即可弃

# 用配置文件写扩展，而不是 `-addext`：系统自带 /usr/bin/openssl 是 LibreSSL，不认 `-addext`。
cat > "${WORK}/openssl.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = codesign
[dn]
CN = ${IDENTITY}
O = DoyahStudio
C = CN
[codesign]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "==> 生成自签名证书（代码签名 EKU · ${DAYS} 天）"
openssl req -x509 -newkey rsa:2048 -sha256 -days "${DAYS}" -nodes \
  -keyout "${WORK}/identity.key" -out "${WORK}/identity.crt" \
  -config "${WORK}/openssl.cnf" 2>/dev/null

# macOS 的 `security import` 只认**老的** PKCS#12 算法（3DES/RC2 + SHA-1 MAC）。
# OpenSSL 3.x 默认出 AES-256 + SHA-256 MAC ⇒ 实测报
#   「MAC verification failed during PKCS12 import (wrong password?)」
# —— 那不是密码错。`-legacy` 让 OpenSSL 3.x 回到老算法；LibreSSL / 老 OpenSSL
# 本来就是老算法、不认 `-legacy`，所以失败就退回不带开关的那一次（两条路都实测可被 security 读入）。
if ! openssl pkcs12 -export -inkey "${WORK}/identity.key" -in "${WORK}/identity.crt" \
  -out "${WORK}/identity.p12" -passout "pass:${P12_PASS}" -name "${IDENTITY}" \
  -legacy 2>/dev/null; then
  openssl pkcs12 -export -inkey "${WORK}/identity.key" -in "${WORK}/identity.crt" \
    -out "${WORK}/identity.p12" -passout "pass:${P12_PASS}" -name "${IDENTITY}"
fi

echo "==> 导入登录钥匙串（只授权给 /usr/bin/codesign；**不用 -A** —— 它会被任何应用静默取用）"
if ! security import "${WORK}/identity.p12" -k "${KEYCHAIN}" -P "${P12_PASS}" \
  -T /usr/bin/codesign >/dev/null 2>&1; then
  P12_PASS=""
  echo ""
  echo "⚠ 导入失败。如果是「MAC verification failed (wrong password?)」—— 那不是密码问题，"
  echo "   是 p12 算法与 macOS 不匹配（OpenSSL 3.x 默认 AES-256/SHA-256，macOS 只认 3DES/RC2 + SHA-1）。"
  echo "   本脚本已用 -legacy 处理过；仍失败就用 GUI 建：钥匙串访问 → 证书助理 → 创建证书…"
  echo "   （身份类型「自签名根证书」+ 证书类型「代码签名」+ 名称「${IDENTITY}」）。"
  exit 1
fi
P12_PASS=""

echo "==> 授权 codesign 使用该私钥（下面输一次登录钥匙串密码，不回显）"
printf '    登录钥匙串密码：' >&2
read -r -s KEYCHAIN_PASSWORD
printf '\n' >&2
if ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" >/dev/null 2>&1; then
  unset KEYCHAIN_PASSWORD
  echo ""
  echo "⚠ 授权没成功（密码不对，或该机器要求走 GUI）。两条退路："
  echo "    1) 重跑本脚本、把密码输对；或"
  echo "    2) 改用 GUI：钥匙串访问 → 证书助理 → 创建证书…"
  echo "       （身份类型「自签名根证书」+ 证书类型「代码签名」+ 名称「${IDENTITY}」），"
  echo "       再让 codesign 首次签名时弹窗点「始终允许」。"
  exit 1
fi
unset KEYCHAIN_PASSWORD

echo ""
# **判存在性不能靠 `security find-identity`**：它只列「被信任的」身份，而自签名证书未信任时
# 实测恒报 `0 valid identities found` —— 拿它当判据会把装好的身份误判成没装。
# 判据改成**真签一次**：签一个临时二进制，走的就是 build-app.sh 后面要走的那条路。
echo "==> 自检：用这个身份真签一个临时二进制（确认 codesign 不会再要授权）"
cp /bin/echo "${WORK}/signtest"
if codesign --force --sign "${IDENTITY}" "${WORK}/signtest" >/dev/null 2>&1; then
  echo "✅ 身份已就位，codesign 无需再授权。"
  echo "   证书 SHA-1：$(security find-certificate -c "${IDENTITY}" -Z "${KEYCHAIN}" 2>/dev/null | awk '/SHA-1 hash/{print $NF}' | head -1)"
  echo ""
  echo "下一步："
  echo "    1) ./Scripts/build-app.sh        # 用这个身份签名"
  echo "    2) 首次启动后，到「系统设置 → 隐私与安全性 → 本地网络」再允许一次"
  echo "       （签名换代，旧授权必然对不上；这是唯一一次）"
  echo "    以后重打包：不弹密码、不掉本地网络授权。"
  echo ""
  echo "注意：不要删掉、不要重建、不要让它过期（${DAYS} 天）—— 换了证书，授权会再次对不上。"
  echo "    附：「security find-identity -v -p codesigning」对本身份报 0 是正常的（它只列被信任的），"
  echo "    不等于身份不可用 —— 以本自检为准。"
else
  echo "❌ 自检签名失败：身份没装上，或 codesign 需要授权却拿不到。"
  echo "   退路 1：重跑本脚本（把钥匙串密码输对）。"
  echo "   退路 2：GUI 建证书 —— 钥匙串访问 → 证书助理 → 创建证书…"
  echo "           （身份类型「自签名根证书」+ 证书类型「代码签名」+ 名称「${IDENTITY}」）。"
  exit 1
fi
