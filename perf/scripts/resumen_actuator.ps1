param([string[]]$Fases = @("antes", "despues"))

function Leer($archivo, $estadistica) {
    if (-not (Test-Path $archivo)) { return $null }
    try {
        $j = Get-Content $archivo -Raw | ConvertFrom-Json
        return ($j.measurements | Where-Object { $_.statistic -eq $estadistica }).value
    } catch { return $null }
}

foreach ($fase in $Fases) {
    $dir = "perf\results\actuator-$fase"
    $filas = @()
    $prevCount = 0; $prevTotal = 0; $prevGcCount = 0; $prevGcTotal = 0

    for ($i = 0; $i -le 15; $i++) {
        $t = "{0:D2}" -f $i
        $count   = Leer "$dir\min$t-http.json" "COUNT"
        $total   = Leer "$dir\min$t-http.json" "TOTAL_TIME"
        $gcCount = Leer "$dir\min$t-gc.json" "COUNT"
        $gcTotal = Leer "$dir\min$t-gc.json" "TOTAL_TIME"

        $dReq = if ($count) { $count - $prevCount } else { 0 }
        $dTot = if ($total) { $total - $prevTotal } else { 0 }

        $filas += [pscustomobject]@{
            Min        = $t
            ReqSeg     = [math]::Round($dReq / 60, 0)
            AvgMs      = if ($dReq -gt 0) { [math]::Round($dTot / $dReq * 1000, 1) } else { $null }
            MaxMs      = [math]::Round((Leer "$dir\min$t-http.json" "MAX") * 1000, 0)
            GcPausas   = if ($gcCount) { $gcCount - $prevGcCount } else { 0 }
            GcMs       = if ($gcTotal) { [math]::Round(($gcTotal - $prevGcTotal) * 1000, 0) } else { 0 }
            GcMaxMs    = [math]::Round((Leer "$dir\min$t-gc.json" "MAX") * 1000, 0)
            CpuPct     = [math]::Round((Leer "$dir\min$t-cpu.json" "VALUE") * 100, 0)
            TomcatBusy = Leer "$dir\min$t-tomcat-busy.json" "VALUE"
            HikariPend = Leer "$dir\min$t-hikari-pending.json" "VALUE"
        }

        if ($count)   { $prevCount = $count; $prevTotal = $total }
        if ($gcCount) { $prevGcCount = $gcCount; $prevGcTotal = $gcTotal }
    }

    Write-Host "`n=== $fase ==="
    $filas | Format-Table -AutoSize
}