[CmdletBinding()]
param(
    [string]$HostAlias = "petalinux-kv260",
    [string]$RemoteProject = "/home/petalinux/Projects/kria-kv260-starter",
    [string]$Language = "",
    [switch]$CheckOnly,
    [switch]$FilesSelfTest,
    [switch]$UiSelfTest,
    [switch]$LayoutSelfTest
)

$ErrorActionPreference = "Stop"
$InstallDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BoardScript = Join-Path $InstallDir "Start-KV260EventCamera-BoardDesktop.ps1"
$X11Script = Join-Path $InstallDir "Start-KV260EventCamera-X11.ps1"
$LogDir = Join-Path $env:TEMP "kv260-event-camera"
$ControlLog = Join-Path $LogDir "control-center.log"
$SettingsDir = if ($env:APPDATA) { Join-Path $env:APPDATA "KV260ControlCenter" } else { Join-Path $env:TEMP "KV260ControlCenter" }
$SettingsPath = Join-Path $SettingsDir "settings.json"
$JupyterLocalPort = 8888
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $SettingsDir | Out-Null

function Write-AppLog {
    param([string]$Text)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $Text" | Out-File -FilePath $ControlLog -Append -Encoding utf8
}

function Get-SshExe {
    return (Get-Command ssh.exe -ErrorAction Stop).Source
}

function Get-ScpExe {
    return (Get-Command scp.exe -ErrorAction Stop).Source
}

function Invoke-NativeNoCapture {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $FilePath @Arguments
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }
}

function Invoke-KV260Ssh {
    param([string]$RemoteCommand)
    $ssh = Get-SshExe
    $scp = Get-ScpExe
    Write-AppLog "ssh $HostAlias $RemoteCommand"
    $id = [Guid]::NewGuid().ToString("N")
    $remoteOut = "/tmp/kv260-control-center-$id.out"
    $remoteErr = "/tmp/kv260-control-center-$id.err"
    $localOut = Join-Path $LogDir "ssh-$id.out"
    $localErr = Join-Path $LogDir "ssh-$id.err"
    $wrapped = "$RemoteCommand > $(ConvertTo-RemoteShellLiteral $remoteOut) 2> $(ConvertTo-RemoteShellLiteral $remoteErr)"

    $code = Invoke-NativeNoCapture -FilePath $ssh -Arguments @("-o", "BatchMode=yes", $HostAlias, $wrapped)
    $outCopyCode = Invoke-NativeNoCapture -FilePath $scp -Arguments @("-O", "${HostAlias}:$remoteOut", $localOut)
    $errCopyCode = Invoke-NativeNoCapture -FilePath $scp -Arguments @("-O", "${HostAlias}:$remoteErr", $localErr)
    [void](Invoke-NativeNoCapture -FilePath $ssh -Arguments @("-o", "BatchMode=yes", $HostAlias, "rm -f $(ConvertTo-RemoteShellLiteral $remoteOut) $(ConvertTo-RemoteShellLiteral $remoteErr)"))

    $stdout = if (Test-Path -LiteralPath $localOut) { [string](Get-Content -LiteralPath $localOut -Raw) } else { "" }
    $stderr = if (Test-Path -LiteralPath $localErr) { [string](Get-Content -LiteralPath $localErr -Raw) } else { "" }
    Remove-Item -LiteralPath $localOut, $localErr -Force -ErrorAction SilentlyContinue
    if ($outCopyCode -ne 0 -or $errCopyCode -ne 0) {
        throw "could not retrieve KV260 command output files"
    }
    if ($code -ne 0) {
        throw "ssh exited with code $code`r`n$stdout`r`n$stderr"
    }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        Write-AppLog "ssh stderr:`r`n$stderr"
    }
    return $stdout
}

function ConvertFrom-JsonTail {
    param(
        [string]$Text,
        [string]$Context = "remote command"
    )
    $lines = @($Text -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 })
    for ($index = $lines.Count - 1; $index -ge 0; $index--) {
        $candidate = $lines[$index].Trim()
        if ($candidate.StartsWith("{") -or $candidate.StartsWith("[")) {
            try {
                return ($candidate | ConvertFrom-Json)
            } catch {
                Write-AppLog "$Context returned invalid JSON. Raw output:`r`n$Text`r`nException:`r`n$($_ | Out-String)"
                throw "$Context returned invalid JSON. Details were written to $ControlLog"
            }
        }
    }
    Write-AppLog "$Context did not return JSON. Raw output:`r`n$Text"
    throw "$Context did not return JSON. Details were written to $ControlLog"
}

