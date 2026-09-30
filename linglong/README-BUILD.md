# 玲珑打包说明（deepDesign Studio）

## 已产出（dist/ 目录）

| 文件 | 大小 | 说明 |
|------|------|------|
| `com.deepcode.deepdesign_0.4.0.0_x86_64_binary.layer` | 147MB | 玲珑应用层（erofs + linglong 头）|
| `com.deepcode.deepdesign_0.4.0.0_x86_64_develop.layer` | 2.7MB | develop 层 |
| `deepdesign-studio_0.4.0.0_amd64.deb` | 65.8MB | deb 包（/opt/apps 布局，可 ll-pica 转换/直接安装）|
| `deepDesign-Studio-0.4.0.0-x86_64.AppImage` | 82.6MB | 免安装 AppImage |

layer 安装：`ll-cli install com.deepcode.deepdesign_0.4.0.0_x86_64_binary.layer`，
运行：`ll-cli run com.deepcode.deepdesign`。

## 目录结构

- `linglong.yaml` —— 玲珑构建描述（linyaps 1.14 schema）
- `package/` —— 预构建产物（~235MB）：
  - `deepdesign-studio` —— release 二进制（deepin 25 / glibc 2.38 构建）
  - `frontend/` —— 纯静态前端 + moonviz.wasm 引擎
  - `lib/deepdesign/` —— WebKitGTK-4.1 全套运行库（约 190MB，随包携带，不依赖 runtime 层的 webkit）
  - `webkit-helpers/` —— WebKit 子进程 helper（WebProcess/NetworkProcess/GPUProcess/injected-bundle）+ bwrap/xdg-dbus-proxy
  - `redirect.so` —— LD_PRELOAD exec 路径重定向 shim（WebKit 硬编码 /usr helper 路径 → 随包目录）
  - `run.sh` —— 容器内启动脚本（装配 LD_LIBRARY_PATH/LD_PRELOAD/WEBKIT_INJECTED_BUNDLE_PATH）
  - desktop / metainfo / icon 入口文件

## 在正常 deepin 25 宿主机构建

```bash
cd linglong
./host-build.sh          # ll-builder build + export layer
```

构建容器内 build 段只做文件拷贝（无编译），需要网络拉取 base/runtime 层
（首次约 500MB）。

## deb → 玲珑 转换路径（ll-pica）

本包已验证可经官方工具 `ll-pica`（1.2.8）从 deb 转换：

```bash
mkdir -p /tmp/pica/package/com.deepcode.deepdesign/sources
cp dist/deepdesign-studio_0.4.0.0_amd64.deb /tmp/pica/package/com.deepcode.deepdesign/sources/
cd sources && dpkg-deb -x *.deb deepdesign-studio/   # pica 预期主 deb 预解包
cat > /tmp/pica/package.yaml << 'YAML'
runtime:
  version: 25.2.1
  base_version: 25.2.1
  source: https://ci.deepin.com/repo/deepin/deepin-community/stable
  distro_version: crimson/release
  arch: amd64
file:
  deb:
    - type: local
      id: com.deepcode.deepdesign
      name: deepdesign-studio
      ref: /tmp/pica/package/com.deepcode.deepdesign/sources/deepdesign-studio_0.4.0.0_amd64.deb
YAML
ll-pica convert -c /tmp/pica/package.yaml -w /tmp/pica --exportFile layer
ll-builder build && ll-builder export -z lz4 --layer
```

注意：deb 需满足 deepin appstore 规范——`/opt/apps/<id>/entries/`（desktop/icon）、
`/opt/apps/<id>/files/`（应用文件），且不放指向 /opt 的绝对路径符号链接（容器内悬空）。
`pica build` 的容器 entry 需 `--skip-output-check` 跳过运行时检查（嵌套环境无 session bus）。

## 运行时注意

1. WebKit 子进程 helper 的路径在 WebKitGTK 里是编译期硬编码（/usr/lib/.../webkit2gtk-4.1/），
   包内通过 `redirect.so`（LD_PRELOAD，hook execve/execvp/execvpe/posix_spawn）重定向到
   随包 `lib/deepdesign/webkit-helpers/`，无需写 /usr。
2. 前端依赖的 moonviz.wasm 已随包携带（package/frontend/vendor/）。
3. 若目标机器缺少 gstreamer 插件，播放类能力受限（非核心功能）。

## 本嵌套环境（玲珑容器内再构建）的已知限制

当前 ZCode 会话本身运行在玲珑容器内，无 root、无 apt。为在此环境试跑打包，
做了如下本地化处理（均在 ~/.local/opt/，不污染系统）：

- 用户级解压玲珑工具链（ll-builder 1.14.3 + box 2.3.4 + 依赖库）
- bwrap 桥接 `/usr/libexec/linglong`（builder helper 硬编码路径）
- 本地反代（ll-proxy.py）修 1.9.2 客户端与新仓库的字段名漂移（1.14 不需要）
- base/runtime 层本地化：org.deepin.{base,runtime}/25.2.2 binary+develop
  全部 complete（base 25.2.2.8 宿主既有 + runtime 为其本地别名）
- `ll-builder build --skip-run-container` 已跑通（exit 0）

嵌套环境最后一关：build 容器内 entry 脚本 exec 报 E2BIG
（fuse-overlayfs 1.7.1 在嵌套 userns + FUSE rootfs 上的深层兼容问题，
正常宿主不经过嵌套路径，不会触发）。因此在正常宿主机上执行 host-build.sh 即可出包。

## 主题修复附带产物

`frontend/index.html` 含本次 Linux 主题色/文本色冲突修复（color-scheme 锁定、
caret/selection 接管、跟随系统深浅色、win11 深色面板补齐），已随包进入产物。
