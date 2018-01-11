$lastCheck = (Get-Date).AddSeconds(-2) 
while ($true) 
{ 
    Get-EventLog Application -Source docker -After $lastcheck |% { $_.TimeGenerated.ToString() + ': ' + $_.ReplacementStrings }
    $lastCheck = Get-Date 
    Start-Sleep -Seconds 2
}
