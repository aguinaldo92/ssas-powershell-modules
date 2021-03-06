function Invoke-SSASProcessCommand
{
	[CmdletBinding(DefaultParameterSetName = "conn")]
	param(				
		[Parameter(Mandatory=$true, ParameterSetName = "connStr")] [string] $connectionString,
		[Parameter(Mandatory=$true, ParameterSetName = "conn")] [Microsoft.AnalysisServices.AdomdClient.AdomdConnection] $connection,
		
		[Parameter(Mandatory=$false)] [string] $database,
		[Parameter(Mandatory=$false)] [string] $table,
		[Parameter(Mandatory=$false)] [string] $partition,
		[Parameter(Mandatory=$false)] [array] $objects,
		[Parameter(Mandatory=$false)] 
		[ValidateSet("full", "data", "clear", "automatic", "clear")] 
		[string] $processType = "full"
		)			
	
   if ($objects -eq $null)
   {
	    
		if ([string]::IsNullOrEmpty($database))
		{
			throw "Must specify -database or -objects parameter"
		}

		$obj = @{
			"database" = $database		
		}

		if (-not [string]::IsNullOrEmpty($table))
		{
			$obj["table"] = $table;
		}
		
		if (-not [string]::IsNullOrEmpty($partition))
		{
			$obj["partition"] = $partition;
		}

		$objects = @($obj)
   }
   
   $objectsJson = ConvertTo-Json $objects

   $processCommand = "
   {
	  `"refresh`": {
	    `"type`": `"$processType`",
	    `"objects`": $objectsJson
	  }
	}"
										
	if ($PsCmdlet.ParameterSetName -eq "connStr")
	{	
		$connection = Get-SSASConnection -connectionString $connectionString -open															
	}
	
	Invoke-SSASCommand -connection $connection -commandText $processCommand	  

	Write-Verbose "Successfully processed $($objects.Count) objects."		
}

function Invoke-SSASCreatePartition
{
	[CmdletBinding(DefaultParameterSetName = "conn")]
	param(				
		[Parameter(Mandatory=$true, ParameterSetName = "connStr")] [string] $connectionString,
		[Parameter(Mandatory=$true, ParameterSetName = "conn")] [Microsoft.AnalysisServices.AdomdClient.AdomdConnection] $connection,

		[Parameter(Mandatory=$true)] [string] $database,
		[Parameter(Mandatory=$true)] [string] $table,
		[Parameter(Mandatory=$true)] [string] $partition,
		[Parameter(Mandatory=$true)] [string] $query,
		[Parameter(Mandatory=$true)] [string] $datasource
		)			

   $cmdText = "
   	{
		`"createOrReplace`": {
			`"object`": {
			`"database`": `"$database`",
			`"table`": `"$table`",
			`"partition`": `"$partition`"
			},
			`"partition`": {
				`"name`": `"$partition`",
				`"source`": {
					`"query`": `"$query`",
					`"dataSource`": `"$datasource`"
				}
			}
		}
	}"

	if ($PsCmdlet.ParameterSetName -eq "connStr")
	{	
		$connection = Get-SSASConnection -connectionString $connectionString -open															
	}

	Invoke-SSASCommand -connection $connection -commandtext $cmdText

	Write-Verbose "Partition $partition successfully (re)created!"		
}

