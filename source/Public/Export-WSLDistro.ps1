# Command to export a WSL distribution to a VHDX file
#
# Examples:
#   Export Ubuntu 24.04 to a VHDX file:
#   .\Export-WSLDistro.ps1 -DistroName Ubuntu-24.04 -ExportPath E:\exports\ubuntu_test.vhdx -VHD -Verbose
# Parameters:
#   -DistroName
#     Required. The name of the WSL distribution to export (e.g., "Ubuntu-24.04")
#
#   -ExportPath
#     Required. Full path where the exported file will be saved
#     Must be a valid Windows path starting with drive letter (e.g., "C:\exports\backup.vhdx")
#     Parent directory must exist
#
#   -VHD
#     Optional switch. When specified, exports to VHDX format instead of tar
#     Recommended for better performance and features like dynamic expansion
#
#   -EstimatedSizeGB
#     Optional. The estimated size in GB for the VHDX file (1-10000 GB)
#     Only used if the script cannot determine the size of the distribution
#     Helps pre-allocate appropriate space for the virtual disk

param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DistroName,
        
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript({
            if ($_ -match '^[a-zA-Z]:\\') {
                $parent = Split-Path -Parent $_
                if (Test-Path $parent) { return $true }
                throw "Directory '$parent' does not exist."
            }
            throw "Path must be a full path (e.g., 'C:\exports\backup.vhdx')"
        })]
    [string]$ExportPath,
        
    [Parameter()]
    [switch]$VHD,

    [Parameter()]
    [ValidateRange(1, 10000)]
    [long]$EstimatedSizeGB
)

