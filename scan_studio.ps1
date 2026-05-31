Add-Type -AssemblyName System.Net.Http

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync([Uri]"ws://127.0.0.1:13469/proxy", [System.Threading.CancellationToken]::None).Wait(5000) | Out-Null
if ($ws.State -ne "Open") { Write-Host "Failed to connect"; exit 1 }
Write-Host "Connected"

function WsSend($obj) {
    $json = $obj | ConvertTo-Json -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg = [ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).Wait(5000) | Out-Null
}

$script:pendingRecvTask = $null
$script:pendingRecvBuf  = $null

function WsRecv([int]$ms = 15000) {
    $mem = New-Object System.IO.MemoryStream
    do {
        if ($null -ne $script:pendingRecvTask) {
            $t   = $script:pendingRecvTask
            $buf = $script:pendingRecvBuf
            $script:pendingRecvTask = $null
            $script:pendingRecvBuf  = $null
        } else {
            $buf = [byte[]]::new(65536)
            $seg = [ArraySegment[byte]]::new($buf)
            $t   = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
        }
        if (-not $t.Wait($ms)) {
            $script:pendingRecvTask = $t
            $script:pendingRecvBuf  = $buf
            Write-Host "  [recv timeout]"; return $null
        }
        $result = $t.Result
        if ($result.MessageType -eq "Close") { return $null }
        if ($result.Count -gt 0) { $mem.Write($buf, 0, $result.Count) }
        if ($result.EndOfMessage) { break }
    } while ($true)
    $json = [System.Text.Encoding]::UTF8.GetString($mem.ToArray())
    return $json | ConvertFrom-Json
}

$init = WsRecv 8000
Write-Host "Init: $($init.control_type)"

$script:msgId = 0
function Invoke-RunCode([string]$lua) {
    $script:msgId++
    WsSend @{
        type    = "json_rpc"; jsonrpc = "2.0"; id = "$($script:msgId)"
        method  = "tools/call"
        params  = @{ name = "execute_luau"; arguments = @{ code = $lua } }
    }
    $r = WsRecv 20000
    while ($r -and $r.type -eq "control") { $r = WsRecv 10000 }
    if ($r -and $r.result) {
        foreach ($c in $r.result.content) { if ($c.text) { Write-Host $c.text } }
    } elseif ($r -and $r.error) { Write-Host "ERROR: $($r.error.message)" }
    return $r
}

Write-Host "=== Workspace scan ==="
Invoke-RunCode @'
local results = {}
local function scan(obj, depth)
    if depth > 3 then return end
    local indent = string.rep("  ", depth)
    local extra = ""
    if obj:IsA("BasePart") then
        local c = obj.BrickColor
        extra = " color=" .. tostring(c) .. " size=" .. tostring(obj.Size)
    end
    table.insert(results, indent .. obj.Name .. " [" .. obj.ClassName .. "]" .. extra)
    for _, child in ipairs(obj:GetChildren()) do
        scan(child, depth + 1)
    end
end
for _, child in ipairs(game:GetService("Workspace"):GetChildren()) do
    scan(child, 0)
end
return table.concat(results, "\n")
'@

Write-Host ""
Write-Host "=== ServerStorage scan ==="
Invoke-RunCode @'
local results = {}
local function scan(obj, depth)
    if depth > 2 then return end
    local indent = string.rep("  ", depth)
    table.insert(results, indent .. obj.Name .. " [" .. obj.ClassName .. "]")
    for _, child in ipairs(obj:GetChildren()) do
        scan(child, depth + 1)
    end
end
for _, child in ipairs(game:GetService("ServerStorage"):GetChildren()) do
    scan(child, 0)
end
return table.concat(results, "\n")
'@

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,"", [System.Threading.CancellationToken]::None).Wait(2000) | Out-Null
