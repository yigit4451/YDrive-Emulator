$xamlFiles = Get-ChildItem -Path $PSScriptRoot -Filter *.xaml -Recurse

foreach ($file in $xamlFiles) {
    $content = Get-Content $file.FullName -Raw
    $matches = [regex]::Matches($content, 'x:Key="([^"]+)"')
    $keys = foreach ($m in $matches) { $m.Groups[1].Value }
    
    $duplicates = $keys | Group-Object | Where-Object { $_.Count -gt 1 }
    if ($duplicates) {
        Write-Host "DUPLICATES FOUND IN: $($file.Name)"
        foreach ($d in $duplicates) {
            Write-Host "  $($d.Name) - $($d.Count) times"
        }
    }
}
Write-Host "Check complete."