if ($CheckOnly) {
    $required = @(
        $BoardScript,
        $X11Script,
        (Join-Path $InstallDir "Start-KV260EventCamera-X11.ps1")
    )
    $missing = $required | Where-Object { -not (Test-Path $_) }
    if ($missing) {
        Write-Host "MISSING=$($missing -join ',')"
        exit 1
    }
    Write-Host "SSH=$(Get-SshExe)"
    Write-Host "SCP=$(Get-ScpExe)"
    Write-Host "BOARD_SCRIPT=$BoardScript"
    Write-Host "X11_SCRIPT=$X11Script"
    exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$script:SupportedLanguages = @(
    [pscustomobject]@{ Code = "en"; Name = "English" },
    [pscustomobject]@{ Code = "ar"; Name = "العربية" },
    [pscustomobject]@{ Code = "es"; Name = "Español" },
    [pscustomobject]@{ Code = "fr"; Name = "Français" },
    [pscustomobject]@{ Code = "ja"; Name = "日本語" },
    [pscustomobject]@{ Code = "ko"; Name = "한국어" },
    [pscustomobject]@{ Code = "vi"; Name = "Tiếng Việt" },
    [pscustomobject]@{ Code = "zh-Hans"; Name = "中文 简体" },
    [pscustomobject]@{ Code = "zh-Hant"; Name = "中文 繁體" },
    [pscustomobject]@{ Code = "de"; Name = "Deutsch" },
    [pscustomobject]@{ Code = "ru"; Name = "Русский" }
)

$script:Translations = @{
    en = @{
        "KV260 Control Center" = "KV260 Control Center"
        "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point." = "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point."
        "Powered by AgInTi Flow - created by LazyingArt LLC - flow.lazying.art" = "Powered by AgInTi Flow - created by LazyingArt LLC - flow.lazying.art"
        "Language" = "Language"
        "Camera" = "Camera"
        "Applications" = "Applications"
        "Files" = "Files"
        "Notebook And Power" = "Notebook And Power"
        "Open Camera On Windows" = "Open Camera On Windows"
        "Open Camera On KV260" = "Open Camera On KV260"
        "Native Metavision Viewer" = "Native Metavision Viewer"
        "Stop Camera Viewers" = "Stop Camera Viewers"
        "Status" = "Status"
        "File Manager" = "File Manager"
        "Terminal" = "Terminal"
        "RXVT Terminal" = "RXVT Terminal"
        "Text Editor" = "Text Editor"
        "Appearance" = "Appearance"
        "Touch Calibrator" = "Touch Calibrator"
        "Preferred Apps" = "Preferred Apps"
        "Desktop Preferences" = "Desktop Preferences"
        "File Transfer GUI" = "File Transfer GUI"
        "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right." = "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right."
        "KV260 Board" = "KV260 Board"
        "Windows / Remote Host" = "Windows / Remote Host"
        "Browse" = "Browse"
        "Up" = "Up"
        "Refresh" = "Refresh"
        "Copy Windows -> KV260" = "Copy Windows -> KV260"
        "Copy KV260 -> Windows" = "Copy KV260 -> Windows"
        "Refresh Both" = "Refresh Both"
        "New KV260 Folder" = "New KV260 Folder"
        "Open Board Transfer GUI" = "Open Board Transfer GUI"
        "Drag files or rows onto a pane. Drop on a folder row to copy into that folder." = "Drag files or rows onto a pane. Drop on a folder row to copy into that folder."
        "Drop target: {0} folder -> {1}" = "Drop target: {0} folder -> {1}"
        "Drop target: {0} current folder -> {1}" = "Drop target: {0} current folder -> {1}"
        "Open Jupyter Notebook" = "Open Jupyter Notebook"
        "Stop Jupyter" = "Stop Jupyter"
        "Reboot KV260" = "Reboot KV260"
        "Shutdown KV260" = "Shutdown KV260"
        "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner." = "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner."
        "Probe Button" = "Probe Button"
    }
    ar = @{
        "KV260 Control Center" = "مركز تحكم KV260"
        "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point." = "شغل كاميرا الأحداث وأدوات اللوحة والدفاتر وإجراءات النظام من نقطة واحدة في ويندوز."
        "Language" = "اللغة"
        "Camera" = "الكاميرا"
        "Applications" = "التطبيقات"
        "Files" = "الملفات"
        "Notebook And Power" = "الدفتر والطاقة"
        "Open Camera On Windows" = "فتح الكاميرا على ويندوز"
        "Open Camera On KV260" = "فتح الكاميرا على KV260"
        "Native Metavision Viewer" = "عارض Metavision الأصلي"
        "Stop Camera Viewers" = "إيقاف عارضات الكاميرا"
        "Status" = "الحالة"
        "File Manager" = "مدير الملفات"
        "Terminal" = "الطرفية"
        "RXVT Terminal" = "طرفية RXVT"
        "Text Editor" = "محرر النصوص"
        "Appearance" = "المظهر"
        "Touch Calibrator" = "معايرة اللمس"
        "Preferred Apps" = "التطبيقات المفضلة"
        "Desktop Preferences" = "تفضيلات سطح المكتب"
        "File Transfer GUI" = "واجهة نقل الملفات"
        "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right." = "انسخ الملفات والمجلدات بين لوحة KV260 في اليسار ومضيف ويندوز أو المضيف البعيد في اليمين."
        "KV260 Board" = "لوحة KV260"
        "Windows / Remote Host" = "ويندوز / مضيف بعيد"
        "Browse" = "تصفح"
        "Up" = "أعلى"
        "Refresh" = "تحديث"
        "Copy Windows -> KV260" = "نسخ ويندوز -> KV260"
        "Copy KV260 -> Windows" = "نسخ KV260 -> ويندوز"
        "Refresh Both" = "تحديث الكل"
        "New KV260 Folder" = "مجلد KV260 جديد"
        "Open Board Transfer GUI" = "فتح نقل اللوحة"
        "Drag files or rows onto a pane. Drop on a folder row to copy into that folder." = "اسحب الملفات أو الصفوف إلى لوحة. أفلت على صف مجلد للنسخ داخله."
        "Drop target: {0} folder -> {1}" = "هدف الإفلات: مجلد {0} -> {1}"
        "Drop target: {0} current folder -> {1}" = "هدف الإفلات: مجلد {0} الحالي -> {1}"
        "Open Jupyter Notebook" = "فتح Jupyter Notebook"
        "Stop Jupyter" = "إيقاف Jupyter"
        "Reboot KV260" = "إعادة تشغيل KV260"
        "Shutdown KV260" = "إيقاف KV260"
        "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner." = "تستخدم تطبيقات Windows X11 برنامج VcXsrv. تطبيقات الكاميرا حصرية لأن /dev/video0 يقبل مالكا واحدا فقط."
        "Probe Button" = "زر اختبار"
    }
    es = @{
        "KV260 Control Center" = "Centro de Control KV260"
        "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point." = "Abre la cámara de eventos, herramientas de la placa, notebooks y acciones del sistema desde una sola entrada de Windows."
        "Language" = "Idioma"
        "Camera" = "Cámara"
        "Applications" = "Aplicaciones"
        "Files" = "Archivos"
        "Notebook And Power" = "Notebook y energía"
        "Open Camera On Windows" = "Abrir cámara en Windows"
        "Open Camera On KV260" = "Abrir cámara en KV260"
        "Native Metavision Viewer" = "Visor Metavision nativo"
        "Stop Camera Viewers" = "Detener visores"
        "Status" = "Estado"
        "File Manager" = "Gestor de archivos"
        "Terminal" = "Terminal"
        "RXVT Terminal" = "Terminal RXVT"
        "Text Editor" = "Editor de texto"
        "Appearance" = "Apariencia"
        "Touch Calibrator" = "Calibrador táctil"
        "Preferred Apps" = "Apps preferidas"
        "Desktop Preferences" = "Preferencias de escritorio"
        "File Transfer GUI" = "Transferencia de archivos"
        "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right." = "Copia archivos y carpetas entre la KV260 a la izquierda y Windows o el host remoto a la derecha."
        "KV260 Board" = "Placa KV260"
        "Windows / Remote Host" = "Windows / host remoto"
        "Browse" = "Buscar"
        "Up" = "Subir"
        "Refresh" = "Actualizar"
        "Copy Windows -> KV260" = "Copiar Windows -> KV260"
        "Copy KV260 -> Windows" = "Copiar KV260 -> Windows"
        "Refresh Both" = "Actualizar ambos"
        "New KV260 Folder" = "Nueva carpeta KV260"
        "Open Board Transfer GUI" = "Abrir transferencia"
        "Drag files or rows onto a pane. Drop on a folder row to copy into that folder." = "Arrastra archivos o filas a un panel. Suelta sobre una carpeta para copiar dentro."
        "Drop target: {0} folder -> {1}" = "Destino: carpeta {0} -> {1}"
        "Drop target: {0} current folder -> {1}" = "Destino: carpeta actual {0} -> {1}"
        "Open Jupyter Notebook" = "Abrir Jupyter Notebook"
        "Stop Jupyter" = "Detener Jupyter"
        "Reboot KV260" = "Reiniciar KV260"
        "Shutdown KV260" = "Apagar KV260"
        "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner." = "Las apps X11 en Windows usan VcXsrv. La cámara es exclusiva porque /dev/video0 solo puede tener un dueño."
        "Probe Button" = "Botón de prueba"
    }
    fr = @{
        "KV260 Control Center" = "Centre de contrôle KV260"
        "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point." = "Lancez la caméra événementielle, les outils de la carte, les notebooks et les actions système depuis une seule entrée Windows."
        "Language" = "Langue"
        "Camera" = "Caméra"
        "Applications" = "Applications"
        "Files" = "Fichiers"
        "Notebook And Power" = "Notebook et alimentation"
        "Open Camera On Windows" = "Ouvrir caméra sur Windows"
        "Open Camera On KV260" = "Ouvrir caméra sur KV260"
        "Native Metavision Viewer" = "Visionneuse Metavision native"
        "Stop Camera Viewers" = "Arrêter les visionneuses"
        "Status" = "État"
        "File Manager" = "Gestionnaire de fichiers"
        "Terminal" = "Terminal"
        "RXVT Terminal" = "Terminal RXVT"
        "Text Editor" = "Éditeur de texte"
        "Appearance" = "Apparence"
        "Touch Calibrator" = "Calibration tactile"
        "Preferred Apps" = "Apps préférées"
        "Desktop Preferences" = "Préférences du bureau"
        "File Transfer GUI" = "Transfert de fichiers"
        "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right." = "Copiez fichiers et dossiers entre la KV260 à gauche et Windows ou l’hôte distant à droite."
        "KV260 Board" = "Carte KV260"
        "Windows / Remote Host" = "Windows / hôte distant"
        "Browse" = "Parcourir"
        "Up" = "Monter"
        "Refresh" = "Actualiser"
        "Copy Windows -> KV260" = "Copier Windows -> KV260"
        "Copy KV260 -> Windows" = "Copier KV260 -> Windows"
        "Refresh Both" = "Tout actualiser"
        "New KV260 Folder" = "Nouveau dossier KV260"
        "Open Board Transfer GUI" = "Ouvrir le transfert"
        "Drag files or rows onto a pane. Drop on a folder row to copy into that folder." = "Glissez fichiers ou lignes sur un panneau. Déposez sur un dossier pour copier dedans."
        "Drop target: {0} folder -> {1}" = "Cible : dossier {0} -> {1}"
        "Drop target: {0} current folder -> {1}" = "Cible : dossier courant {0} -> {1}"
        "Open Jupyter Notebook" = "Ouvrir Jupyter Notebook"
        "Stop Jupyter" = "Arrêter Jupyter"
        "Reboot KV260" = "Redémarrer KV260"
        "Shutdown KV260" = "Éteindre KV260"
        "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner." = "Les apps X11 Windows utilisent VcXsrv. La caméra est exclusive car /dev/video0 ne peut avoir qu’un propriétaire."
        "Probe Button" = "Bouton test"
    }
    ja = @{
        "KV260 Control Center" = "KV260 コントロールセンター"
        "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point." = "イベントカメラ、ボードツール、ノートブック、システム操作を Windows からまとめて起動します。"
        "Language" = "言語"
        "Camera" = "カメラ"
        "Applications" = "アプリ"
        "Files" = "ファイル"
        "Notebook And Power" = "Notebook と電源"
        "Open Camera On Windows" = "Windows でカメラを開く"
        "Open Camera On KV260" = "KV260 でカメラを開く"
        "Native Metavision Viewer" = "Metavision 標準ビューア"
        "Stop Camera Viewers" = "ビューアを停止"
        "Status" = "状態"
        "File Manager" = "ファイル管理"
        "Terminal" = "端末"
        "RXVT Terminal" = "RXVT 端末"
        "Text Editor" = "テキスト編集"
        "Appearance" = "外観"
        "Touch Calibrator" = "タッチ調整"
        "Preferred Apps" = "既定アプリ"
        "Desktop Preferences" = "デスクトップ設定"
        "File Transfer GUI" = "ファイル転送"
        "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right." = "左の KV260 と右の Windows/リモートホスト間でファイルとフォルダをコピーします。"
        "KV260 Board" = "KV260 ボード"
        "Windows / Remote Host" = "Windows / リモート"
        "Browse" = "参照"
        "Up" = "上へ"
        "Refresh" = "更新"
        "Copy Windows -> KV260" = "Windows -> KV260"
        "Copy KV260 -> Windows" = "KV260 -> Windows"
        "Refresh Both" = "両方更新"
        "New KV260 Folder" = "KV260 フォルダ作成"
        "Open Board Transfer GUI" = "転送 GUI を開く"
        "Drag files or rows onto a pane. Drop on a folder row to copy into that folder." = "ファイルや行をペインにドラッグします。フォルダ行へドロップするとその中にコピーします。"
        "Drop target: {0} folder -> {1}" = "ドロップ先: {0} フォルダ -> {1}"
        "Drop target: {0} current folder -> {1}" = "ドロップ先: {0} 現在フォルダ -> {1}"
        "Open Jupyter Notebook" = "Jupyter Notebook を開く"
        "Stop Jupyter" = "Jupyter を停止"
        "Reboot KV260" = "KV260 再起動"
        "Shutdown KV260" = "KV260 シャットダウン"
        "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner." = "Windows X11 アプリは VcXsrv を使用します。/dev/video0 は同時に 1 つの所有者だけです。"
        "Probe Button" = "テストボタン"
    }
    ko = @{
        "KV260 Control Center" = "KV260 제어 센터"
        "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point." = "Windows 한 곳에서 이벤트 카메라, 보드 도구, 노트북, 시스템 작업을 실행합니다."
        "Language" = "언어"
        "Camera" = "카메라"
        "Applications" = "애플리케이션"
        "Files" = "파일"
        "Notebook And Power" = "노트북 및 전원"
        "Open Camera On Windows" = "Windows에서 카메라 열기"
        "Open Camera On KV260" = "KV260에서 카메라 열기"
        "Native Metavision Viewer" = "기본 Metavision 뷰어"
        "Stop Camera Viewers" = "카메라 뷰어 중지"
        "Status" = "상태"
        "File Manager" = "파일 관리자"
        "Terminal" = "터미널"
        "RXVT Terminal" = "RXVT 터미널"
        "Text Editor" = "텍스트 편집기"
        "Appearance" = "모양"
        "Touch Calibrator" = "터치 보정"
        "Preferred Apps" = "기본 앱"
        "Desktop Preferences" = "데스크톱 설정"
        "File Transfer GUI" = "파일 전송"
        "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right." = "왼쪽 KV260과 오른쪽 Windows/원격 호스트 사이에서 파일과 폴더를 복사합니다."
        "KV260 Board" = "KV260 보드"
        "Windows / Remote Host" = "Windows / 원격 호스트"
        "Browse" = "찾기"
        "Up" = "위로"
        "Refresh" = "새로고침"
        "Copy Windows -> KV260" = "Windows -> KV260"
        "Copy KV260 -> Windows" = "KV260 -> Windows"
        "Refresh Both" = "둘 다 새로고침"
        "New KV260 Folder" = "새 KV260 폴더"
        "Open Board Transfer GUI" = "전송 GUI 열기"
        "Drag files or rows onto a pane. Drop on a folder row to copy into that folder." = "파일이나 행을 패널로 끌어오세요. 폴더 행에 놓으면 그 안으로 복사됩니다."
        "Drop target: {0} folder -> {1}" = "드롭 대상: {0} 폴더 -> {1}"
        "Drop target: {0} current folder -> {1}" = "드롭 대상: {0} 현재 폴더 -> {1}"
        "Open Jupyter Notebook" = "Jupyter Notebook 열기"
        "Stop Jupyter" = "Jupyter 중지"
        "Reboot KV260" = "KV260 재부팅"
        "Shutdown KV260" = "KV260 종료"
        "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner." = "Windows X11 앱은 VcXsrv를 사용합니다. /dev/video0은 한 번에 하나의 소유자만 사용할 수 있습니다."
        "Probe Button" = "테스트 버튼"
    }
    vi = @{
        "KV260 Control Center" = "Trung tâm điều khiển KV260"
        "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point." = "Mở camera sự kiện, công cụ bo mạch, notebook và thao tác hệ thống từ một điểm trên Windows."
        "Language" = "Ngôn ngữ"
        "Camera" = "Camera"
        "Applications" = "Ứng dụng"
        "Files" = "Tệp"
        "Notebook And Power" = "Notebook và nguồn"
        "Open Camera On Windows" = "Mở camera trên Windows"
        "Open Camera On KV260" = "Mở camera trên KV260"
        "Native Metavision Viewer" = "Trình xem Metavision gốc"
        "Stop Camera Viewers" = "Dừng trình xem"
        "Status" = "Trạng thái"
        "File Manager" = "Quản lý tệp"
        "Terminal" = "Terminal"
        "RXVT Terminal" = "Terminal RXVT"
        "Text Editor" = "Soạn thảo văn bản"
        "Appearance" = "Giao diện"
        "Touch Calibrator" = "Hiệu chỉnh cảm ứng"
        "Preferred Apps" = "Ứng dụng mặc định"
        "Desktop Preferences" = "Tùy chọn desktop"
        "File Transfer GUI" = "Truyền tệp"
        "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right." = "Sao chép tệp và thư mục giữa KV260 bên trái và Windows hoặc máy từ xa bên phải."
        "KV260 Board" = "Bo KV260"
        "Windows / Remote Host" = "Windows / máy từ xa"
        "Browse" = "Duyệt"
        "Up" = "Lên"
        "Refresh" = "Làm mới"
        "Copy Windows -> KV260" = "Windows -> KV260"
        "Copy KV260 -> Windows" = "KV260 -> Windows"
        "Refresh Both" = "Làm mới cả hai"
        "New KV260 Folder" = "Thư mục KV260 mới"
        "Open Board Transfer GUI" = "Mở truyền tệp"
        "Drag files or rows onto a pane. Drop on a folder row to copy into that folder." = "Kéo tệp hoặc dòng vào khung. Thả lên thư mục để sao chép vào đó."
        "Drop target: {0} folder -> {1}" = "Đích thả: thư mục {0} -> {1}"
        "Drop target: {0} current folder -> {1}" = "Đích thả: thư mục hiện tại {0} -> {1}"
        "Open Jupyter Notebook" = "Mở Jupyter Notebook"
        "Stop Jupyter" = "Dừng Jupyter"
        "Reboot KV260" = "Khởi động lại KV260"
        "Shutdown KV260" = "Tắt KV260"
        "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner." = "Ứng dụng X11 trên Windows dùng VcXsrv. Camera là độc quyền vì /dev/video0 chỉ có một chủ sở hữu."
        "Probe Button" = "Nút kiểm tra"
    }
    "zh-Hans" = @{
        "KV260 Control Center" = "KV260 控制中心"
        "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point." = "从一个 Windows 入口启动事件相机、板端工具、Notebook 和系统操作。"
        "Language" = "语言"
        "Camera" = "相机"
        "Applications" = "应用"
        "Files" = "文件"
        "Notebook And Power" = "Notebook 与电源"
        "Open Camera On Windows" = "在 Windows 打开相机"
        "Open Camera On KV260" = "在 KV260 打开相机"
        "Native Metavision Viewer" = "原生 Metavision 查看器"
        "Stop Camera Viewers" = "停止相机查看器"
        "Status" = "状态"
        "File Manager" = "文件管理器"
        "Terminal" = "终端"
        "RXVT Terminal" = "RXVT 终端"
        "Text Editor" = "文本编辑器"
        "Appearance" = "外观"
        "Touch Calibrator" = "触摸校准"
        "Preferred Apps" = "首选应用"
        "Desktop Preferences" = "桌面设置"
        "File Transfer GUI" = "文件传输界面"
        "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right." = "在左侧 KV260 和右侧 Windows/远程主机之间复制文件和文件夹。"
        "KV260 Board" = "KV260 板端"
        "Windows / Remote Host" = "Windows / 远程主机"
        "Browse" = "浏览"
        "Up" = "上级"
        "Refresh" = "刷新"
        "Copy Windows -> KV260" = "Windows -> KV260"
        "Copy KV260 -> Windows" = "KV260 -> Windows"
        "Refresh Both" = "刷新两侧"
        "New KV260 Folder" = "新建 KV260 文件夹"
        "Open Board Transfer GUI" = "打开板端传输界面"
        "Drag files or rows onto a pane. Drop on a folder row to copy into that folder." = "将文件或行拖到面板。拖到文件夹行可复制到该文件夹。"
        "Drop target: {0} folder -> {1}" = "拖放目标：{0} 文件夹 -> {1}"
        "Drop target: {0} current folder -> {1}" = "拖放目标：{0} 当前文件夹 -> {1}"
        "Open Jupyter Notebook" = "打开 Jupyter Notebook"
        "Stop Jupyter" = "停止 Jupyter"
        "Reboot KV260" = "重启 KV260"
        "Shutdown KV260" = "关闭 KV260"
        "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner." = "Windows X11 应用使用 VcXsrv。相机应用独占，因为 /dev/video0 只能有一个所有者。"
        "Probe Button" = "测试按钮"
    }
    "zh-Hant" = @{
        "KV260 Control Center" = "KV260 控制中心"
        "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point." = "從一個 Windows 入口啟動事件相機、板端工具、Notebook 與系統操作。"
        "Language" = "語言"
        "Camera" = "相機"
        "Applications" = "應用程式"
        "Files" = "檔案"
        "Notebook And Power" = "Notebook 與電源"
        "Open Camera On Windows" = "在 Windows 開啟相機"
        "Open Camera On KV260" = "在 KV260 開啟相機"
        "Native Metavision Viewer" = "原生 Metavision 檢視器"
        "Stop Camera Viewers" = "停止相機檢視器"
        "Status" = "狀態"
        "File Manager" = "檔案管理器"
        "Terminal" = "終端機"
        "RXVT Terminal" = "RXVT 終端機"
        "Text Editor" = "文字編輯器"
        "Appearance" = "外觀"
        "Touch Calibrator" = "觸控校準"
        "Preferred Apps" = "偏好應用"
        "Desktop Preferences" = "桌面設定"
        "File Transfer GUI" = "檔案傳輸介面"
        "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right." = "在左側 KV260 與右側 Windows/遠端主機之間複製檔案和資料夾。"
        "KV260 Board" = "KV260 板端"
        "Windows / Remote Host" = "Windows / 遠端主機"
        "Browse" = "瀏覽"
        "Up" = "上層"
        "Refresh" = "重新整理"
        "Copy Windows -> KV260" = "Windows -> KV260"
        "Copy KV260 -> Windows" = "KV260 -> Windows"
        "Refresh Both" = "重新整理兩側"
        "New KV260 Folder" = "新增 KV260 資料夾"
        "Open Board Transfer GUI" = "開啟板端傳輸介面"
        "Drag files or rows onto a pane. Drop on a folder row to copy into that folder." = "將檔案或列拖到面板。拖到資料夾列可複製到該資料夾。"
        "Drop target: {0} folder -> {1}" = "拖放目標：{0} 資料夾 -> {1}"
        "Drop target: {0} current folder -> {1}" = "拖放目標：{0} 目前資料夾 -> {1}"
        "Open Jupyter Notebook" = "開啟 Jupyter Notebook"
        "Stop Jupyter" = "停止 Jupyter"
        "Reboot KV260" = "重新啟動 KV260"
        "Shutdown KV260" = "關閉 KV260"
        "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner." = "Windows X11 應用使用 VcXsrv。相機應用為獨占，因為 /dev/video0 只能有一個擁有者。"
        "Probe Button" = "測試按鈕"
    }
    de = @{
        "KV260 Control Center" = "KV260 Kontrollzentrum"
        "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point." = "Startet Ereigniskamera, Board-Werkzeuge, Notebooks und Systemaktionen von einem Windows-Einstieg."
        "Language" = "Sprache"
        "Camera" = "Kamera"
        "Applications" = "Anwendungen"
        "Files" = "Dateien"
        "Notebook And Power" = "Notebook und Energie"
        "Open Camera On Windows" = "Kamera auf Windows öffnen"
        "Open Camera On KV260" = "Kamera auf KV260 öffnen"
        "Native Metavision Viewer" = "Nativer Metavision Viewer"
        "Stop Camera Viewers" = "Viewer stoppen"
        "Status" = "Status"
        "File Manager" = "Dateimanager"
        "Terminal" = "Terminal"
        "RXVT Terminal" = "RXVT Terminal"
        "Text Editor" = "Texteditor"
        "Appearance" = "Darstellung"
        "Touch Calibrator" = "Touch-Kalibrierung"
        "Preferred Apps" = "Standard-Apps"
        "Desktop Preferences" = "Desktop-Einstellungen"
        "File Transfer GUI" = "Dateitransfer"
        "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right." = "Kopiert Dateien und Ordner zwischen KV260 links und Windows oder Remote-Host rechts."
        "KV260 Board" = "KV260 Board"
        "Windows / Remote Host" = "Windows / Remote-Host"
        "Browse" = "Durchsuchen"
        "Up" = "Hoch"
        "Refresh" = "Aktualisieren"
        "Copy Windows -> KV260" = "Windows -> KV260"
        "Copy KV260 -> Windows" = "KV260 -> Windows"
        "Refresh Both" = "Beide aktualisieren"
        "New KV260 Folder" = "Neuer KV260 Ordner"
        "Open Board Transfer GUI" = "Transfer-GUI öffnen"
        "Drag files or rows onto a pane. Drop on a folder row to copy into that folder." = "Dateien oder Zeilen auf ein Feld ziehen. Auf Ordnerzeile ablegen, um dorthin zu kopieren."
        "Drop target: {0} folder -> {1}" = "Ablageziel: {0} Ordner -> {1}"
        "Drop target: {0} current folder -> {1}" = "Ablageziel: {0} aktueller Ordner -> {1}"
        "Open Jupyter Notebook" = "Jupyter Notebook öffnen"
        "Stop Jupyter" = "Jupyter stoppen"
        "Reboot KV260" = "KV260 neu starten"
        "Shutdown KV260" = "KV260 herunterfahren"
        "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner." = "Windows-X11-Apps nutzen VcXsrv. Kamera-Apps sind exklusiv, da /dev/video0 nur einen Besitzer haben kann."
        "Probe Button" = "Testknopf"
    }
    ru = @{
        "KV260 Control Center" = "Центр управления KV260"
        "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point." = "Запуск событийной камеры, инструментов платы, ноутбуков и системных действий из одного окна Windows."
        "Language" = "Язык"
        "Camera" = "Камера"
        "Applications" = "Приложения"
        "Files" = "Файлы"
        "Notebook And Power" = "Notebook и питание"
        "Open Camera On Windows" = "Открыть камеру в Windows"
        "Open Camera On KV260" = "Открыть камеру на KV260"
        "Native Metavision Viewer" = "Родной Metavision Viewer"
        "Stop Camera Viewers" = "Остановить просмотр"
        "Status" = "Статус"
        "File Manager" = "Файловый менеджер"
        "Terminal" = "Терминал"
        "RXVT Terminal" = "Терминал RXVT"
        "Text Editor" = "Текстовый редактор"
        "Appearance" = "Внешний вид"
        "Touch Calibrator" = "Калибровка сенсора"
        "Preferred Apps" = "Приложения по умолчанию"
        "Desktop Preferences" = "Настройки рабочего стола"
        "File Transfer GUI" = "Передача файлов"
        "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right." = "Копируйте файлы и папки между KV260 слева и Windows или удаленным хостом справа."
        "KV260 Board" = "Плата KV260"
        "Windows / Remote Host" = "Windows / удаленный хост"
        "Browse" = "Обзор"
        "Up" = "Вверх"
        "Refresh" = "Обновить"
        "Copy Windows -> KV260" = "Windows -> KV260"
        "Copy KV260 -> Windows" = "KV260 -> Windows"
        "Refresh Both" = "Обновить оба"
        "New KV260 Folder" = "Новая папка KV260"
        "Open Board Transfer GUI" = "Открыть передачу"
        "Drag files or rows onto a pane. Drop on a folder row to copy into that folder." = "Перетащите файлы или строки на панель. Бросьте на папку, чтобы скопировать внутрь."
        "Drop target: {0} folder -> {1}" = "Цель: папка {0} -> {1}"
        "Drop target: {0} current folder -> {1}" = "Цель: текущая папка {0} -> {1}"
        "Open Jupyter Notebook" = "Открыть Jupyter Notebook"
        "Stop Jupyter" = "Остановить Jupyter"
        "Reboot KV260" = "Перезагрузить KV260"
        "Shutdown KV260" = "Выключить KV260"
        "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner." = "Windows X11 приложения используют VcXsrv. Камера эксклюзивна, потому что /dev/video0 может иметь только одного владельца."
        "Probe Button" = "Тестовая кнопка"
    }
}

function Get-ControlSettings {
    if (Test-Path -LiteralPath $SettingsPath) {
        try {
            return (Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json)
        } catch {
            Write-AppLog "Could not read settings: $($_.Exception.Message)"
        }
    }
    return [pscustomobject]@{}
}

$script:ControlSettings = Get-ControlSettings
$script:LocalizedControls = @{}
$script:LocalizedToolTips = New-Object System.Collections.ArrayList

function Test-LanguageCode {
    param([string]$Code)
    return [bool]($script:SupportedLanguages | Where-Object { $_.Code -eq $Code } | Select-Object -First 1)
}

function Resolve-Language {
    param([string]$Requested)
    if (-not [string]::IsNullOrWhiteSpace($Requested) -and (Test-LanguageCode $Requested)) {
        return $Requested
    }
    $saved = ""
    if ($script:ControlSettings -and $script:ControlSettings.PSObject.Properties.Name -contains "language") {
        $saved = [string]$script:ControlSettings.language
    }
    if (-not [string]::IsNullOrWhiteSpace($saved) -and (Test-LanguageCode $saved)) {
        return $saved
    }
    return "en"
}

$script:CurrentLanguage = Resolve-Language $Language

function Save-LanguagePreference {
    param([string]$Code)
    try {
        [pscustomobject]@{ language = $Code } |
            ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath $SettingsPath -Encoding UTF8
    } catch {
        Write-AppLog "Could not save language preference: $($_.Exception.Message)"
    }
}

if (-not [string]::IsNullOrWhiteSpace($Language)) {
    Save-LanguagePreference $script:CurrentLanguage
}

function Get-Text {
    param([string]$Key)
    if ($script:Translations.ContainsKey($script:CurrentLanguage) -and $script:Translations[$script:CurrentLanguage].ContainsKey($Key)) {
        return $script:Translations[$script:CurrentLanguage][$Key]
    }
    if ($script:Translations.en.ContainsKey($Key)) {
        return $script:Translations.en[$Key]
    }
    return $Key
}

function Format-Text {
    param([string]$Key, [object[]]$Args)
    return ((Get-Text $Key) -f $Args)
}

function Register-LocalizedControl {
    param([string]$Key, [object]$Control)
    if (-not $script:LocalizedControls.ContainsKey($Key)) {
        $script:LocalizedControls[$Key] = New-Object System.Collections.ArrayList
    }
    [void]$script:LocalizedControls[$Key].Add($Control)
    $Control.Text = Get-Text $Key
}

function Register-LocalizedToolTip {
    param([string]$Key, [object]$Control)
    [void]$script:LocalizedToolTips.Add([pscustomobject]@{
        Key = $Key
        Control = $Control
    })
    if (Get-Variable -Name ToolTip -Scope Script -ErrorAction SilentlyContinue) {
        $script:ToolTip.SetToolTip($Control, (Get-Text $Key))
    }
    if ($Control.PSObject.Properties.Name -contains "AccessibleName") {
        $Control.AccessibleName = Get-Text $Key
    }
}

function Apply-Language {
    foreach ($key in @($script:LocalizedControls.Keys)) {
        foreach ($control in @($script:LocalizedControls[$key])) {
            if ($control -and (-not ($control.PSObject.Properties.Name -contains "IsDisposed") -or -not $control.IsDisposed)) {
                $control.Text = Get-Text $key
            }
        }
    }
    if (Get-Variable -Name ToolTip -Scope Script -ErrorAction SilentlyContinue) {
        foreach ($entry in @($script:LocalizedToolTips)) {
            $control = $entry.Control
            if ($control -and (-not ($control.PSObject.Properties.Name -contains "IsDisposed") -or -not $control.IsDisposed)) {
                $text = Get-Text $entry.Key
                $script:ToolTip.SetToolTip($control, $text)
                if ($control.PSObject.Properties.Name -contains "AccessibleName") {
                    $control.AccessibleName = $text
                }
            }
        }
    }
    if (Get-Variable -Name FileDropHint -Scope Script -ErrorAction SilentlyContinue) {
        $script:FileDropHint.Text = Get-Text "Drag files or rows onto a pane. Drop on a folder row to copy into that folder."
    }
}

function Set-ControlLanguage {
    param([string]$Code)
    if (-not (Test-LanguageCode $Code)) {
        $Code = "en"
    }
    $script:CurrentLanguage = $Code
    Save-LanguagePreference $Code
    Apply-Language
}

function New-FileIconImage {
    param(
        [string]$Kind,
        [System.Drawing.Color]$Accent
    )
    $bitmap = [System.Drawing.Bitmap]::new(18, 18)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    if ($Kind -eq "folder") {
        $tabBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(251, 191, 36))
        $bodyBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(245, 158, 11))
        $borderPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(180, 83, 9))
        $graphics.FillRectangle($tabBrush, 2, 4, 6, 4)
        $graphics.FillRectangle($bodyBrush, 1, 7, 16, 9)
        $graphics.DrawRectangle($borderPen, 1, 7, 16, 9)
        $graphics.DrawLine($borderPen, 2, 7, 8, 7)
        $tabBrush.Dispose()
        $bodyBrush.Dispose()
        $borderPen.Dispose()
    } else {
        $paperBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(248, 250, 252))
        $foldBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(226, 232, 240))
        $accentBrush = [System.Drawing.SolidBrush]::new($Accent)
        $borderPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(100, 116, 139))
        $points = @(
            ([System.Drawing.Point]::new(4, 2)),
            ([System.Drawing.Point]::new(12, 2)),
            ([System.Drawing.Point]::new(15, 5)),
            ([System.Drawing.Point]::new(15, 16)),
            ([System.Drawing.Point]::new(4, 16))
        )
        $graphics.FillPolygon($paperBrush, $points)
        $graphics.FillPolygon($foldBrush, @(
            ([System.Drawing.Point]::new(12, 2)),
            ([System.Drawing.Point]::new(15, 5)),
            ([System.Drawing.Point]::new(12, 5))
        ))
        $graphics.DrawPolygon($borderPen, $points)
        $graphics.FillRectangle($accentBrush, 5, 11, 9, 3)
        $paperBrush.Dispose()
        $foldBrush.Dispose()
        $accentBrush.Dispose()
        $borderPen.Dispose()
    }

    $graphics.Dispose()
    return $bitmap
}

