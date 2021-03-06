Function Set-UcsRestParameter
{
  <#
      .SYNOPSIS
      Set a parameter for this specific phone.

      .DESCRIPTION
      Uses the "Set" API endpoint to set the value of a parameter.

      .PARAMETER IPv4Address
      The IP address of the target phone, in the format 192.168.1.234.

      .PARAMETER Parameter
      The name of the parameter to set.

      .PARAMETER Value
      The value to set. $True is converted to 1 and $False is converted to 0.

      .PARAMETER Quiet
      Suppresses warnings and some errors, and inhibits result output.

      .NOTES
      Phone may reboot after setting a parameter, especially in the case of an invalid assignment.
  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'A valid UCS parameter, such as Up.Timeout',ValueFromPipelineByPropertyName)][String]$Parameter,
    [Parameter(Mandatory,HelpMessage = 'A valid value for the specified parameter.')][AllowEmptyString()][String]$Value,
  [Switch]$PassThru)

  BEGIN {
    if($Value -eq $true)
    {
      $Value = '1'
    }
    elseif($Value -eq $false)
    {
      $Value = '0'
    }

    Try
    {
      $ThisParameter = Get-UcsCleanJSON -String $Parameter -ErrorAction Stop
    }
    Catch
    {
      $Exception = New-Object $_.Exception.GetType().BaseType ("Couldn't process provided parameter $Parameter on $ThisIPv4Address.",$_) #Grab the exception object type from the inner exception and attach the inner exception.
      Throw $Exception
    }

    Try
    {
      $ThisValue = Get-UcsCleanJSON -String $Value -ErrorAction Stop
    }
    Catch
    {
      Write-Debug "Got an error when trying to clean value. Empty string?"
      $ThisValue = ""
    }

    $ParameterSet = ("{{`"data`":{{`"{0}`": `"{1}`"}}}}" -f $ThisParameter, $ThisValue)
  } PROCESS {
    FOREACH($ThisIPv4Address in $IPv4Address)
    {
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address)))
      {
        Try
        {
          $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/config/set' -Method 'Post' -Body $ParameterSet -ErrorAction Stop
        }
        Catch
        {
          $Exception = New-Object $_.Exception.GetType().BaseType ("Couldn't set parameter $Parameter with value $Value on $ThisIPv4Address.",$_) #Grab the exception object type from the inner exception and attach the inner exception.
          Throw $Exception
        }

        if($ThisOutput.Status.IsSuccess -eq $false) {
          Write-Error "Couldn't set parameter $Parameter with value $Value on $ThisIPv4Address. Phone returned an error."
          Continue
        }
      }
    }

  } END {
  }
}

