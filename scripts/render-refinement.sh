#!/bin/bash
set -euo pipefail
mkdir -p build/QuotaNotch-dist build/refinement
# Read the accepted release components without changing the checkout.
git show fe983c2:QuotaNotch/Design/CompactQuotaDesign.swift > build/refinement/OriginalCompact.swift
git show fe983c2:QuotaNotch/Design/QuotaWindowTile.swift > build/refinement/OriginalTile.swift
python3 - <<'PY'
from pathlib import Path
p=Path('build/refinement/OriginalCompact.swift');s=p.read_text();s='import SwiftUI\n'+s[s.index('/// Original small-size'):]
for name in ['QuotaBrandMark','ClaudeRays','CodexKnot','CompactQuotaGauge','GeminiSpark']:
 s=s.replace(name,'Original'+name)
p.write_text(s)
p=Path('build/refinement/OriginalTile.swift');s=p.read_text().replace('QuotaWindowTile','OriginalQuotaWindowTile').replace('QuotaProviderTab','OriginalQuotaProviderTab');p.write_text(s)
PY
swiftc -target "$(uname -m)-apple-macos15.0" -parse-as-library QuotaNotch/Design/*.swift QuotaNotch/Core/QuotaWarning.swift QuotaNotch/Core/QuotaCompactMetrics.swift QuotaNotch/Core/QuotaLocalization.swift QuotaNotch/Core/QuotaModels.swift build/refinement/*.swift scripts/render-refinement.swift -o build/refinement/render
build/refinement/render
