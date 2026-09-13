# Registers the FALLBACK refresh (scripts/refresh_fallback.py) with Windows Task Scheduler.
#
# FALLBACK, NOT PRIMARY. The primary refresh is .github/workflows/refresh.yml at 05:00 UTC.
# This task runs daily at 11:00 local time on this PC (UTC+3, so 08:00 UTC): after the
# workflow's run and its full retry window, so on a normal day the workflow has already
# committed and the fallback's probe simply holds.
#
# IT RUNS ONLY WHILE THIS PC IS ON AND ITS USER IS LOGGED ON. "Interactive" logon means no
# password is stored and nothing runs at the lock screen or after logout. If the PC is off at
# 11:00, StartWhenAvailable runs it once the machine is next available -- not before.
#
#   powershell -NoProfile -File scripts\register_fallback_task.ps1 -Python "C:\...\python.exe"
#   powershell -NoProfile -File scripts\register_fallback_task.ps1 -Unregister
param(
    [string]$Python,
    [string]$At = "11:00",
    [switch]$Unregister
)
$ErrorActionPreference = "Stop"
$TaskName = "Hammer light refresh (fallback)"

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Output "Unregistered '$TaskName'."
    return
}
if (-not $Python -or -not (Test-Path $Python)) {
    throw "Pass -Python with the full path to the python.exe that has duckdb installed."
}

$repo = Split-Path -Parent $PSScriptRoot
$action = New-ScheduledTaskAction -Execute $Python -Argument "scripts\refresh_fallback.py" -WorkingDirectory $repo
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Hours 3) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$description = "FALLBACK for the Project Hammer tool refresh. Primary is the GitHub workflow. " +
               "Runs only while this PC is on and its user is logged on. See scripts\refresh_fallback.py."

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description $description -Force | Out-Null
$t = Get-ScheduledTask -TaskName $TaskName
$i = Get-ScheduledTaskInfo -TaskName $TaskName
Write-Output "Registered '$TaskName': state $($t.State), next run $($i.NextRunTime), runs $Python scripts\refresh_fallback.py in $repo"
