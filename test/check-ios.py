"""Run isolated Swift session/date regression checks on macOS; no live requests."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parent.parent
s = (root / 'iOS/AffittoStanze/AffittoStanzeApp.swift').read_text()
code = ('import SwiftUI\nimport Foundation\n'
        + s[s.index('struct User:'):]
        + (root / 'iOS/Tests/session-check.swift').read_text())
with tempfile.TemporaryDirectory(prefix='affitto-swift-test-') as directory:
    source = Path(directory) / 'Check.swift'
    binary = Path(directory) / 'check'
    source.write_text(code)
    subprocess.run(['swiftc', '-parse-as-library', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
