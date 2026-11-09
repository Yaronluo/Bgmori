#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tmp
python3 - "$@" <<'PY'
from pathlib import Path
import os, subprocess, tempfile
with tempfile.TemporaryDirectory(prefix='bgmori-reminders.',dir='build/tmp') as folder:
    root=Path(folder).resolve()
    (root/'.bgmori-temporary').touch()
    (root/'.active').write_text(str(os.getpid()))
    sources=['Bgmori/Core/Storage/AiringReminderPlan.swift','Bgmori/Core/Storage/NotificationManager.swift',
             'Bgmori/Core/Settings/AppSettings.swift','Bgmori/Core/Models/Models.swift',
             'Bgmori/Core/API/MirrorRouting.swift','Bgmori/App/AppRouter.swift','tests/AiringReminderTests.swift']
    base=['xcrun','swiftc','-swift-version','6','-parse-as-library']
    subprocess.run(base+sources+['-o',str(root/'reminders-mac')],check=True)
    subprocess.run([str(root/'reminders-mac')],check=True)
    sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
    subprocess.run(base+['-sdk',sdk,'-target','arm64-apple-ios27.0-simulator']+sources+['-o',str(root/'reminders-ios')],check=True)
    subprocess.run(['xcrun','simctl','spawn','iPhone 17',str(root/'reminders-ios')],check=True)
PY
