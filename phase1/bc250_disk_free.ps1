Get-PSDrive -PSProvider FileSystem |
  Select-Object Name,Used,Free,@{N='UsedGB';E={[math]::Round($_.Used/1GB,2)}},@{N='FreeGB';E={[math]::Round($_.Free/1GB,2)}} |
  Format-Table -Auto
