#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

python3 -m py_compile "$ROOT/backend/ai_bridge.py" "$ROOT/backend/desktop_adapter.py" "$ROOT/backend/linux_context.py" "$ROOT/backend/agent_runtime.py" "$ROOT/backend/voice_bridge.py"
bash -n "$ROOT/install.sh" "$ROOT/bin/mock-island" "$ROOT/scripts/setup-voice.sh"

# Regression tests: common PC requests must become actual tool plans, not chat advice.
printf '%s\n' 'revisa las actualizaciones pendientes' | python3 "$ROOT/backend/agent_runtime.py" plan --provider mock --stdin | \
  python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["mode"]=="agent" and d["actions"] and d["actions"][0]["tool"]=="package.updates"'
printf '%s\n' 'abre firefox' | python3 "$ROOT/backend/agent_runtime.py" plan --provider mock --stdin | \
  python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["mode"]=="agent" and d["actions"] and d["actions"][0]["tool"]=="app.open"'

if command -v qmllint >/dev/null 2>&1; then
  qmllint "$ROOT/shell.qml"
else
  python3 - "$ROOT/shell.qml" <<'PY'
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
stack=[]
pairs={'}':'{', ')':'(', ']':'['}
opens=set(pairs.values())
state='code'; quote=''; i=0; line=1
while i < len(s):
    ch=s[i]; nxt=s[i+1] if i+1 < len(s) else ''
    if state == 'code':
        if ch == '/' and nxt == '/': state='line'; i += 1
        elif ch == '/' and nxt == '*': state='block'; i += 1
        elif ch in ('"', "'"): state='string'; quote=ch
        elif ch in opens: stack.append((ch,line))
        elif ch in pairs:
            if not stack or stack[-1][0] != pairs[ch]:
                raise SystemExit(f"QML delimiter mismatch at line {line}: {ch}")
            stack.pop()
    elif state == 'line':
        if ch == '\n': state='code'
    elif state == 'block':
        if ch == '*' and nxt == '/': state='code'; i += 1
    elif state == 'string':
        if ch == '\\': i += 1
        elif ch == quote: state='code'
    if ch == '\n': line += 1
    i += 1
if stack:
    raise SystemExit(f"QML has unclosed delimiter: {stack[-1]}")
print('QML delimiters: OK (qmllint no disponible)')
PY
fi

echo "Mock Island checks: OK"
