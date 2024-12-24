#DESCRIPTION
 # <Bulk Export Intune Configuration Policy Device Assignment Status Report>
#.Demo
#<YouTube video link-->https://www.youtube.com/@ChanderManiPandey
#.INPUTS
 # <Provide all required inforamtion in User Input Section >
#.OUTPUTS
 # <Bulk Export Intune Configuration Policy Device Assignment Status Report >

#.NOTES
 
 <#
  Version:         1.0
  Author:          Chander Mani Pandey
  Creation Date:   25 Dec 2024
  
  Find Author on 
  Youtube:-        https://www.youtube.com/@chandermanipandey8763
  Twitter:-        https://twitter.com/Mani_CMPandey
  LinkedIn:-       https://www.linkedin.com/in/chandermanipandey
 #>

#=================================================================================================================================================
#------------------------------------------------------ User Input Section Start------------------------------------------------------------------
#=================================================================================================================================================
$tenantNameOrID  = "xxxxxxxxxxxxxx"       # Tenant Name or ID
$clientAppId     = "xxxxxxxxxxxxxx"       # Client Application ID
$clientAppSecret = "xxxxxxxxxxxxxx"       # Client Application Secret

# List of Policy IDs
$PolicyIDs = @(
    "c6f15e93-3cf7-449e-969b-21fb632fef77",
    "e7a1a387-ea60-4ee0-ad94-af9747ef5078",
    "c4a2df1a-3c16-42e8-90be-8815a74c1203",
    "092a7813-eb3b-4406-a592-9d81a2b878fe",
    "b22a7a1c-0215-48c4-a7af-7705dc843652",
    "6f831176-c56f-4967-af57-fd53bcc88b22",
    "72288c01-97be-41bf-9653-eb9b1c520ac9",
    "ca82d2b5-f42d-45c5-8f75-19df0d1c2acb"
)

$WorkingFolder = "C:\TEMP\Intune_Configuration_Profile_Report"    # Configuration Policy reporting folder Location


#=================================================================================================================================================
#------------------------------------------------------ User Input Section End--------------------------------------------------------------------
#=================================================================================================================================================
CLS
# Set execution policy for the process
Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force -ErrorAction 'Stop'
$error.Clear() # Clear error history
$ErrorActionPreference = 'SilentlyContinue'
Write-Host "===============================Phase-1 (Exporting Intune Configuration_Profile_Report) ======================================================(Started)" -ForegroundColor Green


#====================== data ==================================
# Tenant and app details
$authority = "https://login.windows.net/$tenantNameOrID"
# Initialize variables
$error.Clear()  # Clear error history
$ReportsFolder = "$WorkingFolder\Reports"  # Changed folder name here
$ReportTimeoutSeconds = 300  # Timeout for report generation (5 minutes)
$SleepIntervalSeconds = 10  # Interval to check report status

# Check if Microsoft.Graph.Intune module is installed
Write-Host "Checking if Microsoft.Graph.Intune module is installed..."
$MGIModule = Get-Module -Name "Microsoft.Graph.Intune" -ListAvailable
if ($MGIModule -eq $null) {
    Write-Host "Microsoft.Graph.Intune module not installed. Installing it now..."
    Install-Module -Name Microsoft.Graph.Intune -Force
}
Import-Module Microsoft.Graph.Intune -Force
Write-Host "Microsoft.Graph.Intune module imported successfully."

# Connect to Microsoft Graph API
Update-MSGraphEnvironment -AppId $clientAppId -AuthUrl $authority -Quiet
Connect-MSGraph -ClientSecret $clientAppSecret -Quiet
Update-MSGraphEnvironment -SchemaVersion "Beta" -Quiet

$ConfigurationProfile = Invoke-MSGraphRequest -HttpMethod GET -Url "deviceManagement/deviceConfigurations" | Get-MSGraphAllPages | Select-Object ID,displayName,"@odata.type" 

