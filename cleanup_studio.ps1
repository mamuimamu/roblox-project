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
        foreach ($c in $r.result.content) { if ($c.text) { Write-Host "  -> $($c.text)" } }
    } elseif ($r -and $r.error) { Write-Host "  ERROR: $($r.error.message)" }
    return $r
}

Write-Host ""
Write-Host "=== Blank LocalVehiclePromptGui ==="
Invoke-RunCode @'
local vehicle = game:GetService("Workspace"):FindFirstChild("RescueVehicle")
             or game:GetService("ServerStorage"):FindFirstChild("RescueVehicle")
if not vehicle then return "ERROR: RescueVehicle not found" end

local scripts = vehicle:FindFirstChild("Scripts")
if not scripts then return "ERROR: Scripts folder not found" end

local gui = scripts:FindFirstChild("LocalVehiclePromptGui")
if not gui then return "ERROR: LocalVehiclePromptGui not found" end

gui.Source = "-- no-op (BillboardGui prompt buttons removed)"
return "OK: LocalVehiclePromptGui blanked. ClassName=" .. gui.ClassName
'@

Write-Host ""
Write-Host "=== Delete EndorsedVehicleProximityPromptV1 from non-driver seats ==="
Invoke-RunCode @'
local vehicle = game:GetService("Workspace"):FindFirstChild("RescueVehicle")
             or game:GetService("ServerStorage"):FindFirstChild("RescueVehicle")
if not vehicle then return "ERROR: RescueVehicle not found" end

local deleted = {}
for _, desc in ipairs(vehicle:GetDescendants()) do
    if desc:IsA("ProximityPrompt") and desc.Name == "EndorsedVehicleProximityPromptV1" then
        local parentName = desc.Parent and desc.Parent.Name or "nil"
        -- Only delete from non-VehicleSeat seats (SeatFR, SeatRL, SeatRR)
        -- Keep the VehicleSeat one (VehiclePromptHandler manages it)
        local grandParent = desc.Parent and desc.Parent.Parent
        if grandParent and grandParent:IsA("Seat") then
            table.insert(deleted, grandParent.Name .. "/" .. desc.Parent.Name .. "/" .. desc.Name)
            desc:Destroy()
        end
    end
end
return "Deleted from: " .. (#deleted > 0 and table.concat(deleted, ", ") or "none")
'@

Write-Host ""
Write-Host "=== Rename EndorsedVehicleProximityPromptV1 on VehicleSeat ==="
Invoke-RunCode @'
local vehicle = game:GetService("Workspace"):FindFirstChild("RescueVehicle")
             or game:GetService("ServerStorage"):FindFirstChild("RescueVehicle")
if not vehicle then return "ERROR: RescueVehicle not found" end

local chassis = vehicle:FindFirstChild("Chassis")
if not chassis then return "ERROR: Chassis not found" end

local vs = chassis:FindFirstChild("VehicleSeat")
if not vs then return "ERROR: VehicleSeat not found" end

local renamed = {}
for _, desc in ipairs(vs:GetDescendants()) do
    if desc:IsA("ProximityPrompt") and desc.Name == "EndorsedVehicleProximityPromptV1" then
        desc.Name = "RescueVehiclePrompt"
        table.insert(renamed, desc:GetFullName())
    end
end
return "Renamed: " .. (#renamed > 0 and table.concat(renamed, ", ") or "none found")
'@

$ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,"", [System.Threading.CancellationToken]::None).Wait(2000) | Out-Null
Write-Host ""
Write-Host "Done."
