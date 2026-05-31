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

Write-Host "=== Mode check (Town folder = test play) ==="
Invoke-RunCode @'
local ws = game:GetService("Workspace")
local town = ws:FindFirstChild("Town")
local rv_loc = "RescueVehicle in: "
if ws:FindFirstChild("RescueVehicle") then rv_loc = rv_loc .. "Workspace"
elseif game:GetService("ServerStorage"):FindFirstChild("RescueVehicle") then rv_loc = rv_loc .. "ServerStorage"
else rv_loc = rv_loc .. "NOT FOUND" end
return "Town=" .. tostring(town ~= nil) .. " | " .. rv_loc
'@

Write-Host ""
Write-Host "=== ALL Workspace top-level children ==="
Invoke-RunCode @'
local lines = {}
for _, child in ipairs(game:GetService("Workspace"):GetChildren()) do
    table.insert(lines, child.Name .. " [" .. child.ClassName .. "]")
end
return table.concat(lines, "\n")
'@

Write-Host ""
Write-Host "=== Parts near origin (within 50 studs of 0,0,0) ==="
Invoke-RunCode @'
local lines = {}
for _, d in ipairs(game:GetService("Workspace"):GetDescendants()) do
    if d:IsA("BasePart") then
        local pos = d.Position
        if math.abs(pos.X) < 50 and math.abs(pos.Z) < 50 and pos.Y < 20 then
            local color = tostring(d.BrickColor)
            local size = d.Size
            -- Only show non-tiny, colored parts
            if (size.X > 1 or size.Y > 1 or size.Z > 1) and color ~= "Dark grey metallic" and color ~= "Medium stone grey" then
                table.insert(lines, string.format("%s [%s] color=%s size=%.1fx%.1fx%.1f pos=%.1f,%.1f,%.1f",
                    d:GetFullName(), d.ClassName, color, size.X, size.Y, size.Z, pos.X, pos.Y, pos.Z))
            end
        end
    end
end
return #lines > 0 and table.concat(lines, "\n") or "none"
'@

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,"", [System.Threading.CancellationToken]::None).Wait(2000) | Out-Null