function Initialize-FileImages {
    $images = New-Object System.Windows.Forms.ImageList
    $images.ImageSize = [System.Drawing.Size]::new(18, 18)
    $images.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit
    $palette = @{
        folder = [System.Drawing.Color]::FromArgb(245, 158, 11)
        file = [System.Drawing.Color]::FromArgb(100, 116, 139)
        text = [System.Drawing.Color]::FromArgb(20, 184, 166)
        code = [System.Drawing.Color]::FromArgb(37, 99, 235)
        image = [System.Drawing.Color]::FromArgb(22, 163, 74)
        video = [System.Drawing.Color]::FromArgb(147, 51, 234)
        audio = [System.Drawing.Color]::FromArgb(219, 39, 119)
        archive = [System.Drawing.Color]::FromArgb(217, 119, 6)
        pdf = [System.Drawing.Color]::FromArgb(220, 38, 38)
        doc = [System.Drawing.Color]::FromArgb(29, 78, 216)
        sheet = [System.Drawing.Color]::FromArgb(21, 128, 61)
        raw = [System.Drawing.Color]::FromArgb(79, 70, 229)
    }
    foreach ($key in $palette.Keys) {
        [void]$images.Images.Add($key, (New-FileIconImage -Kind $key -Accent $palette[$key]))
    }
    $script:FileImageList = $images
}

