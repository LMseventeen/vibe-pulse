#!/usr/bin/env python3
"""
Vibe Pulse Hook
- Sends session state to VibePulse.app via Unix socket
- Extended from claude-island-state.py with Bash stdout/exit code capture
- For PermissionRequest: waits for user decision from the app
"""
import json
import os
import socket
import sys

SOCKET_PATH = "/tmp/claude-pulse.sock"
TIMEOUT_SECONDS = 300  # 5 minutes for permission decisions


def get_tty():
    """Get the TTY of the Claude process (parent)"""
    import subprocess

    ppid = os.getppid()

    try:
        result = subprocess.run(
            ["ps", "-p", str(ppid), "-o", "tty="],
            capture_output=True,
            text=True,
            timeout=2
        )
        tty = result.stdout.strip()
        if tty and tty != "??" and tty != "-":
            if not tty.startswith("/dev/"):
                tty = "/dev/" + tty
            return tty
    except Exception:
        pass

    try:
        return os.ttyname(sys.stdin.fileno())
    except (OSError, AttributeError):
        pass
    try:
        return os.ttyname(sys.stdout.fileno())
    except (OSError, AttributeError):
        pass
    return None


def _truncate(text, max_len):
    """Truncate long text, keeping the tail (test summaries are at the end)"""
    if not text or len(text) <= max_len:
        return text
    return "...\n" + text[-max_len:]


def send_event(state):
    """Send event to app, return response if any"""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(TIMEOUT_SECONDS)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(state).encode())

        if state.get("status") == "waiting_for_approval":
            response = sock.recv(4096)
            sock.close()
            if response:
                return json.loads(response.decode())
        else:
            sock.close()

        return None
    except (socket.error, OSError, json.JSONDecodeError):
        return None


def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    session_id = data.get("session_id", "unknown")
    event = data.get("hook_event_name", "")
    cwd = data.get("cwd", "")
    tool_input = data.get("tool_input", {})

    claude_pid = os.getppid()
    tty = get_tty()

    state = {
        "session_id": session_id,
        "cwd": cwd,
        "event": event,
        "pid": claude_pid,
        "tty": tty,
    }

    if event == "PostToolUse":
        state["status"] = "processing"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input

        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

        # --- Vibe Pulse: Capture Bash tool output ---
        tool_name = data.get("tool_name", "")
        if tool_name in ("Bash", "bash", "execute_command"):
            tool_result = data.get("tool_result", {})
            state["stdout"] = _truncate(tool_result.get("stdout", ""), 2048)
            state["stderr"] = _truncate(tool_result.get("stderr", ""), 1024)
            state["exit_code"] = tool_result.get("exitCode")
            state["bash_command"] = tool_input.get("command", "")

    elif event == "PostToolUseFailure":
        state["status"] = "processing"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        state["tool_error"] = data.get("error") or data.get("message")

        tool_use_id_from_event = data.get("tool_use_id")
        if tool_use_id_from_event:
            state["tool_use_id"] = tool_use_id_from_event

        # --- Vibe Pulse: Capture failed Bash output ---
        tool_name = data.get("tool_name", "")
        if tool_name in ("Bash", "bash", "execute_command"):
            tool_result = data.get("tool_result", {})
            state["stdout"] = _truncate(tool_result.get("stdout", ""), 2048)
            state["stderr"] = _truncate(tool_result.get("stderr", ""), 1024)
            state["exit_code"] = tool_result.get("exitCode")
            state["bash_command"] = tool_input.get("command", "")

    elif event == "PermissionRequest":
        state["status"] = "waiting_for_approval"
        state["tool"] = data.get("tool_name")
        state["tool_input"] = tool_input
        # tool_use_id may not exist in PermissionRequest; generate a fallback
        tool_use_id_from_event = data.get("tool_use_id")
        if not tool_use_id_from_event:
            import hashlib, time
            raw = f"{session_id}:{data.get('tool_name','')}:{time.time()}"
            tool_use_id_from_event = "perm_" + hashlib.md5(raw.encode()).hexdigest()[:16]
        state["tool_use_id"] = tool_use_id_from_event

        response = send_event(state)

        if response:
            decision = response.get("decision", "ask")
            reason = response.get("reason", "")

            if decision == "allow":
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {"behavior": "allow"},
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

            elif decision == "deny":
                output = {
                    "hookSpecificOutput": {
                        "hookEventName": "PermissionRequest",
                        "decision": {
                            "behavior": "deny",
                            "message": reason or "Denied by user via VibePulse",
                        },
                    }
                }
                print(json.dumps(output))
                sys.exit(0)

        sys.exit(0)

    elif event == "Notification":
        notification_type = data.get("notification_type")
        if notification_type == "permission_prompt":
            sys.exit(0)
        elif notification_type == "idle_prompt":
            state["status"] = "waiting_for_input"
        else:
            state["status"] = "notification"
        state["notification_type"] = notification_type
        state["message"] = data.get("message")

    elif event == "Stop":
        state["status"] = "waiting_for_input"

    elif event == "StopFailure":
        state["status"] = "waiting_for_input"
        state["stop_error"] = data.get("error") or data.get("message")

    elif event == "SessionStart":
        state["status"] = "waiting_for_input"

    elif event == "SessionEnd":
        state["status"] = "ended"

    else:
        state["status"] = "unknown"

    send_event(state)


if __name__ == "__main__":
    main()
