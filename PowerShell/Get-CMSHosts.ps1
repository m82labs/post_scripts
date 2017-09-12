function Get-CmsHosts() {
    <#
        .SYNOPSIS
        This function queries a CMS instance and returns a list of instances

        .PARAMETER CmsHost 
        The CMS host to connect to
        NOTE - This defaults to the 'SQL_CMS' environment variable. You can set this at the OS level, or within your PowerShell profile.

        .PARAMETER SqlInstance
        !!NOT INJECTION SAFE!! this parameter simply gets inserted into a wildcard query on the list of available instances on the CMS. This parameter accepts a pipe delimeted list of patterns, allowing you to match instance names on multiple conditions. If this parameter is a file path, the instance list will be read from the file. 

        .PARAMETER version
        The SQL Server version (build number) that should be running on the returned instances. 
        !! This will query each instance to get the build version, use in conjuction with SqlInstance if you have a lot of instances !!

        .NOTE
        If all parameters are left blank, this function will return ALL instances on the CMS server.

        .EXAMPLE
        This will return all instances that start with 'SRV-' and are on SQL 2016 RTM
        Get-CMSHosts -SqlInstance 'SRV-' -Version '13.0.1605.1'

        .EXAMPLE
        This can be used in a 'ForEach':
        ForEach ( $instance in Get-CMSHosts -SqlInstance 'SRV-' -Version '13.0.1605.1' ) {
            #Do some stuff
        }
    #>
    param(
        [CmdletBinding()]
        [string]$cmsHost = $env:SQL_CMS,
        [string]$SqlInstance,
        [switch]$EnumDatabases = $false,
        [string]$Version
    )
    
    If ( $SqlInstance -and (Test-Path -Path $SqlInstance -ErrorAction SilentlyContinue) ) {
        $results = Get-Content -Path $SqlInstance
    } Else {
        $pattern = ''

        # If multiple patterns are passed, parse them out
        For ( $pat_i = 0; $pat_i -lt ($SqlInstance.Split('|')).Count; $pat_i++ ) {
            If ( $pat_i -gt 0 ) { $pattern += " OR " }
            $pattern += "server_name LIKE '$($SqlInstance.Split('|')[$pat_i])%'"            
        }

        [string]$query_get_servers = @"
        SELECT DISTINCT server_name
        FROM   msdb.dbo.sysmanagement_shared_registered_servers
        WHERE {{searchPattern}}
"@
        $results = (Invoke-SqlCmd -query $query_get_servers.Replace('{{searchPattern}}',$pattern) -ServerInstance $CmsHost | Select -ExpandProperty server_name)
    }

    if ( $version ) {
        $results | % {
                Try {
                    If ( (Invoke-Sqlcmd -Query "SELECT SERVERPROPERTY('productversion') AS v" -ServerInstance $_ -ConnectionTimeout 1 -QueryTimeout 1 -ErrorAction Stop).v -ne $version) {
                        $results = $results | Where-Object { $_ -notmatch $instance }
                    }
                } Catch {
                    $connect_error += 1
		            Write-Host "failed: $($_.Exception.Message)" -ForegroundColor White -BackgroundColor Red
                    $results = $results | Where-Object { $_ -notmatch $instance }
                    continue
                }
            
        }
    }

    If ( $connect_error ) {
        Write-Host " -[$($connect_error) instance(s) skipped due to connection error]- " -ForegroundColor Red -NoNewline
    }

    if ( $enumDatabases ) {
        $FinalResult = New-Object System.Collections.ArrayList

        $results | % {
            $instance = $_

            $databases = invoke-sqlcmd -Query "select name from sys.databases;" -ServerInstance $instance | Select -ExpandProperty name

            $item = New-Object PSObject -Property @{
                Name = $instance
                Databases = $databases
            }
            
            $item | Add-Member -MemberType ScriptMethod -Name ToString -Force -Value { Write-Output $this.Name }
            
            $FinalResult.Add($item)  | Out-Null
        }
        return $FinalResult
    } else {
        return $results
    }
}