function Shift-Color {
    param(
        [System.Drawing.Color]$Color,
        [int]$Delta
    )
    $r = [Math]::Max(0, [Math]::Min(255, $Color.R + $Delta))
    $g = [Math]::Max(0, [Math]::Min(255, $Color.G + $Delta))
    $b = [Math]::Max(0, [Math]::Min(255, $Color.B + $Delta))
    return [System.Drawing.Color]::FromArgb($r, $g, $b)
}

function New-ActionIconImage {
    param([string]$Icon)
    $bitmap = [System.Drawing.Bitmap]::new(22, 22)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $pen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, 2.0)
    $thinPen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, 1.5)
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::White)
    $softBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(210, 255, 255, 255))

    switch ($Icon) {
        "camera" {
            $graphics.DrawRectangle($pen, 4, 7, 14, 10)
            $graphics.DrawRectangle($pen, 7, 5, 5, 3)
            $graphics.DrawEllipse($thinPen, 9, 9, 5, 5)
        }
        "screen" {
            $graphics.DrawRectangle($pen, 3, 5, 16, 11)
            $graphics.DrawLine($pen, 8, 19, 14, 19)
            $graphics.DrawLine($thinPen, 11, 16, 11, 19)
        }
        "eye" {
            $graphics.DrawArc($pen, 3, 7, 16, 9, 0, 180)
            $graphics.DrawArc($pen, 3, 6, 16, 9, 0, -180)
            $graphics.FillEllipse($brush, 9, 9, 4, 4)
        }
        "stop" {
            $graphics.FillRectangle($brush, 6, 6, 10, 10)
        }
        "status" {
            $graphics.FillEllipse($brush, 4, 13, 3, 3)
            $graphics.FillEllipse($brush, 10, 9, 3, 7)
            $graphics.FillEllipse($brush, 16, 5, 3, 11)
        }
        "folder" {
            $graphics.FillRectangle($softBrush, 3, 7, 16, 10)
            $graphics.FillRectangle($brush, 4, 5, 7, 4)
        }
        "terminal" {
            $graphics.DrawRectangle($pen, 3, 5, 16, 14)
            $graphics.DrawLine($thinPen, 6, 9, 10, 12)
            $graphics.DrawLine($thinPen, 10, 12, 6, 15)
            $graphics.DrawLine($thinPen, 12, 16, 17, 16)
        }
        "edit" {
            $graphics.DrawLine($pen, 6, 16, 15, 7)
            $graphics.DrawLine($pen, 14, 6, 17, 9)
            $graphics.DrawLine($thinPen, 5, 17, 9, 16)
        }
        "palette" {
            $graphics.DrawEllipse($pen, 4, 4, 15, 14)
            $graphics.FillEllipse($brush, 8, 7, 2, 2)
            $graphics.FillEllipse($brush, 13, 7, 2, 2)
            $graphics.FillEllipse($brush, 10, 12, 2, 2)
        }
        "touch" {
            $graphics.DrawRectangle($thinPen, 5, 3, 12, 16)
            $graphics.DrawLine($pen, 11, 8, 11, 16)
            $graphics.DrawLine($thinPen, 8, 14, 11, 17)
            $graphics.DrawLine($thinPen, 14, 14, 11, 17)
        }
        "apps" {
            $graphics.FillRectangle($brush, 4, 4, 5, 5)
            $graphics.FillRectangle($softBrush, 13, 4, 5, 5)
            $graphics.FillRectangle($softBrush, 4, 13, 5, 5)
            $graphics.FillRectangle($brush, 13, 13, 5, 5)
        }
        "desktop" {
            $graphics.DrawRectangle($pen, 3, 5, 16, 11)
            $graphics.FillRectangle($brush, 8, 18, 6, 2)
        }
        "transfer" {
            $graphics.DrawLine($pen, 5, 8, 16, 8)
            $graphics.DrawLine($pen, 13, 5, 16, 8)
            $graphics.DrawLine($pen, 13, 11, 16, 8)
            $graphics.DrawLine($pen, 17, 14, 6, 14)
            $graphics.DrawLine($pen, 9, 11, 6, 14)
            $graphics.DrawLine($pen, 9, 17, 6, 14)
        }
        "upload" {
            $graphics.DrawLine($pen, 11, 16, 11, 5)
            $graphics.DrawLine($pen, 7, 9, 11, 5)
            $graphics.DrawLine($pen, 15, 9, 11, 5)
            $graphics.DrawLine($thinPen, 5, 18, 17, 18)
        }
        "download" {
            $graphics.DrawLine($pen, 11, 5, 11, 16)
            $graphics.DrawLine($pen, 7, 12, 11, 16)
            $graphics.DrawLine($pen, 15, 12, 11, 16)
            $graphics.DrawLine($thinPen, 5, 18, 17, 18)
        }
        "refresh" {
            $graphics.DrawArc($pen, 5, 5, 12, 12, 35, 245)
            $graphics.DrawLine($pen, 15, 5, 18, 5)
            $graphics.DrawLine($pen, 18, 5, 18, 8)
        }
        "plus" {
            $graphics.DrawLine($pen, 11, 5, 11, 17)
            $graphics.DrawLine($pen, 5, 11, 17, 11)
        }
        "open" {
            $graphics.DrawRectangle($thinPen, 4, 7, 14, 12)
            $graphics.DrawLine($pen, 8, 14, 16, 6)
            $graphics.DrawLine($pen, 12, 6, 16, 6)
            $graphics.DrawLine($pen, 16, 6, 16, 10)
        }
        "notebook" {
            $graphics.DrawRectangle($pen, 5, 4, 13, 16)
            $graphics.DrawLine($thinPen, 8, 4, 8, 20)
            $graphics.DrawLine($thinPen, 10, 8, 16, 8)
            $graphics.DrawLine($thinPen, 10, 12, 16, 12)
        }
        "reboot" {
            $graphics.DrawArc($pen, 5, 5, 12, 12, 20, 310)
            $graphics.DrawLine($pen, 11, 3, 15, 6)
            $graphics.DrawLine($pen, 15, 6, 11, 9)
        }
        "power" {
            $graphics.DrawLine($pen, 11, 4, 11, 11)
            $graphics.DrawArc($pen, 5, 8, 12, 12, 135, 270)
        }
        default {
            $graphics.FillEllipse($brush, 5, 5, 12, 12)
        }
    }

    $pen.Dispose()
    $thinPen.Dispose()
    $brush.Dispose()
    $softBrush.Dispose()
    $graphics.Dispose()
    return $bitmap
}

function Initialize-ActionImages {
    $images = New-Object System.Windows.Forms.ImageList
    $images.ImageSize = [System.Drawing.Size]::new(22, 22)
    $images.ColorDepth = [System.Windows.Forms.ColorDepth]::Depth32Bit
    foreach ($icon in @(
        "camera", "screen", "eye", "stop", "status", "folder", "terminal", "edit",
        "palette", "touch", "apps", "desktop", "transfer", "upload", "download",
        "refresh", "plus", "open", "notebook", "reboot", "power"
    )) {
        [void]$images.Images.Add($icon, (New-ActionIconImage -Icon $icon))
    }
    $script:ActionImageList = $images
}

function Get-FileImageKey {
    param([string]$Name, [bool]$IsDirectory)
    if ($IsDirectory) {
        return "folder"
    }
    $extension = [System.IO.Path]::GetExtension($Name).ToLowerInvariant()
    switch ($extension) {
        { $_ -in @(".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tif", ".tiff", ".svg", ".webp") } { return "image" }
        { $_ -in @(".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v") } { return "video" }
        { $_ -in @(".wav", ".mp3", ".flac", ".aac", ".m4a", ".ogg") } { return "audio" }
        { $_ -in @(".zip", ".tar", ".gz", ".tgz", ".xz", ".7z", ".rar") } { return "archive" }
        ".pdf" { return "pdf" }
        { $_ -in @(".doc", ".docx", ".ppt", ".pptx") } { return "doc" }
        { $_ -in @(".xls", ".xlsx", ".csv", ".tsv") } { return "sheet" }
        { $_ -in @(".py", ".ps1", ".sh", ".c", ".cc", ".cpp", ".h", ".hpp", ".js", ".ts", ".html", ".css", ".json", ".xml", ".yaml", ".yml") } { return "code" }
        { $_ -in @(".txt", ".md", ".log", ".ini", ".cfg", ".conf") } { return "text" }
        { $_ -in @(".raw", ".dat", ".aedat", ".h5", ".hdf5", ".npy", ".npz", ".bin") } { return "raw" }
        default { return "file" }
    }
}

function Get-FileTypeLabel {
    param([string]$Name, [bool]$IsDirectory)
    if ($IsDirectory) {
        return "Folder"
    }
    $extension = [System.IO.Path]::GetExtension($Name).ToLowerInvariant()
    switch ($extension) {
        ".py" { return "Python" }
        ".ps1" { return "PowerShell" }
        ".sh" { return "Shell" }
        { $_ -in @(".c", ".cc", ".cpp", ".h", ".hpp") } { return "C/C++" }
        { $_ -in @(".json", ".xml", ".yaml", ".yml") } { return "Data" }
        { $_ -in @(".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tif", ".tiff", ".svg", ".webp") } { return "Image" }
        { $_ -in @(".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v") } { return "Video" }
        { $_ -in @(".wav", ".mp3", ".flac", ".aac", ".m4a", ".ogg") } { return "Audio" }
        { $_ -in @(".zip", ".tar", ".gz", ".tgz", ".xz", ".7z", ".rar") } { return "Archive" }
        ".pdf" { return "PDF" }
        { $_ -in @(".doc", ".docx", ".ppt", ".pptx") } { return "Office" }
        { $_ -in @(".xls", ".xlsx", ".csv", ".tsv") } { return "Table" }
        { $_ -in @(".txt", ".md", ".log", ".ini", ".cfg", ".conf") } { return "Text" }
        { $_ -in @(".raw", ".dat", ".aedat", ".h5", ".hdf5", ".npy", ".npz", ".bin") } { return "Capture" }
        "" { return "File" }
        default { return $extension.TrimStart(".").ToUpperInvariant() }
    }
}

Initialize-FileImages
Initialize-ActionImages

function Add-Log {
    param([string]$Text)
    Write-AppLog $Text
    $timestamp = Get-Date -Format "HH:mm:ss"
    if (Get-Variable -Name OutputBox -Scope Script -ErrorAction SilentlyContinue) {
        $script:OutputBox.AppendText("[$timestamp] $Text`r`n")
    }
}

function Format-FileSize {
    param([object]$Length)
    if ($null -eq $Length) {
        return ""
    }
    $size = [double]$Length
    $units = @("B", "KB", "MB", "GB", "TB")
    $index = 0
    while ($size -ge 1024 -and $index -lt ($units.Count - 1)) {
        $size = $size / 1024
        $index++
    }
    if ($index -eq 0) {
        return "{0:N0} B" -f $size
    }
    return "{0:N1} {1}" -f $size, $units[$index]
}

function ConvertTo-RemoteShellLiteral {
    param([string]$Value)
    return "'" + $Value.Replace("'", "'\''") + "'"
}

function ConvertTo-ScpRemoteSpec {
    param([string]$RemotePath)
    return "${HostAlias}:$(ConvertTo-RemoteShellLiteral $RemotePath)"
}

function Invoke-ScpCopy {
    param([string[]]$Arguments)
    $scp = Get-ScpExe
    Add-Log "scp $($Arguments -join ' ')"
    $code = Invoke-NativeNoCapture -FilePath $scp -Arguments $Arguments
    if ($code -ne 0) {
        throw "scp exited with code $code"
    }
}

