function Export-WSLDistro {
    [CmdletBinding()]
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
        [long]$EstimatedSizeGB = 10
    )

    begin {
        # Validate WSL is available
        if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
            throw "WSL is not installed or not in PATH. Please install WSL first."
        }

        # Validate distribution exists
        $distros = wsl.exe --list --quiet
        if ($distros -notmatch "^$DistroName$") {
            $availableDistros = $distros | Where-Object { $_ -and $_.Trim() } | ForEach-Object { "- $_" }
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

    process {
        # Start the export process
        $exportArgs = @("--export", $DistroName, $ExportPath)
        if ($VHD) {
            $exportArgs += "--vhd"
        }
        Write-Verbose "Starting WSL export with arguments: $($exportArgs -join ' ')"
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
    }

    end {
        if ($monitoring) {
            Write-Warning "Export process did not complete normally"
        }
    }
}

# Export the function
Export-ModuleMember -Function Export-WSLDistro

# Allow direct execution of this script
if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Name) {
    Export-WSLDistro @PSBoundParameters
}