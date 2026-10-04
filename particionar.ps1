<#
.SYNOPSIS
    Particionador y formateador interactivo de tarjetas SD (FAT16, 64 KB) para OneChipMSX, OneChipBook y Nextor/MSX.

.DESCRIPTION
    =========================================================================================
    Particionador de tarjetas SD para OneChipMSX y OneChipBook.
    Creado por Josema el 04/10/2026.
    =========================================================================================
    Versión 0.1: Creación inicial del script.
    Versión 0.2: Control exhaustivo de errores, protección de discos de sistema/arranque,
                 interactividad en tamaños (32-4095 MB), valores por defecto [S/Enter] y
                 ajuste automático del espacio remanente respetando el límite de 4 particiones MBR.
    =========================================================================================

    Históricamente mucha gente tiene problemas para particionar y formatear en FAT16 con clústeres 
    de 64 KB tarjetas SD de más de 4 GB para el chinobuk (OneChipBook) y OCM. Windows no permite 
    hacerlo fácilmente desde la interfaz gráfica. Por ese motivo, y por comodidad mía, he creado 
    este script en PowerShell que automatiza todo el proceso de forma segura.

    El script debe ejecutarse como Administrador (requiere acceso a DiskPart y cmdlets de almacenamiento).

    Flujo y características:
    * Muestra los discos del sistema para elegir la unidad. Si seleccionas el disco de sistema o arranque, 
      te avisa en rojo y te permite volver a elegir sin cerrar el script.
    * Muestra la estructura de particiones actual del disco seleccionado (número, letra, etiqueta y tamaño).
    * Permite conservar las particiones existentes (lo habitual si ya cremos la partición de arranque con OCM-SDBIOS Pack).
    * Detecta el espacio libre utilizable real y permite definir interactivamente el tamaño de cada partición 
      (entre 32 MB y 4095 MB, sugiriendo el máximo posible por defecto al pulsar Enter).
    * Solicita una etiqueta para cada partición (saneada automáticamente a 11 caracteres y mayúsculas).
    * Aplica formato FAT16 con clústeres de 64 KB (unit=64k) y asigna letra de unidad al vuelo.
    * Respeta estrictamente el tope físico de 4 particiones primarias MBR y permite detenerse en cualquier momento.
    * Al finalizar, muestra una tabla resumen limpia con todas las particiones resultantes.

    Ejemplo de uso:
    En una tarjeta de 16 GB, tras crear la primera partición con el script new-sdcard.cmd del 
    OCM-SDBIOS Pack, este script permite añadir las 3 particiones restantes (por ejemplo, dos de 4095 MB 
    y la última aprovechando exactamente todo el espacio restante disponible).

.NOTES
    Sentíos libres de añadir, modificar o mejorar lo que consideréis. Es un script hecho por y para 
    la comunidad MSX. ¡Disfrutadlo!
#>

function Test-Admin {
    $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Error "Este script requiere permisos de Administrador. Ejecuta PowerShell como Administrador."
    exit
}

function Show-DiskStructure([int]$DiskNumber) {
    Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
        Sort-Object PartitionNumber |
        ForEach-Object {
            $vol = if ($_.DriveLetter) { Get-Volume -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue } else {$null }
            [PSCustomObject]@{
                PartitionNumber = $_.PartitionNumber
                DriveLetter     = if ($_.DriveLetter) {$_.DriveLetter } else { "-" }
                FileSystemLabel = if ($vol) {$vol.FileSystemLabel } else { "" }
                FileSystem      = if ($vol) {$vol.FileSystem } else { "" }
                "Size(MB)"      = [math]::Round($_.Size / 1MB, 0)
            }
        } | Format-Table -AutoSize
}

Clear-Host
Write-Host "=== PARTICIONADOR TARJETAS SD EN FAT16 (32 MB - 4095 MB) ===" -ForegroundColor Cyan
Write-Host ""

# 1. Bucle interactivo para la seleccion segura del disco
$targetDisk = $null
$dnum = 0

