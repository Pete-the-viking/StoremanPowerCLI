#======================================================================#

# 
# 
# IBM Tivoli Storage Manager for Mail 
# 
# 
# 
# Data Protection for Microsoft Exchange Server 
# 
# 
# 
# Script for backing up a DAG node - backupdag.ps1 
# 
# 
# 
# 1. Check if server is a member of a DAG 
# 
# 2. Get list of databases on server and thier replication staus 
# 
# 3. Backup database if it meets one of the following: 
# 
# - Local Healthy passive database copy 
# 
# - Local Active copy where a healthy passive copy does not exist 
# 
# - Local Non replicated/recovery databases 
# 
# 
# 
# Usage: 
# 
# PowerShell backupdag.ps1 <log file path> 
# 
# 
# 
# Version: 1.0 
# 
# 
# 
#======================================================================#

# --- get server name --- 
$server = hostname 
$server = $server.ToUpper() 
$isDAG = $false 
$logFile = ".backup.log"

# --- write log entry --- 
function WriteOut 
{ 
param($msg, $log) 
Write-Output((get-date -format 'yyyy-MM-dd hh:mm:ss') +" - " + 
$msg) 
Write-Output((get-date -format 'yyyy-MM-dd hh:mm:ss') +" - " + 
$msg) | 
out-file -encoding ASCII -filepath "$log" -append:$true 
}

# --- check parameters --- 
if ($args) 
{ 
$logFile = "$args" 
}

WriteOut ("Server: " + $server) $logFile

# --- is DP for Exchange installed? --- 
$versionInfo = Get-ItemProperty HKLM:SOFTWAREIBMADSM 
CurrentVersion 
if (!$?) 
{ 
WriteOut "DP for Exchange is not installed." $logFile 
exit 1 
}

# --- build full path to comand line --- 
$commandLine = $versionInfo.TSMExchangePath + "TDPExchange 
tdpexcc.exe"

# --- is this server a member of the DAG ? --- 
$members = Get-DatabaseAvailabilityGroup 
if ( $members ) 
{ 
# --- look for server in DAG members --- 
foreach ( $member in $members.servers ) 
{ 
if ( $member.Name.ToUpper().Contains($server) ) 
{ 
$isDAG = $true 
break 
} 
} 
}

if ( $isDAG ) 
{ 
# --- get mailbox databases for server --- 
$databases = Get-MailboxDatabase -server $server -Status 
if ( $databases ) 
{

WriteOut "Building database backup list..." $logFile 
# --- initialize database backup list ---- 
$backupList = ""

# --- get replication type and copy status for each database 
--- 
foreach( $database in $databases ) 
{ 
# --- setup state variables --- 
$healthyCopyExists = $false 
$localActiveCopy = $false

# --- type "Remote" indicates remote replicated copy --- 
$type = $database.ReplicationType.ToString() 
if ( $type.CompareTo("Remote") -eq 0 ) 
{ 
# --- get copy status for each database --- 
$statuses = Get-MailboxDatabaseCopyStatus $database.Name 
if ( $statuses ) 
{ 
foreach( $status in $statuses ) 
{ 
# --- look if a healthy copy exists --- 
if ( $status.Status.ToString().CompareTo("Healthy") 
-eq 0 ) 
{ 
$healthyCopyExists = $true

if ( $status.Name.Contains( $server ) ) 
{ 
WriteOut ("==> Backing Up Healthy Passive 
Database Copy '$database'") $logFile 
$backupList += ('"' + $database + '"' + ',') 
} 
} 
elseif ( $status.Status.ToString().CompareTo 
("Mounted") -eq 0 ) 
{ 
# --- check for local active database copy --- 
if ( $status.Name.Contains( $server ) ) 
{ 
$localActiveCopy = $true 
} 
} 
}

# --- if a healthy copy does not exist, backup local 
active --- 
if ( (! $healthyCopyExists) -and ($localActiveCopy) ) 
{ 
WriteOut ("==> Backing Up Active Database (No 
Healthy Copies Found) '$database'") $logFile 
$backupList += ('"' + $database + '"' + ',') 
} 
} 
} 
else # --- non replicated local database --- 
{ 
# --- skip local recovery databases --- 
if ( ! $database.Recovery -and $database.Mounted ) 
{ 
WriteOut ("==> Backing Up Non Replicated Database 
'$database'") $logFile 
$backupList += ('"' + $database + '"' + ',') 
} 
else 
{ 
if ( $database.Recovery ) 
{ 
WriteOut "==> Skipping Recovery Database 
'$database'" $logFile 
} 
else 
{ 
WriteOut "==> Skipping Dismounted Non Replicated 
Database '$database'" $logFile 
} 
} 
} 
}

if ( $backupList ) 
{ 
WriteOut("Executing command: '" + $commandLine + "' BACKUP 
'" + $backupList + "' FULL /BACKUPMETHOD=VSS /BACKUPDESTINATION=TSM") 
$logFile 
& "$commandLine" BACKUP "$backupList" 
FULL /BACKUPMETHOD=VSS /BACKUPDESTINATION=TSM 
WriteOut "Backup completed." $logFile 
} 
else 
{ 
WriteOut ("BACKUP LIST EMPTY" ) $logFile 
} 
} 
} 
else 
{ 
WriteOut "This Server is NOT a member of a DAG" $logFile 
exit 1 
}

exit 0
