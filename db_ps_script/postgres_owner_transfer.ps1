# Function to run psql commands
function Run-PsqlCommand {
    param (
        [string]$Command,
        [string]$PgHost,
        [string]$Port,
        [string]$Username,
        [string]$Password,
        [string]$Database = "postgres"
    )
    # Check if psql is available
    if (-not (Get-Command psql -ErrorAction SilentlyContinue)) {
        Write-Error "psql command not found. Ensure PostgreSQL client is installed and added to PATH."
        return $null
    }

    # Set PGPASSWORD environment variable
    $env:PGPASSWORD = $Password
    $psqlCommand = "psql -h $PgHost -p $Port -U $Username -d $Database -t -A -c `"$Command`""
    Write-Debug "Executing psql command: $psqlCommand"

    # Execute command and capture output
    try {
        $result = Invoke-Expression $psqlCommand 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error "psql command failed with exit code $LASTEXITCODE`: $result"
            return $false
        }
        return $result
    }
    catch {
        Write-Error "Exception executing psql: $_"
        return $false
    }
    finally {
        $env:PGPASSWORD = $null
    }
}

# Function to validate connection to PostgreSQL
function Test-PostgreSQLConnection {
    param (
        [string]$PgHost,
        [string]$Port,
        [string]$Username,
        [string]$Password
    )
   
    $testQuery = "SELECT 1;"
    $result = Run-PsqlCommand -Command $testQuery -PgHost $PgHost -Port $Port -Username $Username -Password $Password
   
    return ($result -ne $false)
}

# Function to get validated input
function Get-ValidatedInput {
    param (
        [string]$Prompt,
        [string]$DefaultValue = "",
        [switch]$IsPassword,
        [switch]$AllowEmpty,
        [scriptblock]$ValidationScript = $null
    )
   
    $isValid = $false
    $value = $null
   
    while (-not $isValid) {
        if ($IsPassword) {
            $secureValue = Read-Host $Prompt -AsSecureString
            $value = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue))
        } else {
            $value = Read-Host $Prompt
        }
       
        # Apply default value if empty and allowed
        if ([string]::IsNullOrWhiteSpace($value) -and -not [string]::IsNullOrWhiteSpace($DefaultValue)) {
            $value = $DefaultValue
            Write-Host "Using default value: $DefaultValue"
        }
       
        # Check if empty is allowed
        if ([string]::IsNullOrWhiteSpace($value) -and -not $AllowEmpty) {
            Write-Host "Invalid input: Value cannot be empty. Please try again."
            continue
        }
       
        # Run custom validation if provided
        if ($ValidationScript -ne $null) {
            $validationResult = & $ValidationScript $value
            if (-not $validationResult) {
                continue
            }
        }
       
        $isValid = $true
    }
   
    return $value
}

# Step 1: Ask for PostgreSQL credentials with validation
Write-Host "=== PostgreSQL Ownership Transfer Tool ===" -ForegroundColor Cyan
Write-Host "Enter PostgreSQL credentials:" -ForegroundColor Green

$connectionValid = $false
while (-not $connectionValid) {
    $PgHost = Get-ValidatedInput -Prompt "Host (default: localhost)" -DefaultValue "localhost"
   
    $Port = Get-ValidatedInput -Prompt "Port (default: 5432)" -DefaultValue "5432" -ValidationScript {
        param($value)
        if ($value -match '^\d+$' -and [int]$value -gt 0 -and [int]$value -le 65535) {
            return $true
        } else {
            Write-Host "Invalid port number: Must be a number between 1 and 65535. Please try again."
            return $false
        }
    }
   
    $Username = Get-ValidatedInput -Prompt "Username" -ValidationScript {
        param($value)
        if ($value -match '^[a-zA-Z0-9_]+$') {
            return $true
        } else {
            Write-Host "Invalid username: Must contain only letters, numbers, and underscores. Please try again."
            return $false
        }
    }
   
    $Password = Get-ValidatedInput -Prompt "Password" -IsPassword
   
    Write-Host "Testing connection to PostgreSQL server..." -ForegroundColor Yellow
    $connectionValid = Test-PostgreSQLConnection -PgHost $PgHost -Port $Port -Username $Username -Password $Password
   
    if (-not $connectionValid) {
        Write-Host "Connection failed! Please check your credentials and try again." -ForegroundColor Red
    }
}

Write-Host "Connection successful!" -ForegroundColor Green

