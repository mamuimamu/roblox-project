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
$script:pendingRecvTask = $null; $script:pendingRecvBuf = $null
function WsRecv([int]$ms = 15000) {
    $mem = New-Object System.IO.MemoryStream
    do {
        if ($null -ne $script:pendingRecvTask) {
            $t = $script:pendingRecvTask; $buf = $script:pendingRecvBuf
            $script:pendingRecvTask = $null; $script:pendingRecvBuf = $null
        } else {
            $buf = [byte[]]::new(65536); $seg = [ArraySegment[byte]]::new($buf)
            $t = $ws.ReceiveAsync($seg, [System.Threading.CancellationToken]::None)
        }
        if (-not $t.Wait($ms)) { $script:pendingRecvTask = $t; $script:pendingRecvBuf = $buf; return $null }
        $result = $t.Result
        if ($result.MessageType -eq "Close") { return $null }
        if ($result.Count -gt 0) { $mem.Write($buf, 0, $result.Count) }
        if ($result.EndOfMessage) { break }
    } while ($true)
    return [System.Text.Encoding]::UTF8.GetString($mem.ToArray()) | ConvertFrom-Json
}
$init = WsRecv 8000
$script:msgId = 0
function Invoke-RunCode([string]$lua) {
    $script:msgId++
    WsSend @{ type="json_rpc"; jsonrpc="2.0"; id="$($script:msgId)"; method="tools/call"; params=@{name="execute_luau";arguments=@{code=$lua}} }
    $r = WsRecv 20000
    while ($r -and $r.type -eq "control") { $r = WsRecv 10000 }
    if ($r -and $r.result) { foreach ($c in $r.result.content) { if ($c.text) { Write-Host $c.text } } }
    elseif ($r -and $r.error) { Write-Host "ERROR: $($r.error.message)" }
    return $r
}

Write-Host "=== Vehicle [Script] source ==="
Invoke-RunCode @'
local vehicle = game:GetService("Workspace"):FindFirstChild("RescueVehicle")
             or game:GetService("ServerStorage"):FindFirstChild("RescueVehicle")
if not vehicle then return "RescueVehicle not found" end
local scripts = vehicle:FindFirstChild("Scripts")
if not scripts then return "Scripts not found" end
local vs = scripts:FindFirstChild("Vehicle")
if not vs then return "Vehicle script not found" end
return vs.Source
'@

Write-Host ""
Write-Host "=== Scan for ALL objects in Workspace with BrickColor red ==="
Invoke-RunCode @'
local results = {}
local function isRed(c)
    local s = tostring(c)
    return s:find("[Rr]ed") ~= nil or s == "Bright red" or s == "Crimson"
end
for _, d in ipairs(game:GetService("Workspace"):GetDescendants()) do
    if d:IsA("BasePart") and isRed(d.BrickColor) then
        local pos = d.Position
        table.insert(results, string.format("%s [%s] brickcolor=%s color3=(%d,%d,%d) size=%s pos=%.1f,%.1f,%.1f",
            d:GetFullName(), d.ClassName, tostring(d.BrickColor),
            math.floor(d.Color.R*255), math.floor(d.Color.G*255), math.floor(d.Color.B*255),
            tostring(d.Size), pos.X, pos.Y, pos.Z))
    end
end
return #results > 0 and table.concat(results, "\n") or "none"
'@

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,"", [System.Threading.CancellationToken]::None).Wait(2000) | Out-Null