Function Get-UcsRestParameter
{
  <#
      .SYNOPSIS
      Retrieve configuration parameter

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Parameter
      One or more parameter names.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'A UCS parameter, such as "Up.Timeout."',ValueFromPipelineByPropertyName)][String[]]$Parameter,
    [Switch]$Quiet,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
    $MaxParameters = 20

    #TODO: The REST API only lets us request 20 parameters at a time, but we could invisibly batch them for the user.
    if($Parameter.count -gt $MaxParameters)
    {
      Write-Error ('{0} parameters were provided, maximum is {1}.' -f $Parameter.count, $MaxParameters) -ErrorAction Stop -RecommendedAction 'Reduce the number of parameters and try again.'
    }
  } PROCESS {
    foreach($ThisIPv4Address in $IPv4Address)
    {
      $ParameterString = ''
      Foreach($ThisParameter in $Parameter)
      {
        $ThisParameter = Get-UcsCleanJSON -String $ThisParameter
        $ParameterString += ('"{0}",' -f $ThisParameter)
      }
      $ParameterString = $ParameterString.Substring(0,($ParameterString.Length - 1))

      $ParameterName = ("{{`"data`":[{0}]}}" -f $ParameterString)

      Try
      {
        $RawOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/config/get' -Body $ParameterName -Method Post -Retries $Retries

        $Output = $RawOutput.Data
        $InvalidParams = $RawOutput.InvalidParams
      }
      Catch
      {
        Write-Error -Message "Could not get parameter $Parameter for $ThisIPv4Address."
        Continue #No need to process more.
      }

      Try
      {
        $ParameterNames = $Output |
        Get-Member -ErrorAction Stop |
        Where-Object -Property MemberType -EQ -Value 'NoteProperty' |
        Select-Object -ExpandProperty Name
      }
      Catch
      {
        Write-Error -Message "Could not parse parameter information for $ThisIPv4Address."
      }

      Try
      {
        $InvalidParameterNames = $InvalidParams |
        Get-Member -ErrorAction Stop |
        Where-Object -Property MemberType -EQ -Value 'NoteProperty' |
        Select-Object -ExpandProperty Name
      }
      Catch
      {
        Write-Debug -Message "No invalid parameters detected for $ThisIPv4Address."
      }

      Foreach($ParameterName in $ParameterNames)
      {
        $ThisResult = New-Object -TypeName PsCustomObject
        $ThisResult | Add-Member -MemberType NoteProperty -Name IPv4Address -Value $ThisIPv4Address
        $ThisResult | Add-Member -MemberType NoteProperty -Name Parameter -Value $ParameterName

        Try
        {
          $ThisParameterResult = $Output | Select-Object -ExpandProperty $ParameterName -ErrorAction Stop
          $ThisResult | Add-Member -MemberType NoteProperty -Name Value -Value $ThisParameterResult.Value
          $ThisResult | Add-Member -MemberType NoteProperty -Name Source -Value $ThisParameterResult.Source
        }
        Catch
        {
          Write-Error -Message "Couldn't create a parameter output object for $ThisIPv4Address"
          $ThisResult | Add-Member -MemberType NoteProperty -Name Value -Value $null
          $ThisResult | Add-Member -MemberType NoteProperty -Name Source -Value "Error"
        }

        $null = $OutputArray.Add($ThisResult)
      }

      Foreach($IdName in $InvalidParameterNames)
      {
        $ParameterName = $InvalidParams.$IdName
        Write-Warning "$ParameterName is not a valid parameter name for $ThisIPv4Address."
        $ThisResult = New-Object -TypeName PsCustomObject
        $ThisResult | Add-Member -MemberType NoteProperty -Name IPv4Address -Value $ThisIPv4Address
        $ThisResult | Add-Member -MemberType NoteProperty -Name Parameter -Value $ParameterName
        $ThisResult | Add-Member -MemberType NoteProperty -Name Value -Value $null
        $ThisResult | Add-Member -MemberType NoteProperty -Name Source -Value "InvalidParams"

        $null = $OutputArray.Add($ThisResult)
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestNetworkInfo
{
  <#
      .SYNOPSIS
      Returns basic networking information.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$Quiet,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach($ThisIPv4Address in $IPv4Address)
    {
      $Output = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/network/info' -Retries $Retries
      $Modified = $Output.data

      #Process the provisioning server for consistency with other cmdlets.
      $ProvisioningServer = $Modified.ProvServerAddress.Trim()
      $ProvisioningServer = $ProvisioningServer.Replace('/','\') #Make all slashes the same.
      $ProvisioningServerIndex = $ProvisioningServer.LastIndexOf('\') + 1
      if($ProvisioningServerIndex -gt 0)
      {
        $ProvisioningServer = $ProvisioningServer.Substring($ProvisioningServerIndex)
      }
      $Modified.ProvServerAddress = $ProvisioningServer


      if($Modified.DHCP -eq "enabled")
      {
        $DHCPEnabled = $true
      } elseif($Modified.DHCP -eq "disabled")
      {
        $DHCPEnabled = $false
      } else
      {
        $DHCPEnabled = $null
      }
      $Modified = $Modified | Select-Object -ExcludeProperty DHCP -Property *,@{Name="DHCPEnabled";Expression={$DHCPEnabled}}
      $null = $OutputArray.Add($Modified)
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestDeviceInfo
{
  <#
      .SYNOPSIS
      Returns basic device information.

      .DESCRIPTION
      Returns model information, firmware version information, uptime, MAC address, and information on attached devices.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Quiet
      Prevents the API call from returning warnings when problems occur.

      .EXAMPLE
      Get-DeviceInfo -IPv4Address 192.168.1.20 -Quiet
      Returns device info without returning any warnings in case of a problem.

      .NOTES
      AttachedHardware is a hashtable with multiple objects inside it representing the attached devices.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$Quiet,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN
  {

  }
  PROCESS {
    foreach($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        Write-Debug -Message "Connecting to $ThisIPv4Address"
        $Output = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/device/info' -Method Get -Retries $Retries -ErrorAction Stop
        $OutputData = $Output.Data
      }
      Catch
      {
        Write-Error -Message "Couldn't connect to $ThisIPv4Address"
      }

      if($null -ne $OutputData)
      {
        $OutputObject = New-Object PsCustomObject

        Write-Debug -Message "Parsing data for $ThisIPv4Address"

        $OutputObject | Add-Member -MemberType NoteProperty -Name IPv4Address -Value $ThisIPv4Address

        $MacAddress = $OutputData.MacAddress
        $OutputObject | Add-Member -MemberType NoteProperty -Name MacAddress -Value $MacAddress

        $ModelNumber = $OutputData.ModelNumber
        if($ModelNumber -eq "Trio 8800")
        {
          #Some versions of the Trio firmware output the model differently.
          #TODO: If we find this is true on a lot of models/firmwares, implement some sort of table for this data.
          $ModelNumber = "RealPresence Trio 8800"
        }
        $OutputObject | Add-Member -MemberType NoteProperty -Name Model -Value $ModelNumber

        $DeviceVendor = $OutputData.DeviceVendor
        $OutputObject | Add-Member -MemberType NoteProperty -Name DeviceVendor -Value $DeviceVendor

        $DeviceType = $OutputData.DeviceType
        $OutputObject | Add-Member -MemberType NoteProperty -Name DeviceType -Value $DeviceType

        $AttachedHardware = $OutputData.AttachedHardware
        $OutputObject | Add-Member -MemberType NoteProperty -Name AttachedHardware -Value $AttachedHardware

        <### Get firmware info ###>
        if( ($OutputData | Get-Member).Name -contains 'Firmware')
        {
          #If we're running on a 5.7.X firmware, there's no FirmwareRelease row, so we need to add it from the new Firmware row.
          $Updater = $OutputData.Firmware.Updater
          $OutputObject | Add-Member -MemberType NoteProperty -Name UpdaterFirmware -Value $Updater

          $ApplicationFirmware = $OutputData.Firmware.Application
          $null = $ApplicationFirmware -match '(\d+\.){3}\d{4,}[A-Z]?'
          $ApplicationFirmware = $Matches[0]
          $OutputObject | Add-Member -MemberType NoteProperty -Name FirmwareRelease -Value $ApplicationFirmware

          $BootBlock = $OutputData.Firmware.BootBlock
          $null = $BootBlock -match '(\d+\.){3}\d{4,}[A-Z]?'
          $BootBlock = $Matches[0]
          $OutputObject | Add-Member -MemberType NoteProperty -Name BootBlockFirmware -Value $BootBlock
        }
        elseif( ($OutputData | Get-Member).Name -contains 'FirmwareRelease')
        {
          #On non-5.7.X firmwares, just grab the FirmwareRelease property.
          $OutputObject | Add-Member -MemberType NoteProperty -Name FirmwareRelease -Value $OutputData.FirmwareRelease
        }
        else
        {
          Write-Warning "Couldn't get firmware release for $ThisIPv4Address. Possible API change?"
        }

                <#### Get the uptime ###>
        if( ($OutputData | Get-Member).Name -contains "UpTime")
        {
          #Version 5.7.0
          $Uptime = New-Timespan -Days $OutputData.Uptime.Days -Hours $OutputData.Uptime.Hours -Minutes $OutputData.Uptime.Minutes -Seconds $OutputData.Uptime.Seconds
        }
        else
        {
          #All other versions
          $Uptime = Convert-UcsUptimeString -Uptime ($OutputData.UpTimeSinceLastReboot)
        }

        $OutputObject | Add-Member -MemberType NoteProperty -Name UpTimeSinceLastReboot -Value $Uptime

        $LastReboot = (Get-Date) - ($Uptime)
        $OutputObject | Add-Member -MemberType NoteProperty -Name LastReboot -Value $LastReboot

        $OutputObject
      }
    }

  }
  END
  {

  }
}

Function Restart-UcsRestPhone
{
  <#
      .SYNOPSIS
      Restarts a phone.

      .DESCRIPTION
      Invokes the safeRestart API endpoint to restart the phone. The phone will not restart in the middle of a call, but will restart as soon as possible thereafter.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .NOTES
      Will generate warnings for each phone which does not successfully restart, and status objects for each phone successfully restarted. If -Quiet is specified, no output will be returned.
  #>
  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$PassThru,
    [String][ValidateSet('Reboot','Restart')]$Type = 'Reboot',
    [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN
  {
  }
  PROCESS
  {
    foreach($ThisIPv4Address in $IPv4Address)
    {
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address)))
      {
        if($Type -eq 'Reboot')
        {
          $ApiEndpoint = 'api/v1/mgmt/safeReboot'
        }
        else
        {
          $ApiEndpoint = 'api/v1/mgmt/safeRestart'
        }
        Write-Verbose -Message ('Sending {1} command to {0}.' -f $ThisIPv4Address,$Type)
        Try
        {
          $ThisResult = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint $ApiEndpoint -Method Post -Retries $Retries -ErrorAction Stop
        }
        Catch
        {
          Write-Debug -Message $_
          Write-Error -Message "Could not $Type phone $ThisIPv4Address. Could not connect to phone."
        }

        if($ThisResult.Status.IsSuccess -ne $true)
        {
          Write-Error -Message "Failed to $Type phone $ThisIPv4Address. Phone rejected the $Type request."
          Continue
        }
      }
    }
  }
  END
  {

  }
}

Function Reset-UcsRestConfiguration
{
  <#
      .SYNOPSIS
      Restores a phone's configuration to defaults.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER ToFactoryDefaults
      Specify that the phone should be returned to factory defaults. Note: The available information does not specify the difference between the normal behavior and "ToFactoryDefaults."
  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$ToFactoryDefaults,
    [String][ValidateSet('Local','Web','Device')]$ResetConfiguration = "All",
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    #$OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address)))
      {
        Try
        {
          if($ToFactoryDefaults)
          {
            $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/factoryReset' -Method Post -Retries $Retries -ErrorAction Stop
          }
          else
          {
            if($ResetConfiguration -eq "All")
            {
              $ApiEndpoint = 'api/v1/mgmt/configReset'
            }
            else
            {
              $ApiEndpoint = ('api/v1/mgmt/configReset/{0}' -f $ResetConfiguration.ToLower())
            }

            $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint $ApiEndpoint -Method Post -Retries $Retries -ErrorAction Stop
          }
        }
        Catch
        {
          Write-Debug -Message $_
          Write-Error -Message "Couldn't reset $ThisIPv4Address to defaults. Could not connect to phone."
        }

        if($ThisOutput.Status.IsSuccess -ne $true)
        {
          Write-Debug -Message $ThisOutput.Status
          Write-Error -Message "Couldn't reset $ThisIPv4Address to defaults. An error occurred."
          Continue
        }
      }
    }
  } END {
  }
}

Function Get-UcsRestCall
{
  <#
      .SYNOPSIS
      Returns call status.

      .DESCRIPTION
      Returns the current status of a call, including detailed information such as the directionality of the call, the call's handle, which can be used to take certain actions on the call, and other call-related details. If no calls is currently in progress, the cmdlet returns a warning and no output. Returns only one call regardless of the number of ongoing calls.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Quiet
      Prevents the API request from writing to the console.

      .EXAMPLE
      Get-CallStatus -IPv4Address 192.168.1.20 -Quiet
      Returns the call status of 192.168.1.20 but does not return warnings to the console in case of errors during API calls.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$Quiet,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/webCallControl/callStatus' -Retries $Retries -ErrorAction Stop
      }
      Catch
      {
        Write-Debug -Message "Error caught: $_."
        Write-Error -Message "Couldn't get call data from $ThisIPv4Address"
        Continue
      }

      Try
      {
        #5.7 uses "DurationSeconds" instead of "DurationInSeconds"
        #In 5.8, it returns to "DurationInSeconds" for the V1 API and the changes in V1 are implemented in the V2 API.
        if( ($ThisOutput.data | Get-Member -ErrorAction Stop).Name -contains 'DurationSeconds' )
        {
          $CallDurationSeconds = $ThisOutput.data.DurationSeconds
        }
        else
        {
          $CallDurationSeconds = $ThisOutput.data.DurationInSeconds
        }
      }
      Catch
      {
        Write-Debug "No call in progress on $ThisIPv4Address."
      }

      if($null -ne $CallDurationSeconds)
      {
        $ThisCall = $ThisOutput.data
        Try
        {
          $PropertiesList = ($ThisCall | Get-Member -ErrorAction Stop).Name
        }
        Catch
        {
          Write-Debug "$ThisIPv4Address couldn't get a call."
          Continue
        }

        if($PropertiesList -contains 'UIAppearanceIndex')
        {
          if($ThisCall.UIAppearanceIndex -match '^\d+\*$')
          {
            $ActiveCall = $true
          }
          elseif ($ThisCall.UIAppearanceIndex -match '^\d+$')
          {
            $ActiveCall = $false
          }
          else
          {
            $ActiveCall = $null
          }
          $UIAppearanceIndex = $ThisCall.UiAppearanceIndex.Trim(' *')
        }

        if($ThisCall.StartTime.Length -gt 2)
        {
          $ThisStartTime = Get-Date $ThisCall.StartTime
        }
        else
        {
          $ThisStartTime = $null
        }

        if($null -ne $ThisCall.Muted)
        {
          $ThisCall.Muted = [Int]$ThisCall.Muted
        }
        if($null -ne $ThisCall.Ringing)
        {
          $ThisCall.Ringing = [Int]$ThisCall.Ringing
        }

        $ThisCallObject = New-UcsCallObject `
          -Type $ThisCall.Type `
          -CallHandle $ThisCall.CallHandle `
          -Duration (New-TimeSpan -Seconds $CallDurationSeconds) `
          -Protocol $ThisCall.Protocol.ToUpper() `
          -CallState $ThisCall.CallState `
          -RemotePartyName $ThisCall.RemotePartyName `
          -LineId $ThisCall.LineId `
          -RemotePartyNumber $ThisCall.RemotePartyNumber `
          -Muted $ThisCall.Muted `
          -Ringing $ThisCall.Muted `
          -CallSequence $ThisCall.CallSequence `
          -UIAppearanceIndex $UIAppearanceIndex `
          -ActiveCall $ActiveCall `
          -RTPPort $ThisCall.RTPPort `
          -RTCPPort $ThisCall.RTCPPort `
          -StartTime $ThisStartTime `
          -IPv4Address $ThisIPv4Address `
          -ExcludeNullProperties

        $null = $OutputArray.Add($ThisCallObject)
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestCallv2
{
  <#
      .SYNOPSIS
      Returns call status.

      .DESCRIPTION
      Returns the current status of a call, including detailed information such as the directionality of the call, the call's handle, which can be used to take certain actions on the call, and other call-related details. If no calls is currently in progress, the cmdlet returns a warning and no output. Returns only one call regardless of the number of ongoing calls.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Quiet
      Prevents the API request from writing to the console.

      .EXAMPLE
      Get-CallStatus -IPv4Address 192.168.1.20 -Quiet
      Returns the call status of 192.168.1.20 but does not return warnings to the console in case of errors during API calls.

      .NOTES
      Tested only in Skype for Business environment.
  #>
  [CmdletBinding(DefaultParameterSetName='DefaultParameterSet')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$Quiet,
    [Parameter(Mandatory,ValueFromPipelineByPropertyName,ParameterSetName='CallHandleFilter')][String][ValidatePattern('^0x[a-f0-9]{7,8}$')]$CallHandle,
    [Parameter(Mandatory,ParameterSetName='SequenceFilter')][Parameter(Mandatory,ParameterSetName='LineFilter')][Int]$LineID,
    [Parameter(ParameterSetName='SequenceFilter',Mandatory)][Int]$CallSequence,
    [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      $ApiEndpointString = 'api/v2/webCallControl/callStatus'
      if($PSCmdlet.ParameterSetName -eq 'CallHandleFilter')
      {
        $ThisCallHandle = $CallHandle.Substring(2) #API wants the part after "Ox," so we remove it.
        $ApiEndpointString += "?handle=$ThisCallHandle"
      }
      elseif($PSCmdlet.ParameterSetName -eq 'LineFilter')
      {
        $ApiEndpointString += "?line=$LineID"
      }
      elseif($PSCmdlet.ParameterSetName -eq 'SequenceFilter')
      {
        $ApiEndpointString += "?line=$LineID&sequence=$CallSequence"
      }


      Try
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint $ApiEndpointString -Retries $Retries -ErrorAction Stop
      }
      Catch
      {
        Write-Debug -Message "Error caught: $_."
        Write-Error -Message "Couldn't get call data from $ThisIPv4Address"
        Continue
      }

      foreach($ThisCall in $ThisOutput.Data)
      {
        $CallDurationSeconds = [Int]$ThisCall.DurationSeconds

        if($CallDurationSeconds -ne $null)
        {
          if($ThisCall.StartTime.Length -gt 2)
          {
            $ThisStartTime = Get-Date $ThisCall.StartTime
          }
          else
          {
            $ThisStartTime = $null
          }

          if($null -ne $ThisCall.Muted)
          {
            $ThisCall.Muted = [Int]$ThisCall.Muted
          }
          if($null -ne $ThisCall.Ringing)
          {
            $ThisCall.Ringing = [Int]$ThisCall.Ringing
          }

          $ThisCallObject = New-UcsCallObject `
          -Type $ThisCall.Type `
          -CallHandle $ThisCall.CallHandle `
          -Duration (New-TimeSpan -Seconds $CallDurationSeconds) `
          -Protocol $ThisCall.Protocol.ToUpper() `
          -CallState $ThisCall.CallState `
          -RemotePartyName $ThisCall.RemotePartyName `
          -LineId $ThisCall.LineId `
          -RemotePartyNumber $ThisCall.RemotePartyNumber `
          -Muted $ThisCall.Muted `
          -Ringing $ThisCall.Ringing `
          -CallSequence $ThisCall.CallSequence `
          -UIAppearanceIndex $ThisCall.UiAppearanceIndex `
          -RTPPort $ThisCall.RTPPort `
          -RTCPPort $ThisCall.RTCPPort `
          -StartTime $ThisStartTime `
          -IPv4Address $ThisIPv4Address

          $null = $OutputArray.Add($ThisCallObject)
        }
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestPresence
{
  <#
      .SYNOPSIS
      Returns presence information from the phone, if supported by the call server.

      .DESCRIPTION
      Returns the user's current presence as shown by the phone. Phone output has been modified to simplify parsing of status.

      .PARAMETER IPv4Address
      The phone's IP address in standard format: 192.168.1.20

      .EXAMPLE
      Get-Presence -IPv4Address 192.168.1.20
      Returns the presence of the phone at the specified IP address.

      .NOTES
      Tested only in Skype for Business environment.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/getPresence' -Retries $Retries -ErrorAction Stop
      }
      Catch
      {
        Write-Debug -Message "Caught error $_."
        Write-Error -Message "Couldn't get presence data from $ThisIPv4Address."
        Continue
      }

      if($null -ne $ThisOutput)
      {
        $Modified = $ThisOutput
        $Modified = $Modified | Select-Object -Property Presence, @{
          Name       = 'IPv4Address'
          Expression = {
            $ThisIPv4Address
          }
        }
        $null = $OutputArray.Add($Modified)
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestLineInfo
{
  <#
      .SYNOPSIS
      Returns basic device information.

      .DESCRIPTION
      The LineInfo object includes information on the currently signed in user.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Quiet
      Prevents the API request from writing to the console.

      .EXAMPLE
      Get-LineInfo -IPv4Address 192.168.1.20 -Quiet
      LineNumber         : 1
      ProxyAddress       : fakecompany.org
      Registered         : True
      Label              : John Smith
      LineType           : private
      SIPAddress         : sip:jsmith@fakecompany.org
      Protocol           : SIP
      UserID             : John Sminth
      Port               : 0
      IPv4Address        : 192.168.1.20

      .NOTES
      Behavior has not been tested in open SIP mode.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$Quiet,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/lineInfo' -Retries $Retries -ErrorAction Stop
      }
      Catch
      {
        Write-Error -Message "Couldn't get line info from $ThisIPv4Address."
        Continue
      }
      if($null -ne $ThisOutput)
      {
        Foreach($Modified in $ThisOutput.data)
        {
          if($Modified.RegistrationStatus -eq 'registered')
          {
            $Registered = $true
          }
          elseif($Modified.RegistrationStatus -eq 'unregistered')
          {
            $Registered = $false
          }
          else
          {
            $Registered = $null
          }

          if( ($Modified | Get-Member).Name -contains 'Username')
          {
            #5.7.0 format
            $SipAddress = $Modified.Username
          }
          else
          {
            if($Modified.SIPAddress -notmatch '^.+@.+\..+$')
            {
              #For consistency of output, we don't want this to give us a fake SIP address if the phone is unregistered.
              $SIPAddress = $null
            }
            else
            {
              $SIPAddress = $Modified.SIPAddress
            }
          }

          if($null -ne $SipAddress)
          {
            $SipAddress = ('sip:{0}' -f $SipAddress)
          }

          $Modified = $Modified | Select-Object -ExcludeProperty Username,SipAddress,RegistrationStatus -Property *, @{
            Name       = 'Registered'
            Expression = {
              $Registered
            }
          }, @{
            Name       = 'SIPAddress'
            Expression = {
              $SIPAddress
            }
          }, @{
            Name       = 'IPv4Address'
            Expression = {
              $ThisIPv4Address
            }
          }
          $null = $OutputArray.Add($Modified)
        }
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestSipStatus
{
  <#
      .SYNOPSIS
      Returns advanced SIP information.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/webCallControl/sipStatus' -Retries $Retries
      if($null -ne $ThisOutput)
      {
        $Modified = $ThisOutput.data
        $Modified = $Modified | Select-Object -Property *, @{
          Name       = 'IPv4Address'
          Expression = {
            $ThisIPv4Address
          }
        }
        $null = $OutputArray.Add($Modified)
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestNetworkStatistic
{
  <#
      .SYNOPSIS
      Returns basic device information.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/network/stats' -Retries $Retries -ErrorAction Stop
        if($null -ne $ThisOutput)
        {
          $Modified = $ThisOutput.data
          $Modified = $Modified | Select-Object -Property *, @{
            Name       = 'IPv4Address'
            Expression = {
              $ThisIPv4Address
            }
          }
          $Modified.RxPackets = [Int32]$Modified.RxPackets
          $Modified.TxPackets = [Int32]$Modified.TxPackets
          $Modified.UpTime = Convert-UcsUptimeString -Uptime $Modified.Uptime
          $null = $OutputArray.Add($Modified)
        }
      }
      Catch
      {
        Write-Error "Couldn't connect to $ThisIPv4Address for network stats."
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Start-UcsRestCall
{
  <#
      .SYNOPSIS
      Dial a phone

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Destination
      Call destination. SIP addresses work (no SIP prefix needed) or you could enter something like +15555551234@example.com.

      .PARAMETER LineId
      Which line number this call should be sent on.

      .PARAMETER CallType
      Which type of call this should be. Currently, only SIP is known as a valid option.

      .PARAMETER PassThru
      Return call status information.

      .EXAMPLE
      Start-PhoneCall -IPv4Address 192.168.1.2 -Destination "+15555551234@example.com"
      Initiates a call with the PSTN number 1-555-555-1234.
  #>
  Param([Parameter(Position = 1,Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Position = 2,Mandatory,HelpMessage = 'The call''s destination, such as +15555555555@example.com or example@example.com')][ValidatePattern('.+@.+\..+')][String]$Destination,
    [Parameter(Position = 3)][Int][ValidateRange(1,24)]$LineId = 1,
    [Parameter(Position = 4)][String][ValidateSet('SIP')]$CallType = 'SIP',
    [Parameter(Position = 5)][Switch]$PassThru,
    [Parameter(Position = 6)][Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      $ThisDestination = $Destination
      $ThisDestination = Get-UcsCleanJSON -String $ThisDestination

      $DialString = ("{{`"data`":{{`"Dest`": `"{0}`",`"Line`": `"{1}`",`"Type`": `"{2}`"}}}}" -f $ThisDestination, $LineId, $CallType)
      Try
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/callctrl/dial' -Method Post -Body $DialString -Retries $Retries -ErrorAction Stop
        $ThisOutput = $ThisOutput.Status
      }
      Catch
      {
        Write-Error -Message "Couldn't start call to $ThisDestination on $ThisIPv4Address. Could not connect to phone."
        Continue
      }

      if($ThisOutput.IsSuccess -eq $true)
      {
        if($PassThru -eq $true)
        {
          Start-Sleep -Seconds 1
          $ThisCall = Get-UcsRestCall -IPv4Address $IPv4Address
          $null = $OutputArray.Add($ThisCall)
        }
      }
      else
      {
        Write-Error -Message "Couldn't start call to $ThisDestination on $ThisIPv4Address. An error was returned from the phone."
        Continue
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Stop-UcsRestCall
{
  <#
      .SYNOPSIS
      Stop a phone call.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER CallHandle
      Manually specify the callhandle to end.

      .PARAMETER Force
      Skip firmware version check. On certain firmware versions, calling Stop-UcsRestCall may cause the REST API to stop responding.
  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'Medium')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(ValueFromPipelineByPropertyName)][String][ValidatePattern('^0x[a-f0-9]{7,8}$')]$CallHandle,
    [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries,
    [Switch]$Force)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address)))
      {
        if($CallHandle -notmatch '^0x[a-f0-9]{7,8}$')
        {
          #This section attempts to get a call handle if one was not provided.
          if($CallHandle.Length -gt 0)
          {
            Write-Error -Message "Invalid call handle $CallHandle provided for $ThisIPv4Address."
          }
          else
          {
            Try
            {
              $CallStatus = Get-UcsRestCall -IPv4Address $ThisIPv4Address -ErrorAction Stop
              $CallHandle = $CallStatus.CallHandle
            }
            Catch
            {
              Write-Error -Message "Couldn't get call handle for $ThisIPv4Address."
              Continue
            }
          }
        }

        if($CallHandle.Length -gt 0)
        {
          #This section only starts if we have a callhandle.
          if($Force -ne $true)
          {
            #In certain 5.5.2 releases (5.5.2.8571 on VVX 310/311 tested), using the endCall endpoint causes a failure in the REST API.
            $DeviceInfo = Get-UcsRestDeviceInfo -IPv4Address $ThisIPv4Address
            if($DeviceInfo.FirmwareRelease -like '5.5.2.*')
            {
              Write-Error ('{0} is running firmware {1} which has a known issue with Stop-UcsRestCall. Use another API or use the Force parameter.' -f $ThisIPv4Address,$DeviceInfo.FirmwareRelease)
              Continue
            }
          }
          else
          {
            #Trying to be clear at the expense of technical accuracy.
            Write-Warning "Force was specified to end the call on $ThisIPv4Address. On some phones, ending a call with Force may cause the REST API to stop responding until the next reboot."
          }

          $CallHandle = Get-UcsCleanJSON -String $CallHandle

          $CallEndString = ('{{"data":{{"Ref": "{0}"}}}}' -f $CallHandle)
          Try
          {
            $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/callctrl/endCall' -Body $CallEndString -Method Post -Retries $Retries -ErrorAction Stop
          }
          Catch
          {
            Write-Debug -Message "Caught error $_."
            Write-Error -Message "Couldn't end call $CallHandle for $ThisIPv4Address."
            Continue
          }
          $null = $OutputArray.Add($ThisOutput.Status)
        }
        else
        {
          Write-Warning -Message ('No call to end for {0}.' -f $ThisIPv4Address)
        }
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Set-UcsRestCallMute
{
  <#
      .SYNOPSIS
      Mute or unmute a call.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Mute
      Switch. If specified, mutes the call.
  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'Medium')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Switch]$Mute,
    [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      $MuteInt = 0
      if($Mute)
      {
        $MuteInt = 1
      }
      $CallMuteString = ('{{"data":{{"state": "{0}"}}}}' -f $MuteInt)
      Try
      {
        if($PSCmdlet.ShouldContinue($ThisIPv4Address,"Mute ongoing call?"))
        {
          $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/callctrl/mute' -Body $CallMuteString -Method Post -Retries $Retries -ErrorAction Stop
        }
      }
      Catch
      {
        Write-Debug -Message "Caught error $_."
        Write-Error -Message "Couldn't mute for $ThisIPv4Address."
        Continue
      }
      $null = $OutputArray.Add($ThisOutput.Status)

    }
  } END {
    Return $OutputArray
  }
}