# Step 2: List all databases
Write-Host "`nList of all the databases:" -ForegroundColor Cyan
$databases = Run-PsqlCommand -Command "SELECT datname FROM pg_database WHERE datistemplate = false;" -PgHost $PgHost -Port $Port -Username $Username -Password $Password
if ($databases) {
    $databaseList = @()
    $databases | ForEach-Object {
        $db = $_.Trim()
        if (-not [string]::IsNullOrWhiteSpace($db)) {
            $databaseList += $db
            Write-Host "- $db"
        }
    }
}
else {
    Write-Error "Failed to retrieve databases. Check credentials, host, port, or psql installation."
    exit
}

# List all users
Write-Host "`nList of all the users:" -ForegroundColor Cyan
$users = Run-PsqlCommand -Command "SELECT usename FROM pg_user;" -PgHost $PgHost -Port $Port -Username $Username -Password $Password
if ($users) {
    $userList = @()
    $users | ForEach-Object {
        $user = $_.Trim()
        if (-not [string]::IsNullOrWhiteSpace($user)) {
            $userList += $user
            Write-Host "- $user"
        }
    }
}
else {
    Write-Error "Failed to retrieve users."
    exit
}

# Step 3: Ask for user to check ownership
$targetUser = Get-ValidatedInput -Prompt "`nEnter the username whose ownership details you want to view" -ValidationScript {
    param($value)
    if ($userList -contains $value) {
        return $true
    } else {
        Write-Host "Invalid username: '$value' not found in the database. Please enter one of the listed users." -ForegroundColor Red
        return $false
    }
}

Write-Host "`nOwnership details of '$targetUser':" -ForegroundColor Green

# Step 4: Ask if user wants to view all databases or a specific database
$dbOption = Get-ValidatedInput -Prompt "`nDo you want to view ownership for all databases (0) or a specific database (1)?" -ValidationScript {
    param($value)
    if ($value -eq "0" -or $value -eq "1") {
        return $true
    } else {
        Write-Host "Invalid option. Please enter 0 for all databases or 1 for a specific database." -ForegroundColor Red
        return $false
    }
}

$selectedDatabases = @()
$schemaFilter = ""

if ($dbOption -eq "0") {
    # Use all databases
    $selectedDatabases = $databaseList
}
else {
    # Query for databases where the user owns at least one table
    $databasesWithOwnership = @()
    $dbIndex = 1
    $dbMapping = @{}
    
    Write-Host "`nDatabases where user '$targetUser' has ownership:" -ForegroundColor Cyan
    
    foreach ($db in $databaseList) {
        # Check if the user has any ownership in this database
        $query = @"
SELECT COUNT(*)
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_user u ON c.relowner = u.usesysid
WHERE u.usename = '$targetUser'
AND c.relkind = 'r';
"@
        
        $result = Run-PsqlCommand -Command $query -PgHost $PgHost -Port $Port -Username $Username -Password $Password -Database $db
        
        if ($result -ne $false -and [int]$result -gt 0) {
            $databasesWithOwnership += $db
            $dbMapping[$dbIndex] = $db
            Write-Host "$dbIndex. $db ($result tables)"
            $dbIndex++
        }
    }
    
    if ($databasesWithOwnership.Count -eq 0) {
        Write-Host "No databases found where '$targetUser' has ownership." -ForegroundColor Yellow
        exit
    }
    
    $dbNumber = Get-ValidatedInput -Prompt "`nEnter the number of the database you want to view" -ValidationScript {
        param($value)
        if ($value -match '^\d+$' -and [int]$value -ge 1 -and [int]$value -lt $dbIndex) {
            return $true
        } else {
            Write-Host "Invalid database number. Please enter a number between 1 and $($dbIndex-1)." -ForegroundColor Red
            return $false
        }
    }
    
    $selectedDatabases = @($dbMapping[[int]$dbNumber])
    Write-Host "Selected database: $($selectedDatabases[0])" -ForegroundColor Green
    
    # Step 5: Ask if user wants to view all schemas or specific schemas (ONLY if a specific database was selected)
    $schemaOption = Get-ValidatedInput -Prompt "`nDo you want to view ownership for all schemas (0) or specific schemas (1)?" -ValidationScript {
        param($value)
        if ($value -eq "0" -or $value -eq "1") {
            return $true
        } else {
            Write-Host "Invalid option. Please enter 0 for all schemas or 1 for specific schemas." -ForegroundColor Red
            return $false
        }
    }

    # Process schema selection if user chose specific schemas
    if ($schemaOption -eq "1") {
        $db = $selectedDatabases[0]
        # Get schemas where user has ownership
        $schemaQuery = @"
SELECT DISTINCT n.nspname AS schema_name
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_user u ON c.relowner = u.usesysid
WHERE u.usename = '$targetUser'
AND c.relkind = 'r'
ORDER BY n.nspname;
"@
        
        $schemas = Run-PsqlCommand -Command $schemaQuery -PgHost $PgHost -Port $Port -Username $Username -Password $Password -Database $db
        
        if ($schemas -ne $false) {
            $schemaList = @()
            $schemaIndex = 1
            $schemaMapping = @{}
            
            Write-Host "`nSchemas in database '$db' where user '$targetUser' has ownership:" -ForegroundColor Cyan
            
            $schemas | ForEach-Object {
                $schema = $_.Trim()
                if (-not [string]::IsNullOrWhiteSpace($schema)) {
                    $schemaList += $schema
                    $schemaMapping[$schemaIndex] = $schema
                    Write-Host "$schemaIndex. $schema"
                    $schemaIndex++
                }
            }
            
            if ($schemaList.Count -eq 0) {
                Write-Host "No schemas found in database '$db' where '$targetUser' has ownership." -ForegroundColor Yellow
                exit
            }
            
            $schemaNumbers = Get-ValidatedInput -Prompt "`nEnter the schema numbers you want to view (comma-separated)" -ValidationScript {
                param($value)
                $valid = $true
                $selectedNums = $value -split ',' | ForEach-Object { $_.Trim() }
                
                foreach ($num in $selectedNums) {
                    if (-not ($num -match '^\d+$' -and [int]$num -ge 1 -and [int]$num -lt $schemaIndex)) {
                        $valid = $false
                        Write-Host "Invalid schema number: $num. Please enter numbers between 1 and $($schemaIndex-1)." -ForegroundColor Red
                        break
                    }
                }
                
                return $valid
            }
            
            $selectedSchemas = @()
            $schemaNumbers -split ',' | ForEach-Object {
                $selectedSchemas += $schemaMapping[[int]$_.Trim()]
            }
            
            # Build schema filter for the query
            $schemaFilter = "AND n.nspname IN ('" + ($selectedSchemas -join "','") + "')"
        }
    }
}