function Invoke-FileAction {
    param([scriptblock]$Action)
    try {
        $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()
        & $Action
    } catch {
        Write-AppLog "Files exception:`r`n$($_ | Out-String)"
        Add-Log "Files: $($_.Exception.Message)"
        Show-Message $_.Exception.Message "KV260 File Transfer"
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

function New-FileListView {
    $list = New-Object System.Windows.Forms.ListView
    $list.View = [System.Windows.Forms.View]::Details
    $list.FullRowSelect = $true
    $list.MultiSelect = $true
    $list.HideSelection = $false
    $list.AllowDrop = $true
    $list.Anchor = "Top,Bottom,Left,Right"
    $list.SmallImageList = $script:FileImageList
    $list.ShowItemToolTips = $true
    [void]$list.Columns.Add("Name", 250)
    [void]$list.Columns.Add("Type", 72)
    [void]$list.Columns.Add("Size", 82)
    [void]$list.Columns.Add("Modified", 132)
    return $list
}

function Add-FileListRow {
    param(
        [System.Windows.Forms.ListView]$List,
        [string]$Name,
        [bool]$IsDirectory,
        [object]$Size,
        [object]$Modified,
        [string]$Path
    )
    $item = New-Object System.Windows.Forms.ListViewItem($Name)
    $item.ImageKey = Get-FileImageKey -Name $Name -IsDirectory $IsDirectory
    if ($IsDirectory) {
        $item.ForeColor = [System.Drawing.Color]::FromArgb(146, 64, 14)
        $item.Font = [System.Drawing.Font]::new($List.Font, [System.Drawing.FontStyle]::Bold)
    } else {
        $item.ForeColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
    }
    [void]$item.SubItems.Add((Get-FileTypeLabel -Name $Name -IsDirectory $IsDirectory))
    [void]$item.SubItems.Add($(if ($IsDirectory) { "" } else { Format-FileSize $Size }))
    $modifiedText = ""
    if ($Modified) {
        try {
            $modifiedText = ([DateTime]$Modified).ToString("yyyy-MM-dd HH:mm")
        } catch {
            $modifiedText = [string]$Modified
        }
    }
    [void]$item.SubItems.Add($modifiedText)
    $item.Tag = [pscustomobject]@{
        Path = $Path
        IsDirectory = $IsDirectory
    }
    $item.ToolTipText = $Path
    [void]$List.Items.Add($item)
}

function Get-DropDestinationDirectory {
    param(
        [System.Windows.Forms.ListView]$List,
        [string]$DefaultPath,
        [int]$X,
        [int]$Y
    )
    try {
        $point = $List.PointToClient([System.Drawing.Point]::new($X, $Y))
        $hit = $List.HitTest($point)
        if ($hit -and $hit.Item -and $hit.Item.Tag -and $hit.Item.Tag.IsDirectory) {
            return [string]$hit.Item.Tag.Path
        }
    } catch {
        Write-AppLog "Drop target resolution failed:`r`n$($_ | Out-String)"
    }
    return $DefaultPath
}

function Clear-DropFeedback {
    if ($script:DropHighlightedItem) {
        $script:DropHighlightedItem.BackColor = $script:DropHighlightedBackColor
        $script:DropHighlightedItem.ForeColor = $script:DropHighlightedForeColor
        $script:DropHighlightedItem = $null
        $script:DropHighlightedBackColor = $null
        $script:DropHighlightedForeColor = $null
    }
    if ($script:DropActiveList) {
        $script:DropActiveList.BackColor = $script:DropActiveListBackColor
        $script:DropActiveList = $null
        $script:DropActiveListBackColor = $null
    }
    if (Get-Variable -Name FileDropHint -Scope Script -ErrorAction SilentlyContinue) {
        $script:FileDropHint.Text = Get-Text "Drag files or rows onto a pane. Drop on a folder row to copy into that folder."
        $script:FileDropHint.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
    }
}

function Set-DropFeedback {
    param(
        [System.Windows.Forms.ListView]$List,
        [string]$DefaultPath,
        [int]$X,
        [int]$Y,
        [string]$PaneName
    )

    if (-not $script:DropActiveList -or -not [object]::ReferenceEquals($script:DropActiveList, $List)) {
        Clear-DropFeedback
        $script:DropActiveList = $List
        $script:DropActiveListBackColor = $List.BackColor
        $List.BackColor = [System.Drawing.Color]::FromArgb(248, 250, 255)
    }

    $targetItem = $null
    $targetPath = $DefaultPath
    try {
        $point = $List.PointToClient([System.Drawing.Point]::new($X, $Y))
        $hit = $List.HitTest($point)
        if ($hit -and $hit.Item -and $hit.Item.Tag -and $hit.Item.Tag.IsDirectory) {
            $targetItem = $hit.Item
            $targetPath = [string]$hit.Item.Tag.Path
        }
    } catch {
        Write-AppLog "Drop feedback resolution failed:`r`n$($_ | Out-String)"
    }

    if ($script:DropHighlightedItem -and -not [object]::ReferenceEquals($script:DropHighlightedItem, $targetItem)) {
        $script:DropHighlightedItem.BackColor = $script:DropHighlightedBackColor
        $script:DropHighlightedItem.ForeColor = $script:DropHighlightedForeColor
        $script:DropHighlightedItem = $null
    }

    if ($targetItem -and -not [object]::ReferenceEquals($script:DropHighlightedItem, $targetItem)) {
        $script:DropHighlightedItem = $targetItem
        $script:DropHighlightedBackColor = $targetItem.BackColor
        $script:DropHighlightedForeColor = $targetItem.ForeColor
        $targetItem.BackColor = [System.Drawing.Color]::FromArgb(254, 243, 199)
        $targetItem.ForeColor = [System.Drawing.Color]::FromArgb(120, 53, 15)
    }

    if (Get-Variable -Name FileDropHint -Scope Script -ErrorAction SilentlyContinue) {
        if ($targetItem) {
            $script:FileDropHint.Text = Format-Text "Drop target: {0} folder -> {1}" @($PaneName, $targetPath)
            $script:FileDropHint.ForeColor = [System.Drawing.Color]::FromArgb(146, 64, 14)
        } else {
            $script:FileDropHint.Text = Format-Text "Drop target: {0} current folder -> {1}" @($PaneName, $targetPath)
            $script:FileDropHint.ForeColor = [System.Drawing.Color]::FromArgb(29, 78, 216)
        }
    }

    return $targetPath
}

function Get-SelectedFileTags {
    param([System.Windows.Forms.ListView]$List)
    $tags = @()
    foreach ($item in $List.SelectedItems) {
        $tags += $item.Tag
    }
    return $tags
}

function Refresh-LocalFiles {
    Invoke-FileAction {
        $path = $script:LocalPathText.Text.Trim()
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Local path does not exist: $path"
        }
        $resolved = (Resolve-Path -LiteralPath $path).Path
        $script:LocalPathText.Text = $resolved
        $script:LocalList.Items.Clear()
        Get-ChildItem -Force -LiteralPath $resolved |
            Sort-Object -Property @{ Expression = { $_.PSIsContainer }; Descending = $true }, Name |
            ForEach-Object {
                Add-FileListRow `
                    -List $script:LocalList `
                    -Name $_.Name `
                    -IsDirectory $_.PSIsContainer `
                    -Size $_.Length `
                    -Modified $_.LastWriteTime `
                    -Path $_.FullName
            }
        Add-Log "Local refreshed: $resolved"
    }
}

function Get-KV260Directory {
    param([string]$Path)
    $project = ConvertTo-RemoteShellLiteral $RemoteProject
    $targetPath = ConvertTo-RemoteShellLiteral $Path
    $command = "cd $project && python3 scripts/kv260-list-files-json.py $targetPath"
    $json = Invoke-KV260Ssh $command
    return (ConvertFrom-JsonTail -Text $json -Context "KV260 directory listing")
}

if ($FilesSelfTest) {
    try {
        Write-AppLog "FilesSelfTest starting for $HostAlias $RemoteProject"
        $data = Get-KV260Directory $RemoteProject
        $iconProbe = New-FileListView
        Add-FileListRow -List $iconProbe -Name "folder-probe" -IsDirectory $true -Size 0 -Modified (Get-Date) -Path "/tmp/folder-probe"
        Add-FileListRow -List $iconProbe -Name "script-probe.py" -IsDirectory $false -Size 128 -Modified (Get-Date) -Path "/tmp/script-probe.py"
        Write-Host "KV260_PATH=$($data.path)"
        Write-Host "KV260_ITEMS=$(@($data.items).Count)"
        Write-Host "ICON_ITEMS=$($iconProbe.Items.Count)"
        Write-Host "CONTROL_LOG=$ControlLog"
        $iconProbe.Dispose()
        Write-AppLog "FilesSelfTest passed for $($data.path)"
        exit 0
    } catch {
        Write-AppLog "FilesSelfTest failed:`r`n$($_ | Out-String)"
        Write-Error $_.Exception.Message
        exit 1
    }
}

function Refresh-RemoteFiles {
    Invoke-FileAction {
        $path = $script:RemotePathText.Text.Trim()
        $data = Get-KV260Directory $path
        $script:RemotePathText.Text = $data.path
        $script:RemoteList.Items.Clear()
        foreach ($entry in @($data.items)) {
            $modified = $null
            if ($entry.mtime) {
                $modified = ([DateTimeOffset]::FromUnixTimeSeconds([int64]$entry.mtime)).LocalDateTime
            }
            Add-FileListRow `
                -List $script:RemoteList `
                -Name $entry.name `
                -IsDirectory ([bool]$entry.is_dir) `
                -Size $entry.size `
                -Modified $modified `
                -Path $entry.path
        }
        Add-Log "KV260 refreshed: $($data.path)"
    }
}

function Refresh-FileBrowsers {
    Refresh-LocalFiles
    Refresh-RemoteFiles
}

function Set-LocalParent {
    $path = $script:LocalPathText.Text.Trim()
    $parent = Split-Path -Parent $path
    if ($parent) {
        $script:LocalPathText.Text = $parent
        Refresh-LocalFiles
    }
}

function Set-RemoteParent {
    $path = $script:RemotePathText.Text.Trim().TrimEnd("/")
    $parent = Split-Path -Parent $path
    if ($parent) {
        $script:RemotePathText.Text = $parent.Replace("\", "/")
        Refresh-RemoteFiles
    }
}

function Upload-LocalPaths {
    param(
        [string[]]$Paths,
        [string]$DestinationDirectory = ""
    )
    if (-not $Paths -or $Paths.Count -eq 0) {
        Add-Log "Upload skipped: no local files selected."
        return
    }
    Invoke-FileAction {
        $remoteDir = if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
            $script:RemotePathText.Text.Trim()
        } else {
            $DestinationDirectory
        }
        $dest = (ConvertTo-ScpRemoteSpec $remoteDir) + "/"
        foreach ($path in $Paths) {
            Invoke-ScpCopy -Arguments @("-O", "-r", $path, $dest)
        }
        Add-Log "Uploaded $($Paths.Count) item(s) to $remoteDir"
        Refresh-RemoteFiles
    }
}

function Download-RemotePaths {
    param(
        [string[]]$Paths,
        [string]$DestinationDirectory = ""
    )
    if (-not $Paths -or $Paths.Count -eq 0) {
        Add-Log "Download skipped: no KV260 files selected."
        return
    }
    Invoke-FileAction {
        $localDir = if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
            $script:LocalPathText.Text.Trim()
        } else {
            $DestinationDirectory
        }
        foreach ($path in $Paths) {
            Invoke-ScpCopy -Arguments @("-O", "-r", (ConvertTo-ScpRemoteSpec $path), $localDir)
        }
        Add-Log "Downloaded $($Paths.Count) item(s) to $localDir"
        Refresh-LocalFiles
    }
}

function Upload-SelectedFiles {
    $paths = @(Get-SelectedFileTags $script:LocalList | ForEach-Object { $_.Path })
    Upload-LocalPaths $paths
}

function Download-SelectedFiles {
    $paths = @(Get-SelectedFileTags $script:RemoteList | ForEach-Object { $_.Path })
    Download-RemotePaths $paths
}

function Browse-LocalFolder {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.SelectedPath = $script:LocalPathText.Text
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:LocalPathText.Text = $dialog.SelectedPath
        Refresh-LocalFiles
    }
}

function New-RemoteFolder {
    $name = [Microsoft.VisualBasic.Interaction]::InputBox("Folder name:", "New KV260 Folder", "new-folder")
    if ([string]::IsNullOrWhiteSpace($name)) {
        return
    }
    Invoke-FileAction {
        $base = $script:RemotePathText.Text.Trim().TrimEnd("/")
        $target = "$base/$name"
        Invoke-KV260Ssh "mkdir -p $(ConvertTo-RemoteShellLiteral $target)" | Out-Null
        Add-Log "Created remote folder: $target"
        Refresh-RemoteFiles
    }
}

