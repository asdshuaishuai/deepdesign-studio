//! 模型元数据快照（vendored models.dev 裁剪子集）
//!
//! 事实源是 `models.json`，由 `scripts/sync-models.mjs` 从 https://models.dev/api.json
//! 裁剪生成（仅覆盖 `frontend/index.html` PROVIDERS 涉及的 11 个提供商）。
//! 全量 4.7MB / 221 提供商，本快照 ~48KB——桌面应用离线可用 + 依赖极简。
//!
//! **数据性质（见 docs/research/models-dev-ai-sdk.md）**：models.dev 记**能力轴**
//! （`reasoning_options` 的 toggle/effort 档位），**不含线上字段方言**——
//! 全库无 `thinking`/`reasoning_effort`/`chat_template_kwargs`。请求体的字节
//! 仍由 `agent.rs::thinking_extra_body` 方言表编译（以官方文档为准），本快照只做
//! 发现与漂移对账。契约测试 `presets_match_snapshot` 把这条链锁死。

use serde_json::Value;

/// 端点比对归一：忽略尾部 `/v1`（Anthropic SDK 自行追加 `/v1/messages`，
/// models.dev 把带 /v1 的基址记进 api 字段——路径约定差异而非语义差异）。
/// 按预设 URL 推断我们走的协议族（与 agent.rs::protocol_for 同规则）。
#[cfg(test)]
fn our_family(base_url: &str) -> &'static str {
    let b = base_url.to_ascii_lowercase();
    let t = b.trim_end_matches('/');
    let host = t.split("://").nth(1).unwrap_or("").split('/').next().unwrap_or("");
    if host == "api.anthropic.com" || t.ends_with("/anthropic") || t.ends_with("/anthropic/v1") {
        "@ai-sdk/anthropic"
    } else {
        "@ai-sdk/openai-compatible"
    }
}

/// 已知协议族分歧：快照 npm 家族与我们预设 URL 推断的不一致、且**不改线**的项。
/// 规则（本文件的承诺）：协议族变化意味着请求体改造（Messages vs Chat Completions），
/// 不是改 URL 的事——必须人工裁决。三条全是"快照说 anthropic、我们仍是 OpenAI wire"，
/// 切换需请求体层逐模型验证，暂留。
#[cfg(test)]
const KNOWN_FAMILY_DIVERGENCES: [(&str, &str); 2] = [
    ("minimax", "快照 minimax-cn npm=@ai-sdk/anthropic；本预设仍是 OpenAI 兼容 /v1——双协议支持已落地，用户可切同 id 的 Anthropic 预设"),
    ("minimax-intl", "快照 minimax npm=@ai-sdk/anthropic；同上"),
];

#[cfg(test)]
fn strip_v1(u: &str) -> &str {
    let t = u.trim_end_matches('/');
    t.strip_suffix("/v1").unwrap_or(t)
}
#[cfg(test)]
use serde_json::json; // 仅测试代码使用（build 与 test 对 use 的可见性不同，条件导入避免误报）

/// vendored 快照（source / license / fetched_at / providers）。
pub const SNAPSHOT_JSON: &str = include_str!("../models.json");

/// 顶层 providers 表。快照损坏（非法 JSON / 缺 providers）会在任何使用前 panic——
/// 这是有意的：模型快照不是可降级的运行时数据，坏就应该是响亮失败。
pub fn providers() -> &'static Value {
    static PARSED: std::sync::OnceLock<Value> = std::sync::OnceLock::new();
    PARSED.get_or_init(|| {
        let doc: Value = serde_json::from_str(SNAPSHOT_JSON)
            .expect("models.json 不是合法 JSON（快照被改坏了？）");
        doc.get("providers")
            .cloned()
            .expect("models.json 缺 providers 字段")
    })
}

/// models.dev 提供商 id → 官方 base URL（快照记录值）。
pub fn provider_endpoint(id: &str) -> Option<&'static str> {
    providers()
        .get(id)
        .and_then(|p| p.get("api"))
        .and_then(|v| v.as_str())
}

/// 该提供商下全部模型 id（快照记录）。
pub fn provider_models(id: &str) -> Vec<&'static str> {
    providers()
        .get(id)
        .and_then(|p| p.get("models"))
        .and_then(|m| m.as_object())
        .map(|m| m.keys().map(|k| k.as_str()).collect())
        .unwrap_or_default()
}

/// frontend PROVIDERS 键 → models.dev 提供商 id（前端经 model_registry 命令消费）。
pub const PRESET_PROVIDER_MAP: [(&str, &str); 13] = [
    ("deepseek", "deepseek"),
    ("glm", "zhipuai"),
    ("glm-coding", "zhipuai-coding-plan"),
    ("zai", "zai"),
    ("zai-coding", "zai-coding-plan"),
    ("kimi", "moonshotai-cn"),
    ("kimi-plan", "kimi-code-plan-cn"), // 上游把 kimi-for-coding 拆成 global/cn 两条
    ("minimax", "minimax-cn"),
    ("minimax-intl", "minimax"),
    // Anthropic Messages 双协议端点（官方推荐路径；同一个 models.dev 提供商）
    ("minimax-anthropic", "minimax-cn"),
    ("minimax-anthropic-intl", "minimax"),
    ("stepfun", "stepfun"),
    ("stepfun-plan", "stepfun-step-plan"),
];

/// 完整快照文档（含 source/fetched_at/providers），供 Tauri 命令下发给前端。
pub fn snapshot_document() -> &'static Value {
    static DOC: std::sync::OnceLock<Value> = std::sync::OnceLock::new();
    DOC.get_or_init(|| {
        serde_json::from_str(SNAPSHOT_JSON).expect("models.json 不是合法 JSON")
    })
}