Function Start-UcsRestCallTransfer
{
  <#
      .SYNOPSIS
      Transfer a phone call.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER CallHandle
      Manually specify the callhandle to end.

      .PARAMETER Destination
      The transfer destination. Mandatory.
  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'Medium')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(ValueFromPipelineByPropertyName)][String][ValidatePattern('^0x[a-f0-9]{7,8}$')]$CallHandle,
    [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries,
    [Parameter(Mandatory)]$Destination)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address)))
      {
        if($CallHandle -notmatch '^0x[a-f0-9]{7,8}$')
        {
          #This section attempts to get a call handle if one was not provided.
          if($CallHandle.Length -gt 0)
          {
            Write-Error -Message "Invalid call handle $CallHandle provided for $ThisIPv4Address."
          }
          else
          {
            Try
            {
              $CallStatus = Get-UcsRestCall -IPv4Address $ThisIPv4Address -ErrorAction Stop
              $CallHandle = $CallStatus.CallHandle
            }
            Catch
            {
              Write-Error -Message "Couldn't get call handle for $ThisIPv4Address."
              Continue
            }
          }
        }

        if($CallHandle.Length -gt 0)
        {
          $CallHandle = Get-UcsCleanJSON -String $CallHandle

          $TransferString = ('{{"data":{{"Ref": "{0}","TransferDest":"{1}"}}}}' -f $CallHandle,$Destination)
          Try
          {
            $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/callctrl/transferCall' -Body $TransferString -Method Post -Retries $Retries -ErrorAction Stop
          }
          Catch
          {
            Write-Debug -Message "Caught error $_."
            Write-Error -Message "Couldn't end call $CallHandle for $ThisIPv4Address."
            Continue
          }
          $null = $OutputArray.Add($ThisOutput.Status)
        }
        else
        {
          Write-Warning -Message ('No call to end for {0}.' -f $ThisIPv4Address)
        }
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Send-UcsRestCallDTMF
{
  <#
      .SYNOPSIS
      Send keypad commands.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.
  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'Medium')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory)][ValidatePattern('^[0-9\#\*]+$')][String]$Digits,
    [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      $DTMFstring = ('{{"data":{{"Digits": "{0}"}}}}' -f $Digits)
      Try
      {
        if($PSCmdlet.ShouldContinue($ThisIPv4Address,"Send $Digits?"))
        {
          $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/callctrl/sendDTMF' -Body $DTMFstring -Method Post -Retries $Retries -ErrorAction Stop
        }
      }
      Catch
      {
        Write-Debug -Message "Caught error $_."
        Write-Error -Message "Couldn't send DTMF for $ThisIPv4Address."
        Continue
      }
      $null = $OutputArray.Add($ThisOutput.Status)

    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestCallLog
{
  <#
      .SYNOPSIS
      Get call logs from phone.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Filter
      Filter to missed, received, or placed.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [ValidateSet('All','Missed','Incoming','Outgoing')][String]$Filter = 'All',
    [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
    $FilterMapping = @{'All'='all';'Missed'='missed';'Incoming'='received';'Outgoing'='placed'}
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      if($Filter -eq 'All')
      {
        $FilterString = 'api/v1/mgmt/callLogs'
      }
      else
      {
        $FilterString = ('api/v1/mgmt/callLogs/{0}' -f $FilterMapping[$Filter])
      }

      Try
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint $FilterString -Method Get -Retries $Retries -ErrorAction Stop
      }
      Catch
      {
        Write-Debug -Message "Caught error $_."
        Write-Error -Message "Couldn't get calls for $ThisIPv4Address."
        Continue
      }

      $AllCallList = New-Object System.Collections.ArrayList

      if($Filter -eq 'All')
      {
        $CallCategories = $ThisOutput.Data | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

        Foreach($Category in $CallCategories)
        {
          Foreach($Call in $ThisOutput.Data.$Category)
          {
            $ThisCallType = $Category
            $null = $AllCallList.Add($Call)
          }
        }
      }
      else
      {
        Foreach($Call in $ThisOutput.Data)
        {
          $ThisCallType = $Filter
          $null = $AllCallList.Add($Call)
        }
      }

      Foreach($Call in $AllCallList)
      {
        $ThisCallObject = New-UcsCallObject `
          -Type $ThisCallType `
          -StartTime $Call.StartTime `
          -RemotePartyName $Call.RemotePartyName `
          -RemotePartyNumber $Call.RemotePartyNumber `
          -LineId $Call.LineNumber `
          -IPv4Address $ThisIPv4Address `
          -ExcludeNullProperties

        $null = $OutputArray.Add($ThisCallObject)
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Set-UcsRestCallHold
{
  <#
      .SYNOPSIS
      Hold or resume a call.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Hold
      Boolean. If true, places the call on hold. If false, resumes a held call.

  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'Medium')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Boolean]$Hold = $true,
    [Parameter(ValueFromPipelineByPropertyName)][String][ValidatePattern('^0x[a-f0-9]{7,8}$')]$CallHandle,
    [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      if($CallHandle.Length -gt 4)
      {
        $CallRefString = ('{{"data":{{"Ref": "{0}"}}}}' -f [Int]$CallHandle)
      }
      else
      {
        $CallRefString = ''
      }

      Try
      {
        if($PSCmdlet.ShouldContinue($ThisIPv4Address,"Hold/Resume ongoing call?"))
        {
          if($Hold)
          {
            $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/callctrl/holdCall' -Body $CallRefString -Method Post -Retries $Retries -ErrorAction Stop
          }
          else
          {
            $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/callctrl/resumeCall' -Body $CallRefString -Method Post -Retries $Retries -ErrorAction Stop
          }
        }
      }
      Catch
      {
        Write-Debug -Message "Caught error $_."
        Write-Error -Message "Couldn't hold/resume for $ThisIPv4Address."
        Continue
      }
      $null = $OutputArray.Add($ThisOutput.Status)

    }
  } END {
    Return $OutputArray
  }
}

Function Start-UcsRestCallAnswer
{
  <#
      .SYNOPSIS
      Take an action on a current ringing call.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER CallHandle
      Optional. If specified, answers the specified call.

      .PARAMETER Ignore
      Switch. If specified, call is ignored instead of answered.

      .PARAMETER Reject
      Switch. If specified, call is rejected instead of answered. Takes precedence over Ignore.
  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'Medium')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(ValueFromPipelineByPropertyName)][String][ValidatePattern('^0x[a-f0-9]{7,8}$')]$CallHandle,
    [Switch]$Ignore,
    [Switch]$Reject,
    [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      if($CallHandle.Length -gt 4)
      {
        $CallRefString = ('{{"data":{{"Ref": "{0}"}}}}' -f [Int]$CallHandle)
      }
      else
      {
        $CallRefString = ''
      }

      Try
      {
        if($PSCmdlet.ShouldContinue($ThisIPv4Address,"Take action on inbound call?"))
        {
          if($Reject)
          {
            $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/callctrl/rejectCall' -Body $CallRefString -Method Post -Retries $Retries -ErrorAction Stop
          }
          elseif($Ignore)
          {
            $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/callctrl/ignoreCall' -Body $CallRefString -Method Post -Retries $Retries -ErrorAction Stop
          }
          else
          {
            $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/callctrl/answerCall' -Body $CallRefString -Method Post -Retries $Retries -ErrorAction Stop
          }
        }
      }
      Catch
      {
        Write-Debug -Message "Caught error $_."
        Write-Error -Message "Couldn't answer for $ThisIPv4Address."
        Continue
      }
      $null = $OutputArray.Add($ThisOutput.Status)

    }
  } END {
    Return $OutputArray
  }
}

Function Get-UcsRestStatus
{
  <#
      .SYNOPSIS
      Polls for idle/active/error state

      .PARAMETER IPv4Address
      The phone's IP address in standard format: 192.168.1.20

      .EXAMPLE
      Get-Presence -IPv4Address 192.168.1.20
      Returns the presence of the phone at the specified IP address.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/pollForStatus' -Retries $Retries -ErrorAction Stop
      }
      Catch
      {
        Write-Debug -Message "Caught error $_."
        Write-Error -Message "Couldn't get status data from $ThisIPv4Address."
        Continue
      }

      if($null -ne $ThisOutput)
      {
        $Modified = $ThisOutput.data

        $Duration = $null
        $TimeofLastCall = $null
        $ErrorString = $null

        if($Modified.State -eq "Active")
        {
          #We're in a call. Provision a "duration" property.
          $DurationString = $Modified.StateData.Replace('Active call duration','').Trim()
          $Duration = Convert-UcsRestDuration -Duration $DurationString
        }
        elseif($Modified.State -eq "Idle")
        {
          #No call in progress. Provision a "Time since last call" property.
          $LastCallString = $Modified.StateData.Replace('Time of last call','').Trim()
          $TimeofLastCall = Get-Date $LastCallString
        }
        else
        {
          #Probably an error.
          $ErrorString = $Modified.StateData
        }

        $Modified = $Modified | Select-Object -Property State,@{Name='Duration';Expression={$Duration}},@{Name='TimeOfLastCall';Expression={$TimeOfLastCall}},@{Name='ErrorString';Expression={$ErrorString}},@{
          Name       = 'IPv4Address'
          Expression = {
            $ThisIPv4Address
          }
        }
        $null = $OutputArray.Add($Modified)
      }
    }
  } END {
    Return $OutputArray
  }
}

Function Start-UcsRestPacketCapture
{
  <#
      .SYNOPSIS
      Begin uploading captured network packets to a specified URL.

      .DESCRIPTION
      Upload captured network packets to a provisioning server or other location. If unspecified, the phone uploads to its provisioning server. There is no way to end a background packet capture explicitly.

      .PARAMETER IPv4Address
      The phone's IP address in standard format: 192.168.1.20

      .NOTES
      May require additional configuration, including enabling diags.pcap.enabled and diags.pcap.background.enabled. See Polycom documentation for details.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [String]$URL = $null,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN
  {
  }

  PROCESS
  {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        if($null -eq $URL)
        {
          $null = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/network/uploadBgCapture' -Retries $Retries -Method Post -ErrorAction Stop
        }
        else
        {
          $URLBody = ('{{"data":{{"url": "{0}"}}}}' -f $URL)
          $null = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/network/uploadBgCapture' -Body $URLBody -Retries $Retries -Method Post -ErrorAction Stop
        }
      }
      Catch
      {
        Write-Debug -Message "Caught error $_."
        Write-Error -Message "Couldn't start capturing packets from $ThisIPv4Address."
        Continue
      }

    }
  }

  END
  {
  }
}

Function Get-UcsRestDeviceStatistic
{
  <#
      .SYNOPSIS
      Returns device hardware statistics.

      .DESCRIPTION
      Provides hardware statistics directly from the phone's API. The Cmdlet currently doesn't provide any cleanup of values.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN
  {

  }
  PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/device/stats' -Retries $Retries -ErrorAction Stop
        $ThisOutput.data | Select-Object *,@{Name="IPv4Address";Expression={$ThisIPv4Address}}
      }
      Catch
      {
        Write-Error "Couldn't connect to $ThisIPv4Address for device stats."
      }
    }
  }
  END
  {
  }
}

Function Register-UcsRestLyncUser
{
  <#
      .SYNOPSIS
      Sign in a Skype/Lync user to the phone.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .PARAMETER Credential
      The username and password for the account.

      .PARAMETER Address
      Sign-in address, such as jsmith@company.com

      .PARAMETER LockCode
      Optional, specify a code to be used when unlocking the phone.

      .NOTE
      The default timeout for this cmdlet is 155 seconds.

  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'Medium')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory,HelpMessage='jsmith@company.com')][String]$Address,
    [Parameter(Mandatory,HelpMessage='A credential corresponding to the sign-in address already provided.')][PsCredential]$Credential,
    [String]$Domain = $null,
    [Int]$LockCode = $null,
    [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries,
    [ValidateRange(1,1000)][Int]$Timeout = 155
    )

  BEGIN
  {

  }
  PROCESS
  {
    foreach ($ThisIPv4Address in $IPv4Address)
    {

      Try
      {
        if($null -eq $LockCode)
        {
          $SignInString = ('{{"data":{{"Address": "{0}","User": "{1}","Password": "{2}","Domain": "{3}"}}}}' -f $Address,$Credential.UserName,(ConvertFrom-PsCredential -Credential $Credential),$Domain)
        }
        else
        {
          $SignInString = ('{{"data":{{"Address": "{0}","User": "{1}","Password": "{2}","Domain": "{3}","LockCode": "{4}"}}}}' -f $Address,$Credential.UserName,(ConvertFrom-PsCredential -Credential $Credential),$Domain,$LockCode)
        }

        if ($PSCmdlet.ShouldContinue($ThisIPv4Address)) {
          $null = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/skype/signIn' -Body $SignInString -Method Post -Retries $Retries -Timeout $Timeout -ErrorAction Stop
        }
      }
      Catch
      {
        Write-Debug -Message "Caught error $_."
        Write-Error -Message "Couldn't sign-in for $ThisIPv4Address."
        Continue
      }


    }
  }
  END
  {
  }
}

Function Unregister-UcsRestLyncUser
{
  <#
      .SYNOPSIS
      Sign out a Skype/Lync user.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.

      .NOTE
      The default timeout for this cmdlet is 20 seconds.

  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries,
    [ValidateRange(1,1000)][Int]$Timeout = 155
    )

  BEGIN
  {

  }
  PROCESS
  {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      if ($PSCmdlet.ShouldProcess($ThisIPv4Address)) {
        Try
        {
          $null = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/skype/signOut' -Method Post -Retries $Retries -Timeout $Timeout -ErrorAction Stop
        }
        Catch
        {
          Write-Debug -Message "Caught error $_."
          Write-Error -Message "Couldn't sign out $ThisIPv4Address."
          Continue
        }
      }
    }
  }
  END
  {
  }
}

Function Get-UcsRestLocationInfo
{
  <#
      .SYNOPSIS
      Returns device location information.

      .DESCRIPTION
      Provides location info directly from the phone's API. The Cmdlet currently doesn't provide any cleanup of values.

      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Int][ValidateRange(1,100)]$Retries = (Get-UcsConfig -Api REST).Retries)

  BEGIN
  {

  }
  PROCESS {
    foreach ($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        $ThisOutput = Invoke-UcsRestMethod -IPv4Address $ThisIPv4Address -ApiEndpoint 'api/v1/mgmt/location/info' -Method Get -Retries $Retries -ErrorAction Stop
        $ThisOutput.data | Select-Object *,@{Name="IPv4Address";Expression={$ThisIPv4Address}}
      }
      Catch
      {
        Write-Error "Couldn't connect to $ThisIPv4Address for location info."
      }
    }
  }
  END
  {
  }
}