while ($true) {
    Write-Host "Discos detectados:" -ForegroundColor Gray
    Get-Disk | Select-Object Number, FriendlyName, OperationalStatus, BusType,
        @{N="Size(GB)";E={[math]::Round($_.Size / 1GB, 2)}}, PartitionStyle | Format-Table -AutoSize

    $diskInput = Read-Host "Introduce el NUMERO del disco a particionar (o 'Q' para salir)"
    if ($diskInput.Trim().ToUpper() -eq 'Q') {
        Write-Host "Operacion cancelada por el usuario." -ForegroundColor Gray
        exit
    }

    if (-not [int]::TryParse($diskInput.Trim(), [ref]$dnum)) {
        Write-Warning "Por favor, introduce un numero de disco valido.`n"
        continue
    }

    $targetDisk = Get-Disk -Number $dnum -ErrorAction SilentlyContinue
    if (-not $targetDisk) {
        Write-Warning "El Disco $dnum no existe.`n"
        continue
    }

    # Salvaguarda: Evitar modificar el disco de sistema
    if ($targetDisk.IsBoot -or$targetDisk.IsSystem) {
        Write-Host "`nPELIGRO: El Disco $dnum contiene el sistema operativo o el arranque de Windows." -ForegroundColor Red
        Write-Host "Por seguridad, no se puede seleccionar este disco. Elige otro.`n" -ForegroundColor Yellow
        continue
    }

    break
}

if ($targetDisk.PartitionStyle -ne 'MBR') {
    Write-Warning "`nEl disco $dnum esta inicializado como $($targetDisk.PartitionStyle). MSX/Nextor requiere MBR."
}

Write-Host "`nParticiones actuales en Disco ${dnum} ($($targetDisk.FriendlyName)):" -ForegroundColor Yellow
Show-DiskStructure -DiskNumber $dnum

# Validacion estricta S/N (Enter = S)
while ($true) {
    $confirm = Read-Host "`nDeseas continuar sin borrar las particiones existentes? (S/N) [Default: S]"
    $cleanConfirm =$confirm.Trim()

    if ([string]::IsNullOrWhiteSpace($cleanConfirm) -or $cleanConfirm -match '^[sSyY]$') {
        break
    } elseif ($cleanConfirm -match '^[nN]$') {
        Write-Host "Operacion cancelada." -ForegroundColor Gray
        exit
    } else {
        Write-Warning "Opcion no valida. Pulsa Enter o introduce 'S' para continuar, o 'N' para cancelar."
    }
}

