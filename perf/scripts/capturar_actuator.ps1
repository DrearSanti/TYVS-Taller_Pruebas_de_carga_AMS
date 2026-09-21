param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("antes", "despues", "despues2")]
    [string]$Fase,

    [string]$Ip = "192.168.231.129",
    [int]$Minutos = 15
)

$base = "http://${Ip}:8080/actuator/metrics"
$dir = "perf\results\actuator-$Fase"
New-Item -ItemType Directory -Force $dir | Out-Null

$metricas = @{
    "http"           = "http.server.requests?tag=uri:/register"
    "threads"        = "jvm.threads.live"
    "tomcat-busy"    = "tomcat.threads.busy"
    "gc"             = "jvm.gc.pause"
    "cpu"            = "process.cpu.usage"
    "hikari-active"  = "hikaricp.connections.active"
    "hikari-pending" = "hikaricp.connections.pending"
    "memoria"        = "jvm.memory.used?tag=area:heap"
}

for ($i = 0; $i -le $Minutos; $i++) {
    $t = "{0:D2}" -f $i
    foreach ($nombre in $metricas.Keys) {
        curl.exe -s "$base/$($metricas[$nombre])" -o "$dir\min$t-$nombre.json"
    }
    Write-Host "Muestra minuto $t tomada $(Get-Date -Format HH:mm:ss)"
    if ($i -lt $Minutos) { Start-Sleep -Seconds 60 }
}