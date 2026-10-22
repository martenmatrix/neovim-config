"""Small deterministic agent for the editor's ACP integration regressions."""

import base64
import json
from pathlib import Path
import sys


def send(message):
    print(json.dumps({"jsonrpc": "2.0", **message}), flush=True)


def update(event, **fields):
    send({"method": "session/update", "params": {
        "sessionId": "fixture", "update": {"sessionUpdate": event, **fields},
    }})


held = None
permission_prompt = None
permission_commands = []
permission_number = 0


def request_status_permission():
    global permission_number
    permission_number += 1
    command = permission_commands.pop(0)
    tool = {
        "toolCallId": f"status-{permission_number}", "title": "Show git status",
        "kind": "execute", "status": "pending",
        "rawInput": {"command": command, "commands": [command]},
    }
    update("tool_call", **tool)
    send({
        "id": f"permission-{permission_number}", "method": "session/request_permission",
        "params": {
            "sessionId": "fixture", "toolCall": tool,
            "options": [
                {"optionId": "allow_once", "kind": "allow_once", "name": "Allow once"},
                {"optionId": "allow_always", "kind": "allow_always", "name": "Always allow"},
                {"optionId": "reject_once", "kind": "reject_once", "name": "Deny"},
            ],
        },
    })


for line in sys.stdin:
    request = json.loads(line)
    if "method" not in request:
        assert request["id"] == f"permission-{permission_number}"
        assert request["result"]["outcome"] == {"outcome": "selected", "optionId": "allow_once"}
        update("tool_call_update", toolCallId=f"status-{permission_number}", status="completed")
        if permission_commands:
            request_status_permission()
        else:
            update("agent_message_chunk", content={"type": "text", "text": "Fixture status approvals received"})
            send({"id": permission_prompt, "result": {"stopReason": "end_turn"}})
            permission_prompt = None
        continue
    method = request.get("method")
    ident = request.get("id")
    params = request.get("params", {})
    result = {}
    if method == "initialize":
        result = {
            "protocolVersion": 1,
            "agentCapabilities": {
                "loadSession": True, "sessionCapabilities": {"list": {}},
                "promptCapabilities": {"image": True},
            },
            "authMethods": [],
        }
    elif method in ("session/new", "session/load"):
        if method == "session/load":
            update("user_message_chunk", content={"type": "text", "text": "Previous fixture request"})
            update("agent_message_chunk", content={"type": "text", "text": "Resumed fixture history"})
        result = {
            "sessionId": "fixture",
            "configOptions": [{
                "id": "model", "category": "model", "name": "Model", "type": "select",
                "currentValue": "fixture-model",
                "options": [
                    {"value": "fixture-model", "name": "Fixture"},
                    {"value": "fixture-alternate", "name": "Alternate"},
                ],
            }],
        }
    elif method == "session/list":
        result = {"sessions": [{"sessionId": "fixture", "cwd": str(Path.cwd()), "title": "Fixture"}]}
    elif method == "session/prompt":
        text = "\n".join(p.get("text", "") for p in params.get("prompt", []))
        response = "Fixture response"
        if "STATUS_PERMISSIONS_FIXTURE" in text or "FULL_AUTO_PERMISSIONS_FIXTURE" in text:
            permission_prompt = ident
            permission_commands = (
                ["printf full-auto-fixture"] if "FULL_AUTO_PERMISSIONS_FIXTURE" in text
                else ["git status --short --branch", "git --no-pager status -sb"]
            )
            request_status_permission()
            continue
        if "IMAGE_FIXTURE" in text:
            images = [p for p in params["prompt"] if p["type"] == "image"]
            assert len(images) == 1 and images[0]["mimeType"] == "image/png"
            assert base64.b64decode(images[0]["data"], validate=True).startswith(b"\x89PNG\r\n\x1a\n")
            response = "Fixture image received"
        if "HOLD_FIXTURE" in text:
            held = ident
            update("agent_message_chunk", content={"type": "text", "text": "Waiting"})
            continue
        if "EDIT_FIXTURE" in text:
            Path("first.lua").write_text("return 'changed first'\n")
            Path("second.lua").write_text("return 'changed second'\n")
        if "FOLLOWUP_FIXTURE" in text:
            Path("first.lua").write_text("return 'followup'\n")
        update("agent_message_chunk", content={"type": "text", "text": response})
        result = {"stopReason": "end_turn"}
    elif method == "session/cancel":
        if held is not None:
            send({"id": held, "result": {"stopReason": "cancelled"}})
            held = None
    if ident is not None:
        send({"id": ident, "result": result})
    if method == "session/new":
        update("available_commands_update", availableCommands=[
            {"name": "compact", "description": "Compact fixture context"},
        ])