function Show-Message {
    param([string]$Text, [string]$Title = "KV260 Control Center")
    [System.Windows.Forms.MessageBox]::Show($Text, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
}

function Confirm-Action {
    param([string]$Text)
    $result = [System.Windows.Forms.MessageBox]::Show($Text, "KV260 Control Center", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    return $result -eq [System.Windows.Forms.DialogResult]::Yes
}

function Ensure-VcXsrv {
    $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
    $candidates = @(
        (Join-Path $env:ProgramFiles "VcXsrv\vcxsrv.exe"),
        (Join-Path $programFilesX86 "VcXsrv\vcxsrv.exe")
    )
    $vcxsrv = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $vcxsrv) {
        throw "VcXsrv is not installed. Install VcXsrv, then try again."
    }
    if (-not (Get-Process -Name vcxsrv -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $vcxsrv -ArgumentList @(":0", "-multiwindow", "-clipboard", "-wgl", "-ac")
        Start-Sleep -Seconds 2
    }
    $env:DISPLAY = "localhost:0.0"
    return $vcxsrv
}

function Start-RemoteX11Command {
    param([string]$RemoteCommand, [string]$LogName)
    Ensure-VcXsrv | Out-Null
    $ssh = Get-SshExe
    $logFile = Join-Path $LogDir $LogName
    "[$(Get-Date -Format s)] ssh -Y $HostAlias $RemoteCommand" | Out-File -FilePath $logFile -Append -Encoding utf8
    Start-Process `
        -FilePath $ssh `
        -ArgumentList @("-q", "-Y", "-o", "ForwardX11Trusted=yes", "-o", "BatchMode=yes", $HostAlias, $RemoteCommand) `
        -WindowStyle Hidden
}

function Refresh-Status {
    try {
        $camera = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-event-camera-switch.sh --status"
        $apps = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-remote-gui-app.sh --list"
        $jupyter = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-jupyter-notebook.sh --status"
        $vcxsrv = if (Get-Process -Name vcxsrv -ErrorAction SilentlyContinue) { "running" } else { "not running" }
        Add-Log "Status:`r`n$camera`r`n$jupyter`r`nVcXsrv: $vcxsrv`r`nApps:`r`n$apps"
    } catch {
        Add-Log "Status failed: $($_.Exception.Message)"
    }
}

function Start-BoardDesktop {
    try {
        Add-Log "Switching camera to KV260 display..."
        & $BoardScript -HostAlias $HostAlias -RemoteProject $RemoteProject
        Add-Log "Requested KV260 display mode. The GUI should appear on the board monitor."
        Refresh-Status
    } catch {
        Add-Log "Board display launch failed: $($_.Exception.Message)"
    }
}

function Start-WindowsX11 {
    try {
        Add-Log "Switching camera to Windows X11..."
        & $X11Script -HostAlias $HostAlias -RemoteProject $RemoteProject
        Add-Log "Requested Windows X11 mode. The GUI should appear on this Windows desktop."
        Refresh-Status
    } catch {
        Add-Log "Windows X11 launch failed: $($_.Exception.Message)"
    }
}

function Stop-AllViewers {
    try {
        Add-Log "Stopping all camera viewers..."
        $result = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-event-camera-switch.sh --stop-all && ./scripts/kv260-event-camera-switch.sh --status"
        Add-Log $result
    } catch {
        Add-Log "Stop failed: $($_.Exception.Message)"
    }
}

function Open-RemoteApp {
    param([string]$AppId, [string]$Label)
    try {
        Add-Log "Opening $Label through SSH X11..."
        $check = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-remote-gui-app.sh --check $AppId"
        Add-Log $check
        Start-RemoteX11Command "cd $RemoteProject && ./scripts/kv260-remote-gui-app.sh --launch $AppId" "x11-app-$AppId.log"
    } catch {
        Add-Log "Could not open ${Label}: $($_.Exception.Message)"
    }
}

function Get-TunnelProcesses {
    Get-CimInstance Win32_Process -Filter "Name = 'ssh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*-L ${JupyterLocalPort}:127.0.0.1:8888*" -and $_.CommandLine -like "*$HostAlias*" }
}

function Start-Jupyter {
    try {
        Add-Log "Starting Jupyter on KV260..."
        $server = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-jupyter-notebook.sh --start"
        Add-Log $server

        if (-not (Get-TunnelProcesses)) {
            $ssh = Get-SshExe
            Start-Process `
                -FilePath $ssh `
                -ArgumentList @("-q", "-N", "-L", "${JupyterLocalPort}:127.0.0.1:8888", $HostAlias) `
                -WindowStyle Hidden
            Start-Sleep -Seconds 1
            Add-Log "Opened SSH tunnel: http://127.0.0.1:${JupyterLocalPort}/tree"
        } else {
            Add-Log "SSH tunnel already exists: http://127.0.0.1:${JupyterLocalPort}/tree"
        }
        Start-Process "http://127.0.0.1:${JupyterLocalPort}/tree"
    } catch {
        Add-Log "Jupyter launch failed: $($_.Exception.Message)"
    }
}

function Stop-Jupyter {
    try {
        Add-Log "Stopping Jupyter and its Windows SSH tunnel..."
        Get-TunnelProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        $result = Invoke-KV260Ssh "cd $RemoteProject && ./scripts/kv260-jupyter-notebook.sh --stop"
        Add-Log $result
    } catch {
        Add-Log "Jupyter stop failed: $($_.Exception.Message)"
    }
}

function Read-SudoPassword {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "KV260 sudo password"
    $dialog.StartPosition = "CenterParent"
    $dialog.Size = New-Object System.Drawing.Size(360, 150)
    $dialog.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Enter the KV260 sudo password:"
    $label.Location = New-Object System.Drawing.Point(14, 16)
    $label.Size = New-Object System.Drawing.Size(320, 20)
    $dialog.Controls.Add($label)

    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point(16, 42)
    $box.Size = New-Object System.Drawing.Size(310, 22)
    $box.UseSystemPasswordChar = $true
    $dialog.Controls.Add($box)

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = "OK"
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(170, 78)
    $dialog.Controls.Add($ok)

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.Location = New-Object System.Drawing.Point(252, 78)
    $dialog.Controls.Add($cancel)

    $dialog.AcceptButton = $ok
    $dialog.CancelButton = $cancel
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        return $box.Text
    }
    return $null
}

