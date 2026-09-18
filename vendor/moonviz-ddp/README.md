# moonviz-ddp（vendored）

DDP 容器编解码 crate 的 vendored 副本。引擎预编译化（wasm SDK）后，Rust 侧
仅剩这一个引擎仓库组件，以源码副本形式入库，编译不再依赖兄弟目录 `../moonviz`。

- 上游：https://github.com/asdshuaishuai/moonviz 的 `ddp/` 目录（MIT）
- 同步基线：引擎仓库 commit `159f2318f1758929a1984a394e1b496b9495ce8a`
- 同步方式：`xcopy /e /i /y ..\moonviz\ddp\src vendor\moonviz-ddp\src` + 拷贝 `Cargo.toml`
- DDP1：Argon2id + XChaCha20-Poly1305（密码加密）；DDP2：zstd + CRC32（免密）

上游 API 变更时手动重同步，并重跑 `cd src-tauri && cargo test`（ddp 相关端到端
会真实走一遍加解密往返）。
