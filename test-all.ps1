#Name can be 'random N' to randomly force the Nth group of packages.

param( [string[]] $Name, [string] $Root = "$PSScriptRoot" )

if ($PSVersionTable.PSEdition -eq 'Core' -and $Env:AU_WINPS_BOOTSTRAPPED -ne 'true') {
    $winPs = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path $winPs)) {
        throw 'Windows PowerShell 5.1 is required for this AU script, but powershell.exe was not found.'
    }

    $prev = $Env:AU_WINPS_BOOTSTRAPPED
    $Env:AU_WINPS_BOOTSTRAPPED = 'true'
    try {
        & $winPs -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
        exit $LASTEXITCODE
    }
    finally {
        $Env:AU_WINPS_BOOTSTRAPPED = $prev
    }
}

if (Test-Path $PSScriptRoot/update_vars.ps1) { . $PSScriptRoot/update_vars.ps1 }
$skipGist = $Env:au_skip_gist -eq 'true'
$global:au_root = Resolve-Path $Root

if (($Name.Length -gt 0) -and ($Name[0] -match '^random (.+)')) {
    [array] $lsau = lsau

    $group = [int]$Matches[1]
    $n = (Get-Random -Maximum $group)
    Write-Host "TESTING GROUP $($n+1) of $group"

    $group_size = [int]($lsau.Count / $group) + 1
    $Name = $lsau | select -First $group_size -Skip ($group_size*$n) | % { $_.Name }

    Write-Host ($Name -join ' ')
    Write-Host ('-'*80)
}

$forceUpdates = $Env:au_force -eq 'true'

if ($forceUpdates) {
    Write-Host 'Force mode is enabled for test-all run (au_force=true).'
}
else {
    Write-Host 'Force mode is disabled for test-all run (default behavior).'
}

$options = [ordered]@{
    Force   = $forceUpdates
    Push    = $false
    Threads = 10 

    IgnoreOn = @(                                      #Error message parts to set the package ignore status
        'Could not create SSL/TLS secure channel'
        'Could not establish trust relationship'
        'The operation has timed out'
        'Internal Server Error'
        'Service Temporarily Unavailable'
        'Choco pack failed with exit code 1'
    )

    RepeatOn = @(                                      #Error message parts on which to repeat package updater
        'Could not create SSL/TLS secure channel'             # https://github.com/chocolatey/chocolatey-coreteampackages/issues/718
        'Could not establish trust relationship'              # -||-
        'Unable to connect'
        'The remote name could not be resolved'
        'Choco pack failed with exit code 1'                  # https://github.com/chocolatey/chocolatey-coreteampackages/issues/721
        'The operation has timed out'
        'Internal Server Error'
        'An exception occurred during a WebClient request'
        'Job returned no object, Vector smash ?'
    )
    RepeatSleep   = 60                                      #How much to sleep between repeats in seconds, by default 0
    RepeatCount   = 2                                       #How many times to repeat on errors, by default 1

    Report = @{
        Type = 'markdown'                                   #Report type: markdown or text
        Path = "$PSScriptRoot\Update-Force-Test-${n}.md"    #Path where to save the report
        Params= @{                                          #Report parameters:
            Github_UserRepo = $Env:github_user_repo         #  Markdown: shows user info in upper right corner
            NoAppVeyor  = $true                             #  Markdown: do not show AppVeyor build shield
            Title       = "Update Force Test - Group ${n}"
            UserMessage = "[Ignored](#ignored)"       #  Markdown, Text: Custom user message to show
        }
    }
}

if (-not $skipGist) {
    $options.Gist = @{
        Id     = $Env:gist_id_test                          #Your gist id; leave empty for new private or anonymous gist
        ApiKey = $Env:github_api_key                        #Your github api key - if empty anoymous gist is created
        Path   = "$PSScriptRoot\Update-Force-Test-${n}.md"  #List of files to add to the gist
        Description = "Update Force Test Report #powershell #chocolatey"
    }
}


$global:info = updateall -Name $Name -Options $Options

$au_errors = $global:info | ? { $_.Error } | select -ExpandProperty Error

if ($ThrowOnErrors -and $au_errors.Count -gt 0) {
    throw 'Errors during update'
}