# Ensure directories exist
if (-Not (Test-Path -Path $WorkingFolder)) {
    Write-Host "Creating working folder: $WorkingFolder"
    New-Item -ItemType Directory -Path $WorkingFolder -Force | Out-Null
}
if (-Not (Test-Path -Path $ReportsFolder)) {  # Changed from $PD_DumpPath to $ReportsFolder
    Write-Host "Creating Reports folder: $ReportsFolder"
    New-Item -ItemType Directory -Path $ReportsFolder -Force | Out-Null
}

# Loop through each Policy ID
foreach ($PolicyID in $PolicyIDs) {
    # Get the display name of the current Policy ID from ConfigurationProfile
    $PolicyDisplayName = ($ConfigurationProfile | Where-Object { $_.ID -eq $PolicyID }).displayName

    if ($PolicyDisplayName) {
        Write-Host "Processing Policy: $PolicyDisplayName" -ForegroundColor Cyan
        $PolicyFolder = "$ReportsFolder\$PolicyDisplayName"  # Changed folder reference here

        # Check if the folder exists and if it contains files, delete them
        if (Test-Path -Path $PolicyFolder) {
            $existingFiles = Get-ChildItem -Path $PolicyFolder
            if ($existingFiles.Count -gt 0) {
                Write-Host "Folder is not empty, deleting old reports..." -ForegroundColor Red
                Remove-Item -Path "$PolicyFolder\*" -Force
            }
        } else {
            # If the folder doesn't exist, create it
            New-Item -ItemType Directory -Path $PolicyFolder -Force | Out-Null
        }

        # Create request body for report export
        $postBody = @{
            'reportName' = "DeviceStatusesByConfigurationProfileWithPF"
            'filter' = "(PolicyId eq '$PolicyID')"
        }

        # Initiate the export job
        try {
            $exportJob = Invoke-MSGraphRequest -HttpMethod POST -Url "DeviceManagement/reports/exportJobs" -Content $postBody
            Write-Host "Export job initiated for Policy: $PolicyDisplayName"
        } catch {
            Write-Host "Failed to initiate export job for Policy: $PolicyDisplayName. Error: $_" -ForegroundColor Red
            continue
        }

        # Wait for report to complete
        $elapsedTime = 0
        do {
            Start-Sleep -Seconds $SleepIntervalSeconds
            $elapsedTime += $SleepIntervalSeconds

            $exportJob = Invoke-MSGraphRequest -HttpMethod Get -Url "DeviceManagement/reports/exportJobs('$($exportJob.id)')" -InformationAction SilentlyContinue
            Write-Host -NoNewline "."
        } while ($exportJob.status -eq 'inprogress' -and $elapsedTime -lt $ReportTimeoutSeconds)

        # Check report status
        if ($exportJob.status -eq 'completed') {
            Write-Host "`nReport is ready for Policy: $PolicyDisplayName" -ForegroundColor Yellow
            $fileName = (Split-Path -Path $exportJob.url -Leaf).split('?')[0]
            $outputFilePath = "$PolicyFolder\$fileName"

            # Download the report
            try {
                Invoke-WebRequest -Uri $exportJob.url -Method Get -OutFile $outputFilePath
                Write-Host "Report downloaded for Policy: $PolicyDisplayName at: $outputFilePath"

                # Extract ZIP file contents
                $extractPath = "$PolicyFolder"
                if (-Not (Test-Path -Path $extractPath)) {
                    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
                }
                Expand-Archive -Path $outputFilePath -DestinationPath $extractPath -Force
                #Write-Host "Report extracted to: $extractPath"

                # Delete the ZIP file
                Remove-Item -Path $outputFilePath -Force
                #Write-Host "Deleted ZIP file: $outputFilePath"
            } catch {
                Write-Host "Failed to process report for Policy: $PolicyDisplayName. Error: $_" -ForegroundColor Red
            }
        } else {
            Write-Host "`nExport job for Policy: $PolicyDisplayName failed or timed out." -ForegroundColor Red
        }
    } else {
        Write-Host "No display name found for Policy ID: $PolicyID" -ForegroundColor Red
    }
}

Write-Host "===============================Phase-1 (Exported Configuration_Profile_Reports for All Policy IDs) ====================================================(Completed)" -ForegroundColor Green