/// 某模型的能力轴（reasoning_options 原样返回，None 表示快照未记录）。
pub fn model_reasoning_options(provider: &str, model: &str) -> Option<&'static Value> {
    providers()
        .get(provider)
        .and_then(|p| p.get("models"))
        .and_then(|m| m.get(model))
        .and_then(|m| m.get("reasoning_options"))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 复用导出的映射（单一来源，防两处漂移）。
    fn provider_map() -> &'static [(&'static str, &'static str)] {
        &PRESET_PROVIDER_MAP
    }

    /// 端点漂移白名单：models.dev 记录值与前端预设不一致、且**不自动跟随**的项。
    /// 每条须带 models.dev 当前值（变了就红，逼重新裁决）与理由。
    /// 裁决规则：协议族变化（openai-compatible → anthropic）意味着请求体格式要改
    /// （Messages API vs Chat Completions），不是改 URL 的事，必须人工核实后再动预设。
    const KNOWN_DIVERGENCES: [(&str, &str, &str); 2] = [
        (
            "minimax",
            "https://api.minimaxi.com/anthropic/v1",
            "MiniMax 官方同时提供 OpenAI 兼容(/v1)与 Anthropic 兼容(/anthropic)双协议且推荐后者；\
             切换需改请求体格式，非 URL 之改。且 models.dev 的 CN 值本身把域名与 /v1 混拼\
             （官方 CN Anthropic 基址为 api.minimaxi.com/anthropic），需人工核实后再决",
        ),
        (
            "minimax-intl",
            "https://api.minimax.io/anthropic/v1",
            "MiniMax 官方推荐 Anthropic 兼容路径（prompt cache 等优势）；本仓库仍是 \
             OpenAI 兼容预设，切换需请求体改造，暂留分歧",
        ),
    ];

    /// 从 frontend/index.html 解析 PROVIDERS 行（零依赖手写解析：
    /// 锚定 `baseUrl:'…'` 与 `model:'…'` 紧邻书写形式，提取同行的键）。
    /// PROVIDERS 表是契约的一部分，写法若变（比如换 JSON 结构），这里解析为空、
    /// `presets_match_snapshot` 立即红，不会静默放过。
    /// 从 frontend/index.html 解析 PROVIDERS 预设表。
    /// **锚定 `const PROVIDERS={` 块（花括号配平找块尾）**——不扫全文件：
    /// 全文件扫描时 `let agentConfig={baseUrl:'',…}`、`saveSettings` 等同形行会被
    /// 误当预设，此前只靠"键必须全小写"这一巧合挡掉；一旦有人把 agentConfig
    /// 改成小写，presets_match_snapshot 就会为无关原因变红。锚定后块外行
    /// 天然不入解析，块内键非法则直接 fail loud。
    fn frontend_presets() -> Vec<(String, String, String)> {
        let html = include_str!("../../frontend/index.html");
        let anchor = "const PROVIDERS={";
        let start = html
            .find(anchor)
            .unwrap_or_else(|| panic!("前端未找到 `{anchor}`——预设表写法变了，请同步本解析"))
            + anchor.len();
        // 花括号配平定位块尾
        let mut depth = 1usize;
        let mut end = html.len();
        for (i, c) in html[start..].char_indices() {
            match c {
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        end = start + i;
                        break;
                    }
                }
                _ => {}
            }
        }
        let block = &html[start..end];
        let mut out = Vec::new();
        for line in block.lines() {
            let l = line.trim();
            if !l.contains("baseUrl:") || !l.contains("model:") {
                continue;
            }
            let key_end = l.find(':').unwrap_or(0);
            let key = l[..key_end].trim().trim_matches('\'').to_string();
            let base = between(l, "baseUrl:'", "'");
            let model = between(l, "model:'", "'");
            if let (Some(base), Some(model)) = (base, model) {
                assert!(
                    !key.is_empty() && key.chars().all(|c| c.is_ascii_lowercase() || c == '-'),
                    "PROVIDERS 块内条目键非法：{key:?}（应为 kebab-case）"
                );
                out.push((key, base.to_string(), model.to_string()));
            }
        }
        out
    }

    /// 从 frontend/index.html 解析 MINIMAX_STATIC_MODELS 数组。
    fn frontend_minimax_models() -> Vec<String> {
        let html = include_str!("../../frontend/index.html");
        let start = match html.find("MINIMAX_STATIC_MODELS=[") {
            Some(i) => i,
            None => return Vec::new(),
        };
        let end = html[start..].find(']').map(|i| start + i).unwrap_or(html.len());
        html[start..end]
            .split('\'')
            .skip(1)
            .step_by(2)
            .map(str::to_string)
            .collect()
    }

    fn between<'a>(s: &'a str, open: &str, close: &str) -> Option<&'a str> {
        let i = s.find(open)? + open.len();
        let j = s[i..].find(close)? + i;
        Some(&s[i..j])
    }

    /// 协议族判定等价（审查四-③）：本文件的测试副本 `our_family` 与 agent.rs 的唯一
    /// 运行时实现 `protocol_for` 必须对同一 URL 给出同一结论——两者现在逻辑同构，
    /// 这条测试保证将来任何一边单改判定规则（尾部段/host 比对）都会红。
    #[test]
    fn our_family_matches_agent_protocol_for() {
        use crate::agent::Protocol;
        let mut urls: Vec<String> = frontend_presets()
            .into_iter()
            .map(|(_, base, _)| base)
            .collect();
        // 已知分歧登记的上游现值也是未来切协议的候选 URL，一并钉住
        for (_, url, _) in KNOWN_DIVERGENCES {
            urls.push(url.to_string());
        }
        urls.extend([
            "https://api.anthropic.com".to_string(),
            "https://api.anthropic.com/v1".to_string(),
            "https://api.minimaxi.com/anthropic".to_string(),
            "https://api.minimax.io/anthropic/v1".to_string(),
            "https://api.minimaxi.com/anthropic/v1/".to_string(),
            // 代理路径不得误判为 Anthropic
            "https://x.example.com/anthropic-proxy/v1".to_string(),
            // 前缀伪装不得误判
            "https://api.anthropic.com.evil.net/v1".to_string(),
            "http://localhost:8000/v1".to_string(),
            "https://api.deepseek.com".to_string(),
        ]);
        for u in &urls {
            let our = our_family(u) == "@ai-sdk/anthropic";
            let theirs = crate::agent::protocol_for(u) == Protocol::Anthropic;
            assert_eq!(
                our, theirs,
                "协议族判定分叉：{u} → our_family={} protocol_for={:?}",
                our_family(u),
                crate::agent::protocol_for(u)
            );
        }
    }

    #[test]
    fn presets_match_snapshot() {
        let presets = frontend_presets();
        assert_eq!(
            presets.len(),
            provider_map().len(),
            "frontend PROVIDERS 条目数({})与 PRESET_PROVIDER_MAP({})不一致——加预设两端都要改",
            presets.len(),
            PRESET_PROVIDER_MAP.len()
        );

        let mut divergence_hits: Vec<String> = Vec::new();
        for (key, base_url, model) in &presets {
            let Some(md_id) = provider_map().iter().find(|(k, _)| k == key).map(|(_, v)| *v) else {
                panic!("frontend 预设 `{key}` 没有 models.dev 映射——请更新 PRESET_PROVIDER_MAP");
            };

            // 1) 快照里该提供商必须存在
            let md_api = provider_endpoint(md_id)
                .unwrap_or_else(|| panic!("快照缺提供商 {md_id}（上游改名？同步 PROVIDER_MAP）"));

            // 2) 端点一致（忽略 /v1 路径约定差异——Anthropic SDK 自行追加
            //    /v1/messages，models.dev 把带 /v1 的基址记进 api 字段，
            //    这不是语义差异），或在已知分歧白名单内（且记录值与快照当前值
            //    一致——上游再漂移必须回来重新裁决，不能静默放过）
            if strip_v1(md_api) != strip_v1(base_url.as_str()) {
                divergence_hits.push(key.clone());
                let div = KNOWN_DIVERGENCES.iter().find(|(k, _, _)| k == key);
                match div {
                    Some((_, recorded, reason)) => {
                        assert_eq!(
                            md_api, *recorded,
                            "`{key}` 的 models.dev 值又变了：记录 {recorded}，现值 {md_api}——\
                             重新裁决并更新 KNOWN_DIVERGENCES"
                        );
                        assert!(!reason.is_empty(), "`{key}` 分歧缺少理由");
                    }
                    None => panic!(
                        "预设 `{key}` 端点漂移未被记录：\n  前端 {base_url}\n  models.dev {md_api}\n\
                         核查官方文档后：改预设，或加 KNOWN_DIVERGENCES（带理由）"
                    ),
                }
            }

            // 2.5) 协议族比对：快照 npm 字段（@ai-sdk/anthropic vs openai-compatible）
            // 与我们按 URL 推断的家族不一致时必须登记——否则"URL 没漂移但线上
            // 协议已换"完全隐形（kimi-plan 就是这样：端点一致、家族已变）。
            let md_npm = providers()
                .get(md_id)
                .and_then(|p| p.get("npm"))
                .and_then(|v| v.as_str())
                .unwrap_or("");
            let ours = our_family(base_url);
            if !md_npm.is_empty() && md_npm != ours {
                let fam = KNOWN_FAMILY_DIVERGENCES.iter().find(|(k, _)| k == key);
                match fam {
                    Some((_, reason)) => assert!(!reason.is_empty(), "`{key}` 家族分歧缺少理由"),
                    None => panic!(
                        "预设 `{key}` 协议族漂移未被记录：\n  我们按 URL 推断 {ours}\n  models.dev npm {md_npm}\n\
                         核查官方文档后：改预设协议（涉及请求体改造），或加 KNOWN_FAMILY_DIVERGENCES（带理由）"
                    ),
                }
            }

            let models = provider_models(md_id);
            assert!(
                models.iter().any(|m| *m == model),
                "预设 `{key}` 的默认模型 {model} 不在 {md_id} 的快照模型清单里\n  \
                 快照内含：{:?}\n核查后改预设或重跑 scripts/sync-models.mjs",
                &models[..models.len().min(10)]
            );
        }
        // 反向对账：每个 KNOWN_DIVERGENCES 条目都必须真的命中——
        // 预设若与快照重新对齐而白名单没清，死条目静默失守（镜像 UI_EXTRAS 的双向设计）
        for (k, _, _) in KNOWN_DIVERGENCES {
            assert!(
                divergence_hits.iter().any(|h| h == k),
                "KNOWN_DIVERGENCES 里的 `{k}` 已与快照对齐（漂移消失）——请移除该条目"
            );
        }
        assert_eq!(
            divergence_hits.len(),
            KNOWN_DIVERGENCES.len(),
            "漂移条目数与白名单不一致——两边必须一起维护"
        );
    }

    /// UI 静态清单里、快照暂缺但官方文档确认存在的模型（models.dev 社区数据滞后）。
    /// 双向断言：快照一旦收录该项，白名单就过期，测试红逼你清理。
    const KNOWN_UI_EXTRAS: [(&str, &str); 1] = [(
        "MiniMax-M2.1-highspeed",
        "官方文档确认存在（M2.1 highspeed, 204K ctx）；models.dev 快照滞后未收录",
    )];

    #[test]
    fn minimax_static_models_in_snapshot() {
        let ui_models = frontend_minimax_models();
        assert!(!ui_models.is_empty(), "MINIMAX_STATIC_MODELS 解析为空（前端写法变了？）");
        for m in &ui_models {
            let in_cn = provider_models("minimax-cn").iter().any(|x| *x == m);
            let in_intl = provider_models("minimax").iter().any(|x| *x == m);
            if in_cn || in_intl {
                // 快照已收录 → 若它同时还在额外清单里，说明白名单过期了
                if let Some((_, reason)) = KNOWN_UI_EXTRAS.iter().find(|(k, _)| k == m) {
                    panic!("快照已收录 {m}——把 KNOWN_UI_EXTRAS 里的条目移除（原理由：{reason}）");
                }
            } else {
                let extra = KNOWN_UI_EXTRAS.iter().find(|(k, _)| k == m);
                match extra {
                    Some((_, reason)) => assert!(!reason.is_empty(), "{m} 缺少理由"),
                    None => panic!(
                        "MINIMAX_STATIC_MODELS 里的 {m} 在 minimax-cn / minimax 快照中都不存在，\
                         也未登记为快照滞后项——核查官方文档后：删 UI 条目，或加 KNOWN_UI_EXTRAS（带理由）"
                    ),
                }
            }
        }
    }

    #[test]
    fn snapshot_structure_is_healthy() {
        let p = providers();
        assert!(p.is_object(), "providers 不是对象");
        let total: usize = p
            .as_object()
            .unwrap()
            .values()
            .map(|prov| prov.get("models").and_then(|m| m.as_object()).map(|m| m.len()).unwrap_or(0))
            .sum();
        assert!(total >= 60, "快照模型总数 {total} 低于 60——sync 脚本裁剪逻辑坏了？");

        for (pid, prov) in p.as_object().unwrap() {
            let api = prov.get("api").and_then(|v| v.as_str()).unwrap_or("");
            assert!(api.starts_with("http"), "提供商 {pid} 的 api 非法：{api}");
            assert!(
                prov.get("npm").and_then(|v| v.as_str()).is_some_and(|n| n.starts_with("@ai-sdk/")),
                "提供商 {pid} 缺 @ai-sdk/* 协议族标记（npm 字段）——上游 schema 变了"
            );
            for (mid, m) in prov.get("models").and_then(|m| m.as_object()).into_iter().flatten() {
                assert!(m.get("reasoning").is_some_and(|v| v.is_boolean()), "{pid}/{mid} 缺 reasoning 布尔");
                assert!(m.get("tool_call").is_some_and(|v| v.is_boolean()), "{pid}/{mid} 缺 tool_call 布尔");
                let reasoning = m.get("reasoning").and_then(|v| v.as_bool()).unwrap_or(false);
                if m.get("reasoning_options").is_some() {
                    assert!(reasoning, "{pid}/{mid} 有 reasoning_options 但 reasoning=false（schema 自相矛盾）");
                }
            }
        }
    }

    #[test]
    fn registry_command_payload_is_complete() {
        // 前端拿到的 payload：providers（快照）+ provider_map（预设键→models.dev id）
        let doc = snapshot_document();
        assert_eq!(doc.get("providers").and_then(|p| p.as_object()).map(|m| m.len()), Some(11));
        let map: serde_json::Map<String, Value> = PRESET_PROVIDER_MAP
            .iter()
            .map(|(k, v)| ((*k).to_string(), json!((*v))))
            .collect();
        assert_eq!(map.len(), 13);
        // 映射的每个 models.dev id 必须在快照里有
        for v in map.values() {
            let id = v.as_str().unwrap();
            assert!(provider_endpoint(id).is_some(), "provider_map 的 {id} 不在快照中");
        }
        // 快照里每个 provider 都应有模型
        for id in map.values().map(|v| v.as_str().unwrap()) {
            assert!(!provider_models(id).is_empty(), "{id} 模型清单为空");
        }
    }

    #[test]
    fn snapshot_has_provenance() {
        let doc: Value = serde_json::from_str(SNAPSHOT_JSON).unwrap();
        let fetched = doc.get("fetched_at").and_then(|v| v.as_str()).unwrap_or("");
        assert!(
            fetched.len() == 10 && fetched.as_bytes()[4] == b'-',
            "fetched_at 非法：{fetched}（应为 YYYY-MM-DD；重跑 scripts/sync-models.mjs）"
        );
        assert_eq!(
            doc.get("source").and_then(|v| v.as_str()),
            Some("https://models.dev/api.json"),
            "快照 source 变了——注明新来源"
        );
    }
}