function Invoke-SudoAction {
    param([string]$RemoteCommand, [string]$ActionName)
    if (-not (Confirm-Action "This will $ActionName the KV260. Continue?")) {
        return
    }
    $password = Read-SudoPassword
    if ($null -eq $password) {
        Add-Log "$ActionName cancelled."
        return
    }

    try {
        $ssh = Get-SshExe
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ssh
        $psi.Arguments = "-o BatchMode=no $HostAlias `"sudo -S -p '' $RemoteCommand`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        [void]$process.Start()
        $process.StandardInput.WriteLine($password)
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit(8000) | Out-Null
        Add-Log "$ActionName requested. stdout=$stdout stderr=$stderr"
    } catch {
        Add-Log "$ActionName failed: $($_.Exception.Message)"
    }
}

function Reboot-KV260 {
    Invoke-SudoAction "/sbin/reboot" "reboot"
}

function Shutdown-KV260 {
    Invoke-SudoAction "/sbin/poweroff" "shut down"
}

[System.Windows.Forms.Application]::EnableVisualStyles()
$script:ToolTip = New-Object System.Windows.Forms.ToolTip
$script:ToolTip.InitialDelay = 350
$script:ToolTip.ReshowDelay = 100
$script:ToolTip.AutoPopDelay = 5000
$script:ToolTip.ShowAlways = $true

$form = New-Object System.Windows.Forms.Form
Register-LocalizedControl "KV260 Control Center" $form
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1120, 760)
$form.MinimumSize = New-Object System.Drawing.Size(1040, 680)
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 251)

$title = New-Object System.Windows.Forms.Label
Register-LocalizedControl "KV260 Control Center" $title
$title.Font = New-Object System.Drawing.Font("Segoe UI", 21, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$title.Location = New-Object System.Drawing.Point(84, 16)
$title.Size = New-Object System.Drawing.Size(520, 38)
$form.Controls.Add($title)

$brandPanel = New-Object System.Windows.Forms.Panel
$brandPanel.Location = New-Object System.Drawing.Point(24, 16)
$brandPanel.Size = New-Object System.Drawing.Size(46, 46)
$brandPanel.BackColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$brandPanel.Cursor = [System.Windows.Forms.Cursors]::Default
$brandIcon = New-Object System.Windows.Forms.PictureBox
$brandIcon.Image = $script:ActionImageList.Images["transfer"]
$brandIcon.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::CenterImage
$brandIcon.Dock = [System.Windows.Forms.DockStyle]::Fill
$brandPanel.Controls.Add($brandIcon)
$form.Controls.Add($brandPanel)

$subtitle = New-Object System.Windows.Forms.Label
Register-LocalizedControl "Launch the event camera, board tools, notebooks, and system actions from one Windows entry point." $subtitle
$subtitle.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
$subtitle.Location = New-Object System.Drawing.Point(86, 54)
$subtitle.Size = New-Object System.Drawing.Size(980, 22)
$form.Controls.Add($subtitle)

$brandCredit = New-Object System.Windows.Forms.Label
Register-LocalizedControl "Powered by AgInTi Flow - created by LazyingArt LLC - flow.lazying.art" $brandCredit
$brandCredit.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$brandCredit.ForeColor = [System.Drawing.Color]::FromArgb(37, 99, 235)
$brandCredit.Location = New-Object System.Drawing.Point(86, 74)
$brandCredit.Size = New-Object System.Drawing.Size(980, 18)
$form.Controls.Add($brandCredit)

$languageLabel = New-Object System.Windows.Forms.Label
Register-LocalizedControl "Language" $languageLabel
$languageLabel.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$languageLabel.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
$languageLabel.Location = New-Object System.Drawing.Point(812, 20)
$languageLabel.Size = New-Object System.Drawing.Size(86, 20)
$languageLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$form.Controls.Add($languageLabel)

$script:LanguageCombo = New-Object System.Windows.Forms.ComboBox
$script:LanguageCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$script:LanguageCombo.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$script:LanguageCombo.Location = New-Object System.Drawing.Point(906, 18)
$script:LanguageCombo.Size = New-Object System.Drawing.Size(178, 24)
foreach ($entry in $script:SupportedLanguages) {
    [void]$script:LanguageCombo.Items.Add($entry.Name)
}
$selectedLanguageIndex = 0
for ($i = 0; $i -lt $script:SupportedLanguages.Count; $i++) {
    if ($script:SupportedLanguages[$i].Code -eq $script:CurrentLanguage) {
        $selectedLanguageIndex = $i
        break
    }
}
$script:LanguageCombo.SelectedIndex = $selectedLanguageIndex
$script:LanguageCombo.Add_SelectedIndexChanged({
    if ($script:LanguageCombo.SelectedIndex -ge 0) {
        Set-ControlLanguage $script:SupportedLanguages[$script:LanguageCombo.SelectedIndex].Code
    }
})
$form.Controls.Add($script:LanguageCombo)

function New-Button {
    param(
        [string]$Text,
        [System.Drawing.Color]$BackColor,
        [string]$Icon = ""
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Size = New-Object System.Drawing.Size(174, 42)
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $button.BackColor = $BackColor
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.FlatAppearance.MouseOverBackColor = Shift-Color -Color $BackColor -Delta 18
    $button.FlatAppearance.MouseDownBackColor = Shift-Color -Color $BackColor -Delta -24
    $button.Margin = New-Object System.Windows.Forms.Padding(6)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $button.ImageAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $button.TextImageRelation = [System.Windows.Forms.TextImageRelation]::ImageBeforeText
    $button.Padding = New-Object System.Windows.Forms.Padding(10, 0, 10, 0)
    if ($Icon -and $script:ActionImageList.Images.ContainsKey($Icon)) {
        $button.Image = $script:ActionImageList.Images[$Icon]
    }
    Register-LocalizedControl $Text $button
    return $button
}

function New-CompactIconButton {
    param(
        [string]$Text,
        [System.Drawing.Color]$BackColor,
        [string]$Icon = ""
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Size = New-Object System.Drawing.Size(34, 28)
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $button.BackColor = $BackColor
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.FlatAppearance.MouseOverBackColor = Shift-Color -Color $BackColor -Delta 18
    $button.FlatAppearance.MouseDownBackColor = Shift-Color -Color $BackColor -Delta -24
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Text = ""
    $button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $button.ImageAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $button.TextImageRelation = [System.Windows.Forms.TextImageRelation]::Overlay
    $button.Padding = New-Object System.Windows.Forms.Padding(0)
    if ($Icon -and $script:ActionImageList.Images.ContainsKey($Icon)) {
        $button.Image = $script:ActionImageList.Images[$Icon]
    }
    Register-LocalizedToolTip $Text $button
    return $button
}

function New-TransferArrowButton {
    param(
        [string]$Arrow,
        [string]$ToolTipKey,
        [System.Drawing.Color]$BackColor
    )
    $button = New-Object System.Windows.Forms.Button
    $button.Size = New-Object System.Drawing.Size(58, 44)
    $button.Font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
    $button.BackColor = $BackColor
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.FlatAppearance.MouseOverBackColor = Shift-Color -Color $BackColor -Delta 18
    $button.FlatAppearance.MouseDownBackColor = Shift-Color -Color $BackColor -Delta -24
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Text = $Arrow
    $button.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    Register-LocalizedToolTip $ToolTipKey $button
    return $button
}

function Add-ButtonToPanel {
    param(
        [System.Windows.Forms.FlowLayoutPanel]$Panel,
        [string]$Text,
        [System.Drawing.Color]$Color,
        [scriptblock]$Action,
        [string]$Icon = ""
    )
    $button = New-Button $Text $Color $Icon
    $button.Add_Click($Action)
    $Panel.Controls.Add($button)
}

function New-FlowPanel {
    $panel = New-Object System.Windows.Forms.FlowLayoutPanel
    $panel.Dock = [System.Windows.Forms.DockStyle]::Fill
    $panel.Padding = New-Object System.Windows.Forms.Padding(14)
    $panel.AutoScroll = $true
    $panel.BackColor = [System.Drawing.Color]::White
    return $panel
}

if ($UiSelfTest) {
    $probe = New-Button "Probe Button" ([System.Drawing.Color]::FromArgb(37, 99, 235)) "camera"
    $compactProbe = New-CompactIconButton "Refresh" ([System.Drawing.Color]::FromArgb(71, 85, 105)) "refresh"
    $arrowProbe = New-TransferArrowButton ">>" "Copy KV260 -> Windows" ([System.Drawing.Color]::FromArgb(37, 99, 235))
    Write-Host "ACTION_IMAGES=$($script:ActionImageList.Images.Count)"
    Write-Host "PROBE_HAS_IMAGE=$($null -ne $probe.Image)"
    Write-Host "PROBE_TEXT=$($probe.Text)"
    Write-Host "COMPACT_HAS_IMAGE=$($null -ne $compactProbe.Image)"
    Write-Host "COMPACT_TEXT_LENGTH=$($compactProbe.Text.Length)"
    Write-Host "COMPACT_TOOLTIP=$($script:ToolTip.GetToolTip($compactProbe))"
    Write-Host "ARROW_TEXT=$($arrowProbe.Text)"
    Write-Host "ARROW_TOOLTIP=$($script:ToolTip.GetToolTip($arrowProbe))"
    Write-Host "BRAND_TEXT=$($brandCredit.Text)"
    $arrowProbe.Dispose()
    $compactProbe.Dispose()
    $probe.Dispose()
    $form.Dispose()
    exit 0
}

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(24, 92)
$tabs.Size = New-Object System.Drawing.Size(1060, 416)
$tabs.Anchor = "Top,Left,Right"
$tabs.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($tabs)

$cameraTab = New-Object System.Windows.Forms.TabPage
Register-LocalizedControl "Camera" $cameraTab
$cameraPanel = New-FlowPanel
$cameraTab.Controls.Add($cameraPanel)
$tabs.TabPages.Add($cameraTab)

Add-ButtonToPanel $cameraPanel "Open Camera On Windows" ([System.Drawing.Color]::FromArgb(37, 99, 235)) { Start-WindowsX11 } "screen"
Add-ButtonToPanel $cameraPanel "Open Camera On KV260" ([System.Drawing.Color]::FromArgb(5, 150, 105)) { Start-BoardDesktop } "camera"
Add-ButtonToPanel $cameraPanel "Native Metavision Viewer" ([System.Drawing.Color]::FromArgb(79, 70, 229)) { Open-RemoteApp "native-metavision" "Native Metavision Viewer" } "eye"
Add-ButtonToPanel $cameraPanel "Stop Camera Viewers" ([System.Drawing.Color]::FromArgb(220, 38, 38)) { Stop-AllViewers } "stop"
Add-ButtonToPanel $cameraPanel "Status" ([System.Drawing.Color]::FromArgb(71, 85, 105)) { Refresh-Status } "status"

$appsTab = New-Object System.Windows.Forms.TabPage
Register-LocalizedControl "Applications" $appsTab
$appsPanel = New-FlowPanel
$appsTab.Controls.Add($appsPanel)
$tabs.TabPages.Add($appsTab)

Add-ButtonToPanel $appsPanel "File Manager" ([System.Drawing.Color]::FromArgb(14, 116, 144)) { Open-RemoteApp "pcmanfm" "File Manager" } "folder"
Add-ButtonToPanel $appsPanel "Terminal" ([System.Drawing.Color]::FromArgb(51, 65, 85)) { Open-RemoteApp "terminal" "Terminal" } "terminal"
Add-ButtonToPanel $appsPanel "RXVT Terminal" ([System.Drawing.Color]::FromArgb(71, 85, 105)) { Open-RemoteApp "terminal-rxvt" "RXVT Terminal" } "terminal"
Add-ButtonToPanel $appsPanel "Text Editor" ([System.Drawing.Color]::FromArgb(22, 101, 52)) { Open-RemoteApp "editor" "L3afpad Text Editor" } "edit"
Add-ButtonToPanel $appsPanel "Appearance" ([System.Drawing.Color]::FromArgb(124, 58, 237)) { Open-RemoteApp "appearance" "Appearance" } "palette"
Add-ButtonToPanel $appsPanel "Touch Calibrator" ([System.Drawing.Color]::FromArgb(217, 119, 6)) { Open-RemoteApp "touch-calibrator" "Touch Calibrator" } "touch"
Add-ButtonToPanel $appsPanel "Preferred Apps" ([System.Drawing.Color]::FromArgb(8, 145, 178)) { Open-RemoteApp "preferred-apps" "Preferred Applications" } "apps"
Add-ButtonToPanel $appsPanel "Desktop Preferences" ([System.Drawing.Color]::FromArgb(67, 56, 202)) { Open-RemoteApp "desktop-preferences" "Desktop Preferences" } "desktop"
Add-ButtonToPanel $appsPanel "File Transfer GUI" ([System.Drawing.Color]::FromArgb(37, 99, 235)) { Open-RemoteApp "file-transfer" "KV260 File Transfer" } "transfer"

$filesTab = New-Object System.Windows.Forms.TabPage
Register-LocalizedControl "Files" $filesTab
$tabs.TabPages.Add($filesTab)

$filesHeader = New-Object System.Windows.Forms.Label
Register-LocalizedControl "Copy files and folders between the KV260 board on the left and the Windows/remote host on the right." $filesHeader
$filesHeader.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$filesHeader.ForeColor = [System.Drawing.Color]::FromArgb(71, 85, 105)
$filesHeader.Location = New-Object System.Drawing.Point(14, 12)
$filesHeader.Size = New-Object System.Drawing.Size(1020, 22)
$filesHeader.Anchor = "Top,Left,Right"
$filesTab.Controls.Add($filesHeader)

$localLabel = New-Object System.Windows.Forms.Label
Register-LocalizedControl "KV260 Board" $localLabel
$localLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$localLabel.Location = New-Object System.Drawing.Point(14, 42)
$localLabel.Size = New-Object System.Drawing.Size(120, 22)
$filesTab.Controls.Add($localLabel)

$remoteLabel = New-Object System.Windows.Forms.Label
Register-LocalizedControl "Windows / Remote Host" $remoteLabel
$remoteLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$remoteLabel.Location = New-Object System.Drawing.Point(532, 42)
$remoteLabel.Size = New-Object System.Drawing.Size(220, 22)
$filesTab.Controls.Add($remoteLabel)

$script:LocalPathText = New-Object System.Windows.Forms.TextBox
$script:LocalPathText.Text = [Environment]::GetFolderPath("MyDocuments")
$script:LocalPathText.Location = New-Object System.Drawing.Point(532, 68)
$script:LocalPathText.Size = New-Object System.Drawing.Size(376, 24)
$script:LocalPathText.Anchor = "Top,Left,Right"
$script:LocalPathText.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Refresh-LocalFiles
        $_.SuppressKeyPress = $true
    }
})
$filesTab.Controls.Add($script:LocalPathText)

$localRefresh = New-CompactIconButton "Refresh" ([System.Drawing.Color]::FromArgb(71, 85, 105)) "refresh"
$localRefresh.Location = New-Object System.Drawing.Point(916, 66)
$localRefresh.Anchor = "Top,Right"
$localRefresh.Add_Click({ Refresh-LocalFiles })
$filesTab.Controls.Add($localRefresh)

$localUp = New-CompactIconButton "Up" ([System.Drawing.Color]::FromArgb(71, 85, 105)) "upload"
$localUp.Location = New-Object System.Drawing.Point(954, 66)
$localUp.Anchor = "Top,Right"
$localUp.Add_Click({ Set-LocalParent })
$filesTab.Controls.Add($localUp)

$localBrowse = New-CompactIconButton "Browse" ([System.Drawing.Color]::FromArgb(14, 116, 144)) "folder"
$localBrowse.Location = New-Object System.Drawing.Point(992, 66)
$localBrowse.Anchor = "Top,Right"
$localBrowse.Add_Click({ Browse-LocalFolder })
$filesTab.Controls.Add($localBrowse)

$script:RemotePathText = New-Object System.Windows.Forms.TextBox
$script:RemotePathText.Text = $RemoteProject
$script:RemotePathText.Location = New-Object System.Drawing.Point(14, 68)
$script:RemotePathText.Size = New-Object System.Drawing.Size(398, 24)
$script:RemotePathText.Anchor = "Top,Left"
$script:RemotePathText.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
        Refresh-RemoteFiles
        $_.SuppressKeyPress = $true
    }
})
$filesTab.Controls.Add($script:RemotePathText)

$remoteRefresh = New-CompactIconButton "Refresh" ([System.Drawing.Color]::FromArgb(71, 85, 105)) "refresh"
$remoteRefresh.Location = New-Object System.Drawing.Point(420, 66)
$remoteRefresh.Add_Click({ Refresh-RemoteFiles })
$filesTab.Controls.Add($remoteRefresh)

$remoteUp = New-CompactIconButton "Up" ([System.Drawing.Color]::FromArgb(71, 85, 105)) "upload"
$remoteUp.Location = New-Object System.Drawing.Point(458, 66)
$remoteUp.Add_Click({ Set-RemoteParent })
$filesTab.Controls.Add($remoteUp)

$script:LocalList = New-FileListView
$script:LocalList.Location = New-Object System.Drawing.Point(532, 102)
$script:LocalList.Size = New-Object System.Drawing.Size(510, 220)
$script:LocalList.Add_DoubleClick({
    if ($script:LocalList.SelectedItems.Count -eq 1) {
        $tag = $script:LocalList.SelectedItems[0].Tag
        if ($tag.IsDirectory) {
            $script:LocalPathText.Text = $tag.Path
            Refresh-LocalFiles
        }
    }
})
$script:LocalList.Add_ItemDrag({
    $paths = @(Get-SelectedFileTags $script:LocalList | ForEach-Object { $_.Path })
    if ($paths.Count -gt 0) {
        $data = New-Object System.Windows.Forms.DataObject
        $data.SetData("HostPaths", ($paths -join "`n"))
        [void]$script:LocalList.DoDragDrop($data, [System.Windows.Forms.DragDropEffects]::Copy)
    }
})
$script:LocalList.Add_DragEnter({
    if ($_.Data.GetDataPresent("BoardPaths")) {
        $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy
        [void](Set-DropFeedback -List $script:LocalList -DefaultPath $script:LocalPathText.Text.Trim() -X $_.X -Y $_.Y -PaneName "Windows")
    }
})
$script:LocalList.Add_DragOver({
    if ($_.Data.GetDataPresent("BoardPaths")) {
        $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy
        [void](Set-DropFeedback -List $script:LocalList -DefaultPath $script:LocalPathText.Text.Trim() -X $_.X -Y $_.Y -PaneName "Windows")
    }
})
$script:LocalList.Add_DragLeave({
    Clear-DropFeedback
})
$script:LocalList.Add_DragDrop({
    if ($_.Data.GetDataPresent("BoardPaths")) {
        $paths = ([string]$_.Data.GetData("BoardPaths")) -split "`n" | Where-Object { $_ }
        $target = Get-DropDestinationDirectory `
            -List $script:LocalList `
            -DefaultPath $script:LocalPathText.Text.Trim() `
            -X $_.X `
            -Y $_.Y
        Clear-DropFeedback
        Download-RemotePaths $paths $target
    }
})
$filesTab.Controls.Add($script:LocalList)

$script:RemoteList = New-FileListView
$script:RemoteList.Location = New-Object System.Drawing.Point(14, 102)
$script:RemoteList.Size = New-Object System.Drawing.Size(500, 220)
$script:RemoteList.Anchor = "Top,Bottom,Left"
$script:RemoteList.Add_DoubleClick({
    if ($script:RemoteList.SelectedItems.Count -eq 1) {
        $tag = $script:RemoteList.SelectedItems[0].Tag
        if ($tag.IsDirectory) {
            $script:RemotePathText.Text = $tag.Path
            Refresh-RemoteFiles
        }
    }
})
$script:RemoteList.Add_ItemDrag({
    $paths = @(Get-SelectedFileTags $script:RemoteList | ForEach-Object { $_.Path })
    if ($paths.Count -gt 0) {
        $data = New-Object System.Windows.Forms.DataObject
        $data.SetData("BoardPaths", ($paths -join "`n"))
        [void]$script:RemoteList.DoDragDrop($data, [System.Windows.Forms.DragDropEffects]::Copy)
    }
})
$script:RemoteList.Add_DragEnter({
    if ($_.Data.GetDataPresent("HostPaths") -or $_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy
        [void](Set-DropFeedback -List $script:RemoteList -DefaultPath $script:RemotePathText.Text.Trim() -X $_.X -Y $_.Y -PaneName "KV260")
    }
})
$script:RemoteList.Add_DragOver({
    if ($_.Data.GetDataPresent("HostPaths") -or $_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $_.Effect = [System.Windows.Forms.DragDropEffects]::Copy
        [void](Set-DropFeedback -List $script:RemoteList -DefaultPath $script:RemotePathText.Text.Trim() -X $_.X -Y $_.Y -PaneName "KV260")
    }
})
$script:RemoteList.Add_DragLeave({
    Clear-DropFeedback
})
$script:RemoteList.Add_DragDrop({
    $target = Get-DropDestinationDirectory `
        -List $script:RemoteList `
        -DefaultPath $script:RemotePathText.Text.Trim() `
        -X $_.X `
        -Y $_.Y
    Clear-DropFeedback
    if ($_.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $paths = [string[]]$_.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        Upload-LocalPaths $paths $target
    } elseif ($_.Data.GetDataPresent("HostPaths")) {
        $paths = ([string]$_.Data.GetData("HostPaths")) -split "`n" | Where-Object { $_ }
        Upload-LocalPaths $paths $target
    }
})
$filesTab.Controls.Add($script:RemoteList)

$uploadButton = New-TransferArrowButton "<<" "Copy Windows -> KV260" ([System.Drawing.Color]::FromArgb(5, 150, 105))
$uploadButton.Location = New-Object System.Drawing.Point(14, 334)
$uploadButton.Add_Click({ Upload-SelectedFiles })
$filesTab.Controls.Add($uploadButton)

$downloadButton = New-TransferArrowButton ">>" "Copy KV260 -> Windows" ([System.Drawing.Color]::FromArgb(37, 99, 235))
$downloadButton.Location = New-Object System.Drawing.Point(210, 334)
$downloadButton.Add_Click({ Download-SelectedFiles })
$filesTab.Controls.Add($downloadButton)

