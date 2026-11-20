# 上传到 GitHub

仓库已初始化并提交（3 个提交，含完整历史）。两条路，任选：

## A. 你自己推（推荐，不需要把 token 给我）

```bash
cd NetCove
git remote add origin https://github.com/<你的用户名>/netcove.git
git push -u origin main
```

或一条命令（会自动建私有仓库）：

```bash
scripts/push_to_github.sh <你的用户名>/netcove      # 需要先 gh auth login
```

## B. 用离线 bundle（没有网络/GitHub 授权时）

`NetCove-repo.bundle` 含全部提交历史：

```bash
git clone NetCove-repo.bundle netcove
cd netcove && git remote set-url origin https://github.com/<你>/netcove.git
git push -u origin main
```

## C. 让我代推

把 **fine-grained PAT**（仅 `Contents: Read/Write` + `Administration: Read/Write`，限定 30 天）发我，
我执行 `scripts/push_to_github.sh <owner>/<repo> <TOKEN>`。
⚠️ token 会出现在本次会话记录里，用完请立刻在 GitHub 撤销。

## 推上去之后：CI 会替你构建 ipa

`.github/workflows/build.yml` 有两个 job，跑在 **macos-14** runner 上：

| job | 做什么 | 产物 |
|---|---|---|
| `test` | 静态自检 + `xcodegen` + `xcodebuild test`（模拟器，免签名） | `build-log` |
| `unsigned-ipa` | `xcodebuild archive` → `Payload/` → zip | **`NetCove-unsigned.ipa`** |

触发方式：推送代码，或在 Actions 页面点 **Run workflow**。构建完成后在 run 页面的 Artifacts 里下载。

### 关于这个 ipa

- 它是**无签名**的，`xcodebuild` 用 `CODE_SIGNING_ALLOWED=NO` 打出来
- 装上手机需要你自己签：**AltStore / Sideloadly / Xcode 免费描述文件**，用你的 Apple ID
- 想直接装（不折腾签名）就走 Mac 本地：`scripts/release.sh <TEAM_ID>`，用你的开发者证书签

### 首次 CI 可能失败的地方（先知道，别慌）

1. **SPM 依赖解析**：`KSPlayer` / `WCDB` / `AMSMB2` 的版本号或包名可能与我写的不完全一致，改 `project.yml` 的 `from:` 即可
2. **编译错误**：这套代码从未真正编译过（本机无 Xcode），CI 第一次跑会暴露具体文件与行号
3. 需要的话可以先只跑 `test` job，把编译修绿之后再跑 `unsigned-ipa`
