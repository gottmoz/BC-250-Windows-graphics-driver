$iso='C:\Users\Public\Win10_22H2_EnglishInternational_x64.iso'
$img=Get-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue
if($img){
  'IMG_ATTACHED=' + $img.Attached
  'IMG_NUMBER=' + $img.Number
  'IMG_DEVPATH=' + $img.DevicePath
}
Get-DiskImage | Select-Object ImagePath,Attached,Number,DevicePath | Format-Table -Auto
Get-Disk | Select-Object Number,FriendlyName,OperationalStatus,PartitionStyle,Size,IsOffline,IsReadOnly | Format-Table -Auto
Get-Partition | Select-Object DiskNumber,PartitionNumber,DriveLetter,GptType,Type,Size | Format-Table -Auto
Get-Volume | Select-Object DriveLetter,FileSystemLabel,FileSystem,DriveType,SizeRemaining,Size,Path | Format-Table -Auto
