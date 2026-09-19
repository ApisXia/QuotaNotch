#!/bin/bash
set -euo pipefail
mkdir -p build/task-status-src build/task-status-output
python3 - <<'PY'
from pathlib import Path
import subprocess
out=Path('build/task-status-src')
def block(source, marker):
 start=source.index(marker); opening=source.index('{',start); depth=1; end=opening+1
 while depth:
  if source[end]=='{': depth+=1
  if source[end]=='}': depth-=1
  end+=1
 return source[start:end]
source=Path('QuotaNotch/UI/AgentCompactView.swift').read_text()
out.joinpath('Glyph.swift').write_text(source.split('struct AgentCompactDock<')[0])
old=subprocess.check_output(['git','show','ce06250:QuotaNotch/UI/AgentCompactView.swift'],text=True).split('struct AgentCompactDock<')[0]
for name in ['AgentWingOffsetKey','AgentPaperGlyph','AgentTaskStateMark','AgentSpeechMark','AgentCrossMark']:
 old=old.replace(name,'Previous'+name)
out.joinpath('Previous.swift').write_text(old)
model=Path('QuotaNotch/Core/AgentActivity.swift').read_text()
attention=Path('QuotaNotch/Core/AgentAttention.swift').read_text()
text=Path('QuotaNotch/UI/AgentActivityStore.swift').read_text()
helpers='import SwiftUI\n'+block(model,'enum AgentRunState:')+'\n'+block(attention,'enum AgentGlyphMotion {')+'\nenum AgentText {\nstatic func t(_ zh: String, _ en: String) -> String { zh }\n'+block(text,'static func state(_ state: AgentRunState)')+'\n'+block(text,'static func color(_ state: AgentRunState)')+'\n}'
out.joinpath('Model.swift').write_text(helpers)
PY
swiftc -target "$(uname -m)-apple-macos15.0" -parse-as-library build/task-status-src/*.swift scripts/render-task-status.swift -o build/task-status-preview
build/task-status-preview
