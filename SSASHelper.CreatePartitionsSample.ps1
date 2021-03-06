# Clear the screen
cls

# On error stop the script
$ErrorActionPreference = "Stop"

# Get the current folder of the running script
$currentPath = (Split-Path $MyInvocation.MyCommand.Definition -Parent)

# Import helper modules
Import-Module "$currentPath\Modules\SSASHelper" -Force

# Connection strings (on prem & Azure)
# ex: "Data Source=.\sql2016tb;Initial Catalog=Adventure Works Internet Sales;"
$connStr = (Get-Content "$currentPath\SSASTestConnStr.txt" | Out-String)		

# Create partitions
2009..2015|%{
	
	$startYear = $_	

	$endYear = $_ + 1

	$query = "SELECT *
	          FROM [dbo].[FactInternetSales] 
			  WHERE (([OrderDate] >= N'$startYear-01-01') AND ([OrderDate] < N'$endYear-01-01'))"
			  
	
	# Create/Update the partition
	Invoke-SSASCreatePartition -connectionString $connStr `
		-database "AW Internet Sales Tabular Model" `
		-table "Internet Sales" -partition "Internet Sales $startYear" `
		-datasource "Adventure Works DB from SQL" `
		-query $query `
		-verbose
}
	
