<#
.SYNOPSIS
=========================================================================================
Particionador tarjetas SD para OneChipMSX y OneChipBook.
Creado por Josema el 04/10/2026.
=========================================================================================
Versión 0.1. Creación del script.
Versión 0.2. Se implementa control de errores, protección para no formatear algo que sea del sistema y valores por defecto.
=========================================================================================

Históricamente mucha gente tiene problemas para particionar y formatear una tarjeta SD de más de 4GB para el chinobuk, por ese motivo y por comodidad mía, he hecho un script en powershell que soluciona todo eso en Windows 11. 

El script hay que ejecutarlo como administrador, ya que accede a la herramienta diskpart.

* Muestra los discos que hay en el sistema para que elijamos donde se crearán las particiones. Si seleccionamos un disco que sea del sistema, muestra un mensaje y no hace nada.
* Cuando seleccionamos un disco válido, muestra el estado inicial de las particiones del mismo.
* Detecta el espacio libre y, si hay suficiente, pregunta el tamaño de la partición (entre 32MB y 4095MB) y después pregunta el  nombre de la partición a crear.
* Crea una partición de 4095MB, vuelve a detectar el espacio libre y sigue haciendo esto hasta que no quede espacio en la tarjeta o haya un total de 4 particiones primarias.
* Muestra el estado final de las particiones en la tarjeta SD.

En mi caso, en una tarjeta de 16GB, creé una partición con el script new-sdcard.cmd del OCM-SDBIOS Pack, después el script me creó 2 particiones de 4095MB y una con el resto que quedaba en la tarjeta.

Sentíos libres de añadir/modificar/mejorar lo que sea del script. Es la primera versión y, aunque a mi me funciona, fijo que tiene algún fallo.

¡Disfrutadlo!

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
