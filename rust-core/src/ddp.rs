//! DDP 编解码（纯逻辑，无 NAPI 依赖——host 测试与 CI 直接覆盖）。
//! 与桌面版共用 vendor/moonviz-ddp：同一 .ddp 文件两端互通。
//! 入参/返回均为标准 base64（前端 btoa 语义）。

use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};

pub type DdpResult<T> = Result<T, String>;

/// MBT 源 → DDP 容器 base64。空密码走 DDP2 无密码模式（zstd+CRC）。
pub fn encrypt_b64(mbt: &str, password: &str) -> DdpResult<String> {
    let ddp = moonviz_ddp::encrypt_ddp(mbt, password)?;
    Ok(BASE64.encode(&ddp))
}

/// DDP 容器 base64 → MBT 源。口令不符/容器损坏返回 Err（消息即 codec 错误码）。
pub fn decrypt_b64(ddp_b64: &str, password: &str) -> DdpResult<String> {
    let bytes = BASE64
        .decode(ddp_b64.as_bytes())
        .map_err(|e| format!("ddp_transport_invalid_base64:{e}"))?;
    moonviz_ddp::decrypt_ddp(&bytes, password)
        .map(|s| s.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_with_password() {
        let mbt = "# Board\n\nhello 深设计 390x844";
        let ddp = encrypt_b64(mbt, "口令-123").unwrap();
        assert_eq!(decrypt_b64(&ddp, "口令-123").unwrap(), mbt);
    }

    #[test]
    fn roundtrip_no_password_ddp2() {
        let mbt = "# Board\n\nno-secret";
        let ddp = encrypt_b64(mbt, "").unwrap();
        assert_eq!(decrypt_b64(&ddp, "").unwrap(), mbt);
    }

    #[test]
    fn wrong_password_rejected() {
        let ddp = encrypt_b64("x", "right").unwrap();
        assert!(decrypt_b64(&ddp, "wrong").is_err());
    }

    #[test]
    fn large_doc_roundtrip() {
        let mbt = "# Board\n\n互通性验证".repeat(64);
        let ddp = encrypt_b64(&mbt, "p@ss").unwrap();
        assert_eq!(decrypt_b64(&ddp, "p@ss").unwrap(), mbt);
    }
}
