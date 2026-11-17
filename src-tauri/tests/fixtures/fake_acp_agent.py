#!/usr/bin/env python3
"""假 ACP agent 测试夹具：讲最小 ACP 协议（newline-delimited JSON-RPC over stdio）。

时序：initialize / session/new 应答 → 收到 session/prompt 后依次发
agent_thought_chunk → tool_call → tool_call_update → agent_message_chunk →
session/request_permission（**阻塞等待客户端应答**）→ fs/write_text_file 改
工作区 mbt.md → end_turn 响应。用于 acp.rs 全链集成测试。
"""
import json
import sys
import os


def send(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    sid = "fake-session-1"
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        rid = msg.get("id")
        method = msg.get("method", "")
        if rid is not None and method:
            # 客户端请求
            if method == "initialize":
                send({"jsonrpc": "2.0", "id": rid, "result": {"protocolVersion": 1, "agentCapabilities": {}}})
            elif method == "session/new":
                send({"jsonrpc": "2.0", "id": rid, "result": {"sessionId": sid}})
            elif method == "session/prompt":
                prompt_id = rid
                # 事件序列
                send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": sid, "update": {"sessionUpdate": "agent_thought_chunk", "content": {"type": "text", "text": "思考：检查文档"}}}})
                send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": sid, "update": {"sessionUpdate": "tool_call", "toolCallId": "t1", "title": "读取 mbt.md", "kind": "read"}}})
                send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": sid, "update": {"sessionUpdate": "tool_call_update", "toolCallId": "t1", "status": "completed"}}})
                send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": sid, "update": {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "我来改一下标题。"}}}})
                # 权限请求：等客户端应答后才继续。params 用**协议形状**——
                # 真实字段是 toolCall（标题在其 title 里），顶层 title 非协议字段
                # （官方 SDK RequestPermissionRequest: options/sessionId/toolCall）
                send({"jsonrpc": "2.0", "id": 900, "method": "session/request_permission", "params": {"sessionId": sid, "toolCall": {"title": "写入项目文件", "kind": "edit"}, "options": [{"kind": "allow_once", "name": "允许", "optionId": "allow_once"}, {"kind": "reject_once", "name": "拒绝", "optionId": "reject_once"}]}})
                # 该行循环继续收应答（id=900 的 response 在下方处理）
                continue
            else:
                send({"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "method_not_found"}})
            continue
        if rid is not None:
            # 客户端响应
            if rid == 900:
                # 锚定应答线格式：result 必须是 outcome 包裹对象（官方 SDK
                # RequestPermissionResponse.outcome: selected/cancelled）。
                # 畸形形状此前在全绿测试下逃逸（夹具只判 id 不解析 result）
                outcome = (msg.get("result") or {}).get("outcome")
                if not isinstance(outcome, dict) or outcome.get("outcome") not in ("selected", "cancelled"):
                    sys.stderr.write("FAKE-AGENT: 权限应答线格式错误（缺 outcome 包裹对象）: %s\n" % json.dumps(msg, ensure_ascii=False))
                    sys.exit(1)
                if outcome.get("outcome") == "selected" and outcome.get("optionId") != "allow_once":
                    sys.stderr.write("FAKE-AGENT: selected 应答缺 optionId 或不匹配: %s\n" % json.dumps(outcome, ensure_ascii=False))
                    sys.exit(1)
                # 权限已应答：走 fs 回调写文件，然后 end_turn
                send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": sid, "update": {"sessionUpdate": "agent_message_chunk", "content": {"type": "text", "text": "已获授权，写入修改。"}}}})
                send({"jsonrpc": "2.0", "id": 901, "method": "fs/write_text_file", "params": {"sessionId": sid, "path": os.path.join(os.getcwd(), "mbt.md"), "content": "---\nmoonviz:\n  format: visual-document\n---\n\n# w\n\n<!-- moonviz:artboard w -->\n```mbt\nfn visual_w() -> @decl.Prototype {\n  let page = @decl.prototype(name=\"w\", width=390, height=844)\n  page.add(@decl.generic_node(id=\"t1\", component=\"body_text\", kind=\"text\", width=@decl.fixed(200), height=@decl.fixed(24), x=20, y=40, text=\"外接智能体改的\", fill=\"none\", text_color=\"#14201A\", font_size=14, visible=true))\n  page\n}\n```\n"}})
                send({"jsonrpc": "2.0", "id": prompt_id, "result": {"stopReason": "end_turn"}})


if __name__ == "__main__":
    main()