begin {
    # Add function to get WSL distribution size
    function Get-WSLDistributionSize {
        param (
            [string]$DistroName
        )
        
        try {
            # Get the WSL installation path
            $wslPath = (Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" | 
                       Get-ItemProperty | 
                       Where-Object { $_.DistributionName -eq $DistroName }).BasePath

            if (-not $wslPath) {
                throw "Could not find WSL path for distribution $DistroName"
            }

            # Get the size of the ext4.vhdx file
            $vhdxPath = Join-Path $wslPath "ext4.vhdx"
            if (Test-Path $vhdxPath) {
                $sizeBytes = (Get-Item $vhdxPath).Length
                return [math]::Ceiling($sizeBytes / 1GB)
            }
            
            # If we can't find the VHDX, return a default size
            return 256
        }
        catch {
            Write-Warning "Could not determine WSL distribution size: $_"
            return 256  # Default to 256GB if we can't determine the size
        }
    }

    Write-Host ""
    Write-Warning "It is recommended to shut down your WSL distribution before exporting with wsl.exe --shutdown"
    Write-Host ""
    Start-Sleep -Seconds 1
    Write-Warning "This will export your WSL distribution. The process cannot be interrupted once started."
    Write-Host "Press Ctrl+C within 5 seconds to cancel..." -ForegroundColor Yellow
    Write-Host ""
    Start-Sleep -Seconds 5

    # If no size was specified, calculate it
    if (-not $EstimatedSizeGB) {
        $EstimatedSizeGB = Get-WSLDistributionSize -DistroName $DistroName
        Write-Host "Automatically determined size: $EstimatedSizeGB GB" -ForegroundColor Green
    }

    Write-Host "Shutting down WSL..." -ForegroundColor Yellow
    wsl.exe --shutdown
    wsl.exe --terminate $DistroName
    Write-Host "WSL shutdown complete." -ForegroundColor Green
    Write-Host ""

    Write-Host "Starting export..." -ForegroundColor Green
    Write-Host ""
    Write-Host "Do not interrupt the process until it is complete. If you do, restart the wslservice.exe process to interract with your WSL distribution." -ForegroundColor Yellow
    Write-Host ""
    # Progress display helper
    function Write-ExportProgress {
        param(
            [Parameter(Mandatory)]
            [long]$CurrentSize,
                
            [Parameter(Mandatory)]
            [long]$TotalSize,
                
            [Parameter(Mandatory)]
            [TimeSpan]$Elapsed,
                
            [Parameter(Mandatory)]
            [char]$SpinnerChar
        )

        # Prevent division by zero
        if ($Elapsed.TotalSeconds -le 0) {
            return @{
                ProgressPercent = 0
                CurrentSize     = 0
                TotalSize      = [math]::Round($TotalSize / 1GB, 2)
                SpeedMBps      = 0
                RemainingTime  = [TimeSpan]::Zero
            }
        }

        # Calculate speed
        $speed = $CurrentSize / $Elapsed.TotalSeconds
        $speedMBps = [math]::Round($speed / 1MB, 2)
            
        # Calculate time remaining
        $remainingTime = [TimeSpan]::Zero
        if ($speed -gt 0) {
            $remainingBytes = $TotalSize - $CurrentSize
            $remainingTime = [TimeSpan]::FromSeconds($remainingBytes / $speed)
        }
            
        # Calculate progress percentage
        $progressPercent = [math]::Min(100, [math]::Round(($CurrentSize / $TotalSize) * 100, 1))
            
        # Create progress bar (50 chars wide)
        $progressBar = "[" + ("=" * [math]::Floor($progressPercent / 2)) + ">" + 
                          (" " * [math]::Floor((100 - $progressPercent) / 2)) + "]"
            
        # Format sizes
        $currentGB = [math]::Round($CurrentSize / 1GB, 2)
        $totalGB = [math]::Round($TotalSize / 1GB, 2)
            
        # Build and write status line
        $status = "`r{0} {1} {2}% | {3:N2}GB / {4:N2}GB | {5:N2} MB/s | ETA: {6:hh\:mm\:ss}" -f `
            $SpinnerChar, $progressBar, $progressPercent, $currentGB, $totalGB, 
        $speedMBps, $remainingTime

        Write-Host $status -NoNewline
            
        # Return progress info for potential use
        return @{
            ProgressPercent = $progressPercent
            CurrentSize     = $currentGB
            TotalSize       = $totalGB
            SpeedMBps       = $speedMBps
            RemainingTime   = $remainingTime
        }
    }

    try {
        # Validate WSL is available
        if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
            throw "WSL is not installed or not in PATH. Please install WSL first."
        }

        # Improved distribution validation
        $distros = (wsl.exe --list --quiet) -split "`n" | 
                  Where-Object { $_ } | 
                  ForEach-Object { $_.Trim() } |
                  Where-Object { $_ -ne "" }

        $distroExists = $false
        foreach ($distro in $distros) {
            if ($distro.Trim() -eq $DistroName) {
                $distroExists = $true
                break
            }
        }

        if (-not $distroExists) {
            $availableDistros = $distros | ForEach-Object { "- $_" }
            throw "Distribution '$DistroName' not found. Available distributions:`n$($availableDistros -join "`n")"
        }

        # Calculate initial size
        $initialSize = $EstimatedSizeGB * 1GB
        Write-Host "Using estimated size of $EstimatedSizeGB GB"

        # Create export directory if it doesn't exist
        $exportDir = Split-Path -Parent $ExportPath
        if (-not (Test-Path $exportDir)) {
            Write-Verbose "Creating directory: $exportDir"
            New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
        }

        # Check if export file already exists
        if (Test-Path $ExportPath) {
            throw "Export file already exists: $ExportPath"
        }
    }
    catch {
        Write-Error -ErrorRecord $_
        return [PSCustomObject]@{
            Success    = $false
            ExportPath = $ExportPath
            Error      = $_.Exception.Message
            Duration   = [TimeSpan]::Zero
            SizeGB     = 0
            ExitCode   = -1
        }
    }
}

process {
    $result = [PSCustomObject]@{
        Success    = $false
        ExportPath = $ExportPath
        Error      = $null
        Duration   = [TimeSpan]::Zero
        SizeGB     = 0
        ExitCode   = -1
    }

    try {
        # Start the export process
        $exportArgs = @("--export", $DistroName, $ExportPath)
        if ($VHD) {
            $exportArgs += "--vhd"
        }
        Write-Verbose "Starting WSL export with arguments: $($exportArgs -join ' ')"
        
        # Create process start info with redirected output
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "wsl.exe"
        $psi.Arguments = $exportArgs
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardOutput = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        # Start the process
        $exportProcess = New-Object System.Diagnostics.Process
        $exportProcess.StartInfo = $psi
        $exportProcess.Start() | Out-Null

        # Initialize monitoring variables
        $monitoring = $true
        $startTime = Get-Date
        $spinner = @('|', '/', '-', '\')
        $spinnerIndex = 0
        $lastProgress = $null

        while ($monitoring) {
            Start-Sleep -Milliseconds 500
                
            if (Test-Path $ExportPath) {
                $currentSize = (Get-Item $ExportPath).Length
                $elapsed = (Get-Date) - $startTime

                # Only update progress if time has elapsed
                if ($elapsed.TotalSeconds -gt 0) {
                    $lastProgress = Write-ExportProgress `
                        -CurrentSize $currentSize `
                        -TotalSize $initialSize `
                        -Elapsed $elapsed `
                        -SpinnerChar $spinner[$spinnerIndex]
                        
                    $spinnerIndex = ($spinnerIndex + 1) % 4
                }
            }
                
            # Check if the export process has finished
            if ($exportProcess.HasExited) {
                $monitoring = $false
                Write-Host "`nExport completed!"
                
                # Get any error output
                $errorOutput = $exportProcess.StandardError.ReadToEnd()
                $standardOutput = $exportProcess.StandardOutput.ReadToEnd()

                switch ($exportProcess.ExitCode) {
                    0 {
                        Write-Host "Export successful!"
                        $result.Success = $true
                    }
                    default {
                        if ($errorOutput) {
                            throw "Export failed with error: $errorOutput"
                        }
                        elseif ($standardOutput) {
                            throw "Export failed with output: $standardOutput"
                        }
                        else {
                            throw "Export failed with exit code $($exportProcess.ExitCode)"
                        }
                    }
                }

                $result.Duration = $elapsed
                $result.ExitCode = $exportProcess.ExitCode
                if ($lastProgress) {
                    $result.SizeGB = $lastProgress.CurrentSize
                }
                elseif (Test-Path $ExportPath) {
                    $result.SizeGB = [math]::Round((Get-Item $ExportPath).Length / 1GB, 2)
                }
            }
        }

        # Cleanup
        $exportProcess.Dispose()
    }
    catch {
        $result.Error = $_.Exception.Message
        Write-Error -ErrorRecord $_
    }

    return $result
}

end {
    if ($monitoring) {
        Write-Warning "Export process did not complete normally"
    }
}

