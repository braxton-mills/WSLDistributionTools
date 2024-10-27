# Parameters for the WSL export
param(
    [Parameter(Mandatory=$true)]
    [string]$DistroName,
    
    [Parameter(Mandatory=$true)]
    [string]$ExportPath,
    
    [switch]$VHD,

    [Parameter(Mandatory=$false)]
    [long]$EstimatedSizeGB = 10
)

# Use provided estimate size
$initialSize = $EstimatedSizeGB * 1GB
Write-Host "Using estimated size of $EstimatedSizeGB GB"

# Start the export process
$exportArgs = @("--export", $DistroName, $ExportPath)
if ($VHD) {
    $exportArgs += "--vhd"
}
$exportProcess = Start-Process wsl.exe -ArgumentList $exportArgs -PassThru

# Monitor the export file size
$monitoring = $true
$lastSize = 0
$startTime = Get-Date
$spinner = @('|', '/', '-', '\')
$spinnerIndex = 0

while ($monitoring) {
    Start-Sleep -Milliseconds 500
    
    if (Test-Path $ExportPath) {
        $currentSize = (Get-Item $ExportPath).Length
        $elapsed = (Get-Date) - $startTime
        
        # Calculate speed and progress
        if ($elapsed.TotalSeconds -gt 0) {
            $speed = $currentSize / $elapsed.TotalSeconds
            $speedMBps = [math]::Round($speed/1MB, 2)
            
            # Calculate estimated time remaining
            if ($speed -gt 0) {
                $remainingBytes = $initialSize - $currentSize
                $remainingSeconds = $remainingBytes / $speed
                $remainingTime = [TimeSpan]::FromSeconds($remainingSeconds)
            }
            
            # Calculate progress percentage (cap at 100%)
            $progressPercent = [math]::Min(100, [math]::Round(($currentSize / $initialSize) * 100, 1))
            
            # Create progress bar
            $progressBar = "[" + ("=" * [math]::Floor($progressPercent/2)) + ">" + (" " * [math]::Floor((100-$progressPercent)/2)) + "]"
            
            # Update spinner
            $spinnerIndex = ($spinnerIndex + 1) % 4
            $currentSpinner = $spinner[$spinnerIndex]
            
            # Clear the previous line and write the new status
            Write-Host "`r$currentSpinner $progressBar $progressPercent% | $([math]::Round($currentSize/1GB, 2))GB / $([math]::Round($initialSize/1GB, 2))GB | $speedMBps MB/s | ETA: $($remainingTime.ToString('hh\:mm\:ss'))" -NoNewline
        }
        
        $lastSize = $currentSize
    }
    
    # Check if the export process has finished
    if ($exportProcess.HasExited) {
        $monitoring = $false
        Write-Host "`nExport completed!"
    }
}

# Check the exit code
if ($exportProcess.ExitCode -eq 0) {
    Write-Host "Export successful!"
} else {
    Write-Host "Export failed with exit code $($exportProcess.ExitCode)"
}