function Invoke-SSASCommand
{
	[CmdletBinding(DefaultParameterSetName = "connStr")]
	param(				
		[Parameter(Mandatory=$true, ParameterSetName = "connStr")] [string] $connectionString,
		[Parameter(Mandatory=$true, ParameterSetName = "conn")] [Microsoft.AnalysisServices.AdomdClient.AdomdConnection] $connection,
		[Parameter(Mandatory=$true)] [string] $commandText,
		[Parameter(Mandatory=$false)] 
		[ValidateSet("nonQuery", "query")] 
		[string] $commandType = "nonQuery"
		)			
	
	try {

		if ($PsCmdlet.ParameterSetName -eq "connStr")
		{	
			$connection = Get-SSASConnection -connectionString $connectionString -open -Verbose											
		}

		$cmd = $connection.CreateCommand()
		
		$cmd.CommandText = $commandText
				
		Write-Verbose "Executing SSAS Command: '$commandText'"

		switch ($commandType) {
			"nonQuery" { $cmd.ExecuteNonQuery() | Out-Null }
			"query" { 

				try {
					$reader = $cmd.ExecuteReader()
			
					while($reader.Read())
					{
						$hashRow = @{}
						
						for ($fieldOrdinal = 0; $fieldOrdinal -lt $reader.FieldCount; $fieldOrdinal++)
						{
							$key = $reader.GetName($fieldOrdinal)
							$value = $reader.GetValue($fieldOrdinal)					
							if ($value -is [DBNull]) { $value = $null }
							
							$hashRow.Add($key, $value);                        
						}
						
						Write-Output $hashRow
					}
				}
				finally {
					
					if ($reader)
					{
						$reader.Close()
						$reader.Dispose()
					}
				}			

				#$reader = $cmd.ExecuteReader()
				#,$reader 
				# ...note the comma in front of the $reader. As PowerShell implicitly tries to unpack collection objects, this comma forces the collection to be returned intact.
				# https://social.technet.microsoft.com/Forums/en-US/1ccf16ce-d771-49cb-825e-8330bf2e1e99/powershell-possible-to-return-a-datareader-object-from-a-function-call?forum=ITCG
			}
			Default { $cmd.ExecuteNonQuery() | Out-Null }
		}

	}
	finally{
		
		$cmd.Dispose()       

		if ($PsCmdlet.ParameterSetName -eq "connStr")
		{	
    		$connection.Dispose()
		}
	}
	
}

function Get-SSASConnection
{
	[CmdletBinding()]
	param(					
		[Parameter(Mandatory=$true)] [string] $connectionString,
		[switch] $open = $false
		)			

	$connection = new-object Microsoft.AnalysisServices.AdomdClient.AdomdConnection

    $connection.ConnectionString = $connectionString        
	
	if ($open)
	{
		Write-Verbose ("Opening Connection to: '{0}'" -f $connection.ConnectionString)
				
		$connection.Open()
	}
		
	Write-Output $connection
}

function Set-AzureASState
{
	[CmdletBinding()]
    param(
            [Parameter(Mandatory = $true)] [System.String]$resourceGroupName,
            [Parameter(Mandatory = $true)] [System.String]$serverName,
			[Parameter(Mandatory = $true)] [System.String]$ApplicationID,
			[Parameter(Mandatory = $true)] [System.String]$ApplicationKey,
			[Parameter(Mandatory = $true)] [System.String]$tennantid,
			[Parameter(Mandatory = $true)] [System.String]$SubscriptionId,
			[Parameter(Mandatory = $false)] [ValidateSet('suspend','resume')] [System.String]$action = 'suspend',
            [Parameter(Mandatory = $false)] [System.Boolean]$WeekendOff = $false
    )
    $TokenEndpoint = {https://login.windows.net/{0}/oauth2/token} -f $tennantid 
    $ARMResource = "https://management.core.windows.net/"

    $Body = @{
            'resource'= $ARMResource
            'client_id' = $ApplicationID
            'grant_type' = 'client_credentials'
            'client_secret' = $ApplicationKey
    }

    $params = @{
        ContentType = 'application/x-www-form-urlencoded'
        Headers = @{'accept'='application/json'}
        Body = $Body
        Method = 'Post'
        URI = $TokenEndpoint
    }

    $token = Invoke-RestMethod @params

    #If is weekend and is supposed not to resume ($WeekendOff value), change $action to suspend
    $weekendDays = "Sunday","Saturday"

    $currentDayOfWeek = (Get-Date).DayOfWeek

    if($weekendDays -contains $currentDayOfWeek -and $action -eq "resume" -and $WeekendOff){
        $action = "suspend"
    }
    
    $requestUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.AnalysisServices/servers/$serverName/$action ?api-version=2016-05-16"

    $params = @{
        ContentType = 'application/x-www-form-urlencoded'
        Headers = @{'authorization'="Bearer $($Token.access_token)"}
        Method = 'Post'
        URI = $requestUri
    }

    Invoke-RestMethod @params
}