# Now build and execute the query to get ownership details
$ownershipTable = @()
$index = 1

foreach ($db in $selectedDatabases) {
    # Build the query with optional schema filter
    $query = @"
SELECT
    n.nspname AS schemaname,
    c.relname AS table,
    u.usename AS owner
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_user u ON c.relowner = u.usesysid
WHERE u.usename = '$targetUser'
AND c.relkind = 'r'
$schemaFilter
ORDER BY n.nspname, c.relname;
"@

    # Test connection to the database
    $testQuery = "SELECT current_database();"
    $testResult = Run-PsqlCommand -Command $testQuery -PgHost $PgHost -Port $Port -Username $Username -Password $Password -Database $db
    if ($testResult -eq $false) {
        Write-Warning "Cannot connect to database '$db'. Skipping."
        continue
    }

    # Run ownership query
    $result = Run-PsqlCommand -Command $query -PgHost $PgHost -Port $Port -Username $Username -Password $Password -Database $db
    if ($result -ne $false) {
        $result | ForEach-Object {
            $row = $_ -split '\|'
            if ($row.Count -eq 3) {
                $ownershipTable += [PSCustomObject]@{
                    S_No          = $index
                    Database_Name = $db
                    Schema_Name   = $row[0]
                    Table_Name    = $row[1]
                    Owner         = $row[2]
                }
                $index++
            }
            else {
                Write-Warning "Unexpected row format in database $db`: $_"
            }
        }
    }
    else {
        Write-Warning "No results or error querying database: $db"
    }
}

# Display ownership table with numbers
if ($ownershipTable.Count -gt 0) {
    Write-Host "`nDetailed ownership results:" -ForegroundColor Cyan
    $ownershipTable | Format-Table -Property S_No, Database_Name, Schema_Name, Table_Name, Owner -AutoSize
}
else {
    Write-Host "No tables owned by '$targetUser' found with the specified criteria." -ForegroundColor Yellow
    exit
}

# Step 6: Transfer ownership
$proceed = Get-ValidatedInput -Prompt "`nWould you like to transfer ownership from '$targetUser'? (1/0)" -ValidationScript {
    param($value)
    if ($value -eq '1' -or $value -eq '0') {
        return $true
    } else {
        Write-Host "Invalid input: Please enter '1' for yes or '0' for no." -ForegroundColor Red
        return $false
    }
}