# 2. Bucle principal de creacion interactiva
while ($true) {
    Update-Disk -Number $dnum -ErrorAction SilentlyContinue
    $diskInfo = Get-Disk -Number $dnum
    $existingParts = @(Get-Partition -DiskNumber $dnum -ErrorAction SilentlyContinue)
    $currentPartCount = $existingParts.Count

    if ($currentPartCount -ge 4) {
        Write-Warning "`nSe ha alcanzado el tope maximo de 4 particiones primarias en MBR."
        break
    }

    # Espacio contiguo utilizable real reportado por el sistema de almacenamiento
    $freeMB = [math]::Floor($diskInfo.LargestFreeExtent / 1MB)

    if ($freeMB -lt 32) {
        Write-Host "`nNo queda suficiente espacio libre sin asignar ($freeMB MB restantes, minimo requerido: 32 MB)." -ForegroundColor Gray
        break
    }

    $nextPartIndex = $currentPartCount + 1
    $maxAllowedMB = [math]::Min($freeMB, 4095)
    $minAllowedMB = 32

    Write-Host "`n------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "Espacio libre total disponible: $freeMB MB" -ForegroundColor Green
    Write-Host "Configurando Particion $nextPartIndex de 4" -ForegroundColor Yellow

    # Solicitar y validar tamano en MB
    $sizeMB = 0
    $defaultSize =$maxAllowedMB

    while ($true) {$sizeInput = Read-Host "Introduce tamano en MB [$minAllowedMB - $maxAllowedMB] [Default:$defaultSize]"
        if ([string]::IsNullOrWhiteSpace($sizeInput)) {
            $sizeMB =$defaultSize
            break
        }

        [int]$parsedSize = 0
        if ([int]::TryParse($sizeInput.Trim(), [ref]$parsedSize)) {
            if ($parsedSize -ge$minAllowedMB -and $parsedSize -le$maxAllowedMB) {
                $sizeMB =$parsedSize
                break
            } else {
                Write-Warning "El tamano debe estar comprendido entre $minAllowedMB MB y$maxAllowedMB MB."
            }
        } else {
            Write-Warning "Introduce un numero entero valido en megabytes."
        }
    }

    # Si se pide todo el espacio libre restante y no excede 4095 MB, dejamos que DiskPart tome el maximo exacto
    $sizeParam = ""
    if ($sizeMB -lt $freeMB -or$sizeMB -eq 4095) {
        $sizeParam = "size=$sizeMB"
    }

    # Solicitar y validar etiqueta
    $defaultLabel = "FAT16_$nextPartIndex"
    $rawLabel = Read-Host "Introduce etiqueta (max 11 caracteres) [Default: $defaultLabel]"
    if ([string]::IsNullOrWhiteSpace($rawLabel)) {
        $rawLabel =$defaultLabel
    }

    $cleanLabel = ($rawLabel.Trim().ToUpper() -replace '[^A-Z0-9_\-]', '')
    if ($cleanLabel.Length -gt 11) { $cleanLabel =$cleanLabel.Substring(0, 11) }
    if ([string]::IsNullOrWhiteSpace($cleanLabel)) { $cleanLabel =$defaultLabel }

    Write-Host "Creando particion ($sizeMB MB) y formateando en FAT16 (64 KB, etiqueta '$cleanLabel')..." -ForegroundColor Gray

    $dpScript = @"
select disk $dnum
create partition primary $sizeParam
format fs=fat unit=64k label="$cleanLabel" quick
assign
"@

    $dpResult =$dpScript | diskpart | Out-String

    if ($dpResult -match "satisfactoriamente|correctamente|successfully") {
        Write-Host "[OK] Particion $nextPartIndex creada y formateada con exito." -ForegroundColor Green
    } else {
        Write-Host $dpResult -ForegroundColor Red
        Write-Warning "Diskpart devolvio un error. Operacion detenida."
        break
    }

    # Si se creo la 4ª particion, no hay mas ranuras primarias
    if ($nextPartIndex -ge 4) {
        break
    }

    # Comprobar si vale la pena preguntar por otra particion
    Update-Disk -Number $dnum -ErrorAction SilentlyContinue
    $diskInfo = Get-Disk -Number $dnum
    $remainingAfter = [math]::Floor($diskInfo.LargestFreeExtent / 1MB)

    if ($remainingAfter -ge 32) {
        while ($true) {$continueOpt = Read-Host "`nDeseas crear otra particion con el espacio restante ($remainingAfter MB)? (S/N) [Default: S]"
            $cleanOpt =$continueOpt.Trim()

            if ([string]::IsNullOrWhiteSpace($cleanOpt) -or $cleanOpt -match '^[sSyY]$') {
                break
            } elseif ($cleanOpt -match '^[nN]$') {
                Write-Host "Creacion finalizada a peticion del usuario." -ForegroundColor Gray
                break
            } else {
                Write-Warning "Opcion no valida. Pulsa Enter o introduce 'S' para continuar, o 'N' para finalizar."
            }
        }
        if ($cleanOpt -match '^[nN]$') { break }
    } else {
        break
    }

    Start-Sleep -Seconds 1
}

# 3. Resumen final
Update-Disk -Number $dnum -ErrorAction SilentlyContinue
Write-Host "`n=== ESTRUCTURA FINAL DEL DISCO CONCLUIDA ===" -ForegroundColor Cyan
Show-DiskStructure -DiskNumber $dnum
Write-Host "Proceso finalizado." -ForegroundColor Green
