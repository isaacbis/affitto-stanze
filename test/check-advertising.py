"""Compile the production consent coordinator on macOS with fake iOS/Google services."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parent.parent
source = (root / 'iOS/AffittoStanze/Advertising.swift').read_text()
coordinator = source[source.index('enum TrackingAuthorization'):source.index('// iOS service adapter.')]
code = ('import Foundation\nimport Combine\n' + coordinator
        + (root / 'iOS/Tests/advertising-check.swift').read_text())
with tempfile.TemporaryDirectory(prefix='affitto-ads-test-') as directory:
    path = Path(directory) / 'Check.swift'
    binary = Path(directory) / 'check'
    path.write_text(code)
    subprocess.run(['swiftc', '-D', 'DEBUG', '-parse-as-library', str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