if ($proceed -eq '1') {
    $newOwner = Get-ValidatedInput -Prompt "Please enter the username you want to transfer ownership to" -ValidationScript {
        param($value)
        if ($userList -contains $value) {
            return $true
        } else {
            Write-Host "Invalid username: '$value' not found in the database. Please enter one of the listed users." -ForegroundColor Red
            return $false
        }
    }
   
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "1. Transfer ownership of specific table or table's"
    Write-Host "2. Transfer all ownerships of '$targetUser' to '$newOwner'"
   
    $option = Get-ValidatedInput -Prompt "Select option (1 or 2)" -ValidationScript {
        param($value)
        if ($value -eq '1' -or $value -eq '2') {
            return $true
        } else {
            Write-Host "Invalid option: Please enter '1' or '2'." -ForegroundColor Red
            return $false
        }
    }

    if ($option -eq '1') {
        # Display table numbers for reference
        Write-Host "`nAvailable tables for transfer:" -ForegroundColor Yellow
        $ownershipTable | Format-Table -Property S_No, Database_Name, Schema_Name, Table_Name -AutoSize
       
        # Prompt for comma-separated numbers
        $validInput = $false
        while (-not $validInput) {
            Write-Host "Please enter the table numbers to transfer, separated by commas (e.g., 1, 2, 3):" -ForegroundColor Green
            $numberInput = Read-Host
            $selectedNumbers = $numberInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }

            if (-not $selectedNumbers) {
                Write-Host "No valid numbers provided. Please try again." -ForegroundColor Red
            }
            else {
                $validNumbers = $selectedNumbers | Where-Object {
                    $num = [int]$_
                    $exists = $ownershipTable | Where-Object { $_.S_No -eq $num }
                    if (-not $exists) {
                        Write-Host "Number $num does not correspond to any table." -ForegroundColor Red
                        return $false
                    }
                    return $true
                }
               
                if ($validNumbers.Count -eq $selectedNumbers.Count) {
                    $validInput = $true
                }
                else {
                    Write-Host "Please enter only valid table numbers from the list above." -ForegroundColor Red
                }
            }
        }

        $tableList = @()
        foreach ($num in $selectedNumbers) {
            $entry = $ownershipTable | Where-Object { $_.S_No -eq [int]$num }
            $tableList += [PSCustomObject]@{
                Database   = $entry.Database_Name
                SchemaName = $entry.Schema_Name
                Table      = $entry.Table_Name
            }
        }

        foreach ($entry in $tableList) {
            # Transfer ownership for specific table
            $alterQuery = "ALTER TABLE $($entry.SchemaName).$($entry.Table) OWNER TO $newOwner;"
            $result = Run-PsqlCommand -Command $alterQuery -PgHost $PgHost -Port $Port -Username $Username -Password $Password -Database $entry.Database
            if ($result -ne $false) {
                Write-Host "Ownership of '$($entry.Table)' in '$($entry.Database)' transferred from '$targetUser' to '$newOwner'." -ForegroundColor Green
            }
            else {
                Write-Host "Failed to transfer ownership of '$($entry.Table)' in '$($entry.Database)'." -ForegroundColor Red
            }
        }
    }
    elseif ($option -eq '2') {
        # Transfer all ownerships
        $successCount = 0
        $failCount = 0
       
        foreach ($entry in $ownershipTable) {
            $alterQuery = "ALTER TABLE $($entry.Schema_Name).$($entry.Table_Name) OWNER TO $newOwner;"
            $result = Run-PsqlCommand -Command $alterQuery -PgHost $PgHost -Port $Port -Username $Username -Password $Password -Database $entry.Database_Name
            if ($result -ne $false) {
                Write-Host "Ownership of '$($entry.Table_Name)' in '$($entry.Database_Name)' transferred from '$targetUser' to '$newOwner'." -ForegroundColor Green
                $successCount++
            }
            else {
                Write-Host "Failed to transfer ownership of '$($entry.Table_Name)' in '$($entry.Database_Name)'." -ForegroundColor Red
                $failCount++
            }
        }
       
        Write-Host "`nTransfer summary:" -ForegroundColor Cyan
        Write-Host "Successfully transferred: $successCount tables" -ForegroundColor Green
        if ($failCount -gt 0) {
            Write-Host "Failed to transfer: $failCount tables" -ForegroundColor Red
        }
    }
}
else {
    Write-Host "Operation cancelled." -ForegroundColor Yellow
}

Write-Host "`nThank you for using the PostgreSQL Ownership Transfer Tool!" -ForegroundColor Cyan