$refreshFilesButton = New-Button "Refresh Both" ([System.Drawing.Color]::FromArgb(71, 85, 105)) "refresh"
$refreshFilesButton.Location = New-Object System.Drawing.Point(406, 334)
$refreshFilesButton.Size = New-Object System.Drawing.Size(130, 34)
$refreshFilesButton.Add_Click({ Refresh-FileBrowsers })
$filesTab.Controls.Add($refreshFilesButton)

$newRemoteFolder = New-Button "New KV260 Folder" ([System.Drawing.Color]::FromArgb(217, 119, 6)) "plus"
$newRemoteFolder.Location = New-Object System.Drawing.Point(542, 334)
$newRemoteFolder.Size = New-Object System.Drawing.Size(166, 34)
$newRemoteFolder.Add_Click({ New-RemoteFolder })
$filesTab.Controls.Add($newRemoteFolder)

$openBoardTransfer = New-Button "Open Board Transfer GUI" ([System.Drawing.Color]::FromArgb(79, 70, 229)) "open"
$openBoardTransfer.Location = New-Object System.Drawing.Point(714, 334)
$openBoardTransfer.Size = New-Object System.Drawing.Size(212, 34)
$openBoardTransfer.Add_Click({ Open-RemoteApp "file-transfer" "KV260 File Transfer" })
$filesTab.Controls.Add($openBoardTransfer)

$script:FileDropHint = New-Object System.Windows.Forms.Label
Register-LocalizedControl "Drag files or rows onto a pane. Drop on a folder row to copy into that folder." $script:FileDropHint
$script:FileDropHint.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$script:FileDropHint.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$script:FileDropHint.Location = New-Object System.Drawing.Point(14, 374)
$script:FileDropHint.Size = New-Object System.Drawing.Size(1020, 20)
$script:FileDropHint.Anchor = "Top,Left,Right"
$filesTab.Controls.Add($script:FileDropHint)

$notebookTab = New-Object System.Windows.Forms.TabPage
Register-LocalizedControl "Notebook And Power" $notebookTab
$notebookPanel = New-FlowPanel
$notebookTab.Controls.Add($notebookPanel)
$tabs.TabPages.Add($notebookTab)

Add-ButtonToPanel $notebookPanel "Open Jupyter Notebook" ([System.Drawing.Color]::FromArgb(234, 88, 12)) { Start-Jupyter } "notebook"
Add-ButtonToPanel $notebookPanel "Stop Jupyter" ([System.Drawing.Color]::FromArgb(194, 65, 12)) { Stop-Jupyter } "stop"
Add-ButtonToPanel $notebookPanel "Reboot KV260" ([System.Drawing.Color]::FromArgb(185, 28, 28)) { Reboot-KV260 } "reboot"
Add-ButtonToPanel $notebookPanel "Shutdown KV260" ([System.Drawing.Color]::FromArgb(127, 29, 29)) { Shutdown-KV260 } "power"

$script:OutputBox = New-Object System.Windows.Forms.TextBox
$script:OutputBox.Location = New-Object System.Drawing.Point(24, 524)
$script:OutputBox.Size = New-Object System.Drawing.Size(1060, 126)
$script:OutputBox.Anchor = "Top,Bottom,Left,Right"
$script:OutputBox.Multiline = $true
$script:OutputBox.ReadOnly = $true
$script:OutputBox.ScrollBars = "Vertical"
$script:OutputBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$script:OutputBox.BackColor = [System.Drawing.Color]::FromArgb(15, 23, 42)
$script:OutputBox.ForeColor = [System.Drawing.Color]::FromArgb(226, 232, 240)
$form.Controls.Add($script:OutputBox)

$footer = New-Object System.Windows.Forms.Label
Register-LocalizedControl "Windows X11 apps use VcXsrv. Camera apps are exclusive because /dev/video0 can have only one owner." $footer
$footer.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$footer.ForeColor = [System.Drawing.Color]::FromArgb(100, 116, 139)
$footer.Location = New-Object System.Drawing.Point(24, 666)
$footer.Size = New-Object System.Drawing.Size(1060, 20)
$footer.Anchor = "Bottom,Left,Right"
$form.Controls.Add($footer)

function Resize-FileListColumns {
    param(
        [System.Windows.Forms.ListView]$List,
        [int]$Width
    )
    if (-not $List -or $List.Columns.Count -lt 4) {
        return
    }
    $typeWidth = 74
    $sizeWidth = 84
    $modifiedWidth = 132
    $padding = 32
    $nameWidth = [Math]::Max(160, $Width - $typeWidth - $sizeWidth - $modifiedWidth - $padding)
    $List.Columns[0].Width = $nameWidth
    $List.Columns[1].Width = $typeWidth
    $List.Columns[2].Width = $sizeWidth
    $List.Columns[3].Width = $modifiedWidth
}

function Apply-FilesTabLayout {
    if (-not (Get-Variable -Name filesTab -Scope Script -ErrorAction SilentlyContinue)) {
        return
    }
    $clientWidth = $filesTab.ClientSize.Width
    $clientHeight = $filesTab.ClientSize.Height
    if ($tabs -and $tabs.DisplayRectangle.Width -gt $clientWidth) {
        $clientWidth = $tabs.DisplayRectangle.Width
    }
    if ($tabs -and $tabs.DisplayRectangle.Height -gt $clientHeight) {
        $clientHeight = $tabs.DisplayRectangle.Height
    }
    if ($clientWidth -lt 700 -or $clientHeight -lt 260) {
        return
    }

    $filesTab.SuspendLayout()
    try {
        $margin = 14
        $centerWidth = 76
        $gap = 10
        $headerY = 10
        $labelY = 38
        $pathY = 62
        $listY = 98
        $iconW = 34
        $iconH = 28
        $iconGap = 4
        $hintH = 20
        $utilityH = 34
        $bottomMargin = 12

        $contentWidth = [Math]::Max(700, $clientWidth - (2 * $margin))
        $paneWidth = [Math]::Floor(($contentWidth - $centerWidth - (2 * $gap)) / 2)
        $paneWidth = [Math]::Max(320, $paneWidth)
        $leftX = $margin
        $centerX = $leftX + $paneWidth + $gap
        $rightX = $centerX + $centerWidth + $gap
        $rightLimit = $rightX + $paneWidth

        if ($rightLimit -gt ($clientWidth - $margin)) {
            $paneWidth = [Math]::Floor(($clientWidth - (2 * $margin) - $centerWidth - (2 * $gap)) / 2)
            $paneWidth = [Math]::Max(300, $paneWidth)
            $centerX = $leftX + $paneWidth + $gap
            $rightX = $centerX + $centerWidth + $gap
        }

        $utilityY = [Math]::Max($listY + 150, $clientHeight - $bottomMargin - $hintH - 8 - $utilityH)
        $listHeight = [Math]::Max(150, $utilityY - $listY - 12)
        $hintY = $utilityY + $utilityH + 6

        $filesHeader.SetBounds($margin, $headerY, [Math]::Max(300, $clientWidth - (2 * $margin)), 22)
        $localLabel.SetBounds($leftX, $labelY, $paneWidth, 22)
        $remoteLabel.SetBounds($rightX, $labelY, $paneWidth, 22)

        $leftPathWidth = [Math]::Max(160, $paneWidth - (2 * $iconW) - (2 * $iconGap))
        $script:RemotePathText.SetBounds($leftX, $pathY, $leftPathWidth, 24)
        $remoteRefresh.SetBounds($leftX + $leftPathWidth + $iconGap, $pathY - 2, $iconW, $iconH)
        $remoteUp.SetBounds($leftX + $leftPathWidth + $iconGap + $iconW + $iconGap, $pathY - 2, $iconW, $iconH)

        $rightPathWidth = [Math]::Max(160, $paneWidth - (3 * $iconW) - (3 * $iconGap))
        $script:LocalPathText.SetBounds($rightX, $pathY, $rightPathWidth, 24)
        $localRefresh.SetBounds($rightX + $rightPathWidth + $iconGap, $pathY - 2, $iconW, $iconH)
        $localUp.SetBounds($rightX + $rightPathWidth + $iconGap + $iconW + $iconGap, $pathY - 2, $iconW, $iconH)
        $localBrowse.SetBounds($rightX + $rightPathWidth + $iconGap + (2 * ($iconW + $iconGap)), $pathY - 2, $iconW, $iconH)

        $script:RemoteList.SetBounds($leftX, $listY, $paneWidth, $listHeight)
        $script:LocalList.SetBounds($rightX, $listY, $paneWidth, $listHeight)
        Resize-FileListColumns $script:RemoteList $paneWidth
        Resize-FileListColumns $script:LocalList $paneWidth

        $arrowX = $centerX + [Math]::Floor(($centerWidth - 58) / 2)
        $arrowY = $listY + [Math]::Max(18, [Math]::Floor(($listHeight - 96) / 2))
        $uploadButton.SetBounds($arrowX, $arrowY, 58, 44)
        $downloadButton.SetBounds($arrowX, $arrowY + 54, 58, 44)

        $utilityGap = 8
        $refreshW = [Math]::Min(150, [Math]::Max(122, [Math]::Floor($paneWidth * 0.30)))
        $newFolderW = [Math]::Min(210, [Math]::Max(158, [Math]::Floor($paneWidth * 0.38)))
        $openTransferW = [Math]::Min(250, [Math]::Max(198, [Math]::Floor($paneWidth * 0.46)))
        $utilityX = $leftX
        $refreshFilesButton.SetBounds($utilityX, $utilityY, $refreshW, $utilityH)
        $utilityX += $refreshW + $utilityGap
        $newRemoteFolder.SetBounds($utilityX, $utilityY, $newFolderW, $utilityH)
        $utilityX += $newFolderW + $utilityGap
        $openBoardTransfer.SetBounds($utilityX, $utilityY, $openTransferW, $utilityH)

        $script:FileDropHint.SetBounds($margin, $hintY, [Math]::Max(300, $clientWidth - (2 * $margin)), $hintH)
    } finally {
        $filesTab.ResumeLayout($true)
    }
}

function Apply-ControlCenterLayout {
    $client = $form.ClientSize
    if ($client.Width -lt 900 -or $client.Height -lt 560) {
        return
    }

    $form.SuspendLayout()
    try {
        $margin = 24
        $right = $client.Width - $margin
        $languageComboW = 178
        $languageLabelW = 86
        $languageX = $right - $languageComboW
        $languageLabelX = $languageX - $languageLabelW - 8

        $brandPanel.SetBounds($margin, 16, 46, 46)
        $title.SetBounds(84, 16, [Math]::Max(300, $languageLabelX - 96), 38)
        $subtitle.SetBounds(86, 54, [Math]::Max(300, $right - 86), 22)
        $brandCredit.SetBounds(86, 74, [Math]::Max(300, $right - 86), 18)
        $languageLabel.SetBounds($languageLabelX, 20, $languageLabelW, 20)
        $script:LanguageCombo.SetBounds($languageX, 18, $languageComboW, 24)

        $footerH = 20
        $footerY = $client.Height - 28 - $footerH
        $outputH = [Math]::Min(150, [Math]::Max(112, [Math]::Floor($client.Height * 0.18)))
        $outputY = $footerY - 12 - $outputH
        $tabsTop = 100
        $tabsH = [Math]::Max(300, $outputY - 14 - $tabsTop)

        $tabs.SetBounds($margin, $tabsTop, [Math]::Max(600, $client.Width - (2 * $margin)), $tabsH)
        $script:OutputBox.SetBounds($margin, $outputY, [Math]::Max(600, $client.Width - (2 * $margin)), $outputH)
        $footer.SetBounds($margin, $footerY, [Math]::Max(600, $client.Width - (2 * $margin)), $footerH)
    } finally {
        $form.ResumeLayout($true)
    }
    Apply-FilesTabLayout
}

if ($LayoutSelfTest) {
    $form.ClientSize = New-Object System.Drawing.Size(1120, 760)
    Apply-ControlCenterLayout
    Write-Host "NORMAL_TABS=$($tabs.Width)x$($tabs.Height)"
    Write-Host "NORMAL_LEFT=$($script:RemoteList.Left),$($script:RemoteList.Width)"
    Write-Host "NORMAL_RIGHT=$($script:LocalList.Left),$($script:LocalList.Width)"
    Write-Host "NORMAL_ARROWS=$($uploadButton.Text)/$($downloadButton.Text):$($uploadButton.Left),$($downloadButton.Left)"
    Write-Host "NORMAL_GAP=$($script:LocalList.Left - ($script:RemoteList.Left + $script:RemoteList.Width))"
    $form.ClientSize = New-Object System.Drawing.Size(1600, 960)
    Apply-ControlCenterLayout
    Write-Host "LARGE_TABS=$($tabs.Width)x$($tabs.Height)"
    Write-Host "LARGE_LEFT=$($script:RemoteList.Left),$($script:RemoteList.Width)"
    Write-Host "LARGE_RIGHT=$($script:LocalList.Left),$($script:LocalList.Width)"
    Write-Host "LARGE_ARROWS=$($uploadButton.Text)/$($downloadButton.Text):$($uploadButton.Left),$($downloadButton.Left)"
    Write-Host "LARGE_GAP=$($script:LocalList.Left - ($script:RemoteList.Left + $script:RemoteList.Width))"
    $form.Dispose()
    exit 0
}

$form.Add_Resize({
    Apply-ControlCenterLayout
})

$tabs.Add_SelectedIndexChanged({
    Apply-FilesTabLayout
})

$form.Add_Shown({
    Apply-ControlCenterLayout
    Add-Log "Ready. Host alias: $HostAlias"
    Refresh-Status
    Refresh-LocalFiles
    Refresh-RemoteFiles
})

[void]$form.ShowDialog()
