<# Set destination, source, secondary, source database, destination AG, and Azure Storage credential variables #>
$dest = "fbgquadag-vm2";
$source = "fbgquadag-vm1";
$secondary = "fbgquadag-vm3";
$sourcedb = "WideWorldImporters";
$destag = "fbgquadag-ag";
$azurecred = "https://fbgquagagsa.blob.core.windows.net/backups"

<# Set to 0 to run, 1 to display variable values #>
$debug = 1;

<# Get a list of databases on the destination instance #>
$databases = (Get-DbaAgDatabase -SqlInstance $dest -AvailabilityGroup $destag).Name;


if($debug -eq 1)
{
    Write-Output "Source replica: $source";
    Write-Output "Dest replica: $dest";
    Write-Output "Secondary: $secondary";
}

try {
    
    <# Get the backup history for the WideWorldImporters database #>
    $backup = Get-DbaDbBackupHistory -SqlInstance $source -Database $sourcedb -DeviceType URL -LastFull;

    <# Get the backup file name
        Note: The Path property is an array which is why the subscript is there #>
    $backupfile = $backup.Path[0];
    <# Loop through each destination database #>
    foreach($database in $databases)
    {
        if(!$backupfile)
        {
            throw "Backup file for $database is null"; 
        }

        <# Because we are restoring the same backup file to three different databases, the physical files have to be unique 
           This is accomplished by parsin a suffix from the destination database name and pssing it as the -DestinationFileSuffix parameter to the Restore-DbaDatabase command #>
        $us = $database.IndexOf('_');
        $len = $database.Length;
        $strend = $len - $us;
        $suffix = $database.Substring($us,$strend)

        if($debug -eq 0)
        {
            <# Remove the database from the availability group #>
            Write-Output "Removing $database from $destag on $dest";
            Remove-DbaAgDatabase -SqlInstance $dest -Database $database -AvailabilityGroup $destag -Confirm:$false;
            <# Remove the database from the secondary instances #>
            Write-Output "Dropping $database on $secondary";
            Remove-DbaDatabase -SqlInstance $secondary -Database $database -Confirm:$false;
            <# Restore the database to the primary replica using the destination defaults for file paths #>
            Write-Output "Restoring $database to $dest from $backupfile";
            Restore-DbaDatabase -SqlInstance $dest -Path $backupfile -DatabaseName $database -DestinationFileSuffix $suffix -UseDestinationDefaultDirectories -WithReplace;
            <# Add the database back to the availability group #>
            Write-Output "Adding $database to $destag on $dest";
            Add-DbaAgDatabase -SqlInstance $dest -AvailabilityGroup $destag -Database $database -SeedingMode Automatic -Confirm:$false;
        }
        $now = Get-Date -Format yyyyMMdd_HHmmss;
        "Restored $database at $now" | Out-File -FilePath C:\temp\CloneJobOutput.txt -Append;
    }
}
catch
{
    Write-Output "Something threw an exception or used Write-Error";
    Write-Output $_ -ErrorAction Stop;
}


