<#
=========================================================================================
Particionador tarjetas SD para OneChipMSX y OneChipBook.
Creado por Josema el 04/10/2026.
=========================================================================================
Versión 0.1. Creación del script.
=========================================================================================

Históricamente mucha gente tiene problemas para particionar y formatear una tarjeta SD de más de 4GB para el chinobuk, por ese motivo y por comodidad mía, he hecho un script en powershell que soluciona todo eso en Windows 11. 

El script hay que ejecutarlo como administrador, ya que accede a la herramienta diskpart.

* Muestra los discos que hay en el sistema para que elijamos donde se crearán las particiones.
* Muestra el estado inicial de las particiones en la tarjeta SD.
* Detecta el espacio libre y, si hay suficiente, pregunta el nombre de la partición a crear.
* Crea una partición de 4095MB, vuelve a detectar el espacio libre y sigue haciendo esto hasta que no quede espacio en la tarjeta.
* Muestra el estado final de las particiones en la tarjeta SD.

En mi caso, en una tarjeta de 16GB, creé una partición con el script new-sdcard.cmd del OCM-SDBIOS Pack, después el script me creó 2 particiones de 4095MB y una con el resto que quedaba en la tarjeta.

Cada vez que va a crear una partición, pregunta si queremos etiquetarla (si no, le pone una etiqueta por defecto). Solo lo he probado con mi tarjeta de 16GB, en teoría, si es de más, puede que el script pete porque solo se permiten 4 particiones primarias... si me hago con una tarjeta más grande lo probaré e intentaré arreglar eso.

Sentíos libres de añadir/modificar/mejorar lo que sea del script. Es la primera versión y, aunque a mi me funciona, fijo que tiene algún fallo.

¡Disfrutadlo!

#>


ufunction Check-Admin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Check-Admin)) {
    Write-Error "Executa PowerShell como Administrador."
    exit
}

Clear-Host
Write-Host "=== GESTOR DE PARTICIONES FAT-16 (4095 MB + RESTO) ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "Discos detectados:" -Foreground Gray
$fl = Get-Disk
$fl | Select-Object Number, FriendlyName, OperationalStatus, @{N="Size(GB)";E={[math]::Round($_.Size/1GB,2)}} | Format-Table -AutoSize

$diskInput = Read-Host "Introduce el NUMERO del disco a particionar"
[int]$dnum = 0
if (-not [int]::TryParse($diskInput.Trim(), [ref]$dnum)) {
    Write-Error "Numero no valido."
    exit
}

$disk = $fl | Where-Object { $_.Number -eq $dnum }
if (-not $disk) {
    Write-Error "Disco no encontrado."
    exit
}

Write-Host "Particiones actuales en Disco $dnum :" -ForegroundColor Yellow
Get-Partition -DiskNumber $dnum | Sort-Object PartitionNumber | ForEach-Object {
    $vol = if ($_.DriveLetter) { Get-Volume -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue } else { $null }
    [PSCustomObject]@{
        PartitionNumber = $_.PartitionNumber
        DriveLetter     = if ($_.DriveLetter) { $_.DriveLetter } else { "-" }
        FileSystemLabel = if ($vol) { $vol.FileSystemLabel } else { "" }
        FileSystem      = if ($vol) { $vol.FileSystem } else { "" }
        "Size(MB)"      = [math]::Round($_.Size / 1MB, 0)
    }
} | Format-Table -AutoSize

$confirm = Read-Host "¿Deseas continuar sin borrar las particiones existentes? (S/N)"
if ($confirm -notmatch '^[sSyy]') {
    Write-Host "Operacion cancelada." -Foreground Gray
    exit
}

$count = 1

for (;;) {
    $parts = Get-Partition -DiskNumber $dnum
    if ($parts.Count -ge 4) {
        Write-Warning "Se ha alcanzado el limite maximo de 4 particiones nb primarias en MBR."
        break
    }

    $dinfo = Get-Disk | Where-Object { $_.Number -eq $dnum }
    $freeMB = [math]::Floor($dinfo.LargestFreeExtent / 1MB)
    if ($freeMB -lt 16) {
        Write-Host "No queda espacio libre suficiente en el disco ($freeMB MB detectados)." -Foreground Gray
        break
    }

    Write-Host "-----------------------------------------------------" -Foreground Cyan
    $partscount = $parts.Count + 1
    Write-Host "Espacio libre detectado: $freeMB MB [Particion $partscount/4]" -Foreground Green

    $isFull = $freeMB -ge 4095
    if ($isFull) {
        $sizePar = "size=4095"
        $defLabel = "FAT16_" + $count
        $msgLab = "Introduce etiqueta para particion de 4095 MB [Default: $defLabel]"
    } else {
        $sizePar = ""
        $defLabel = "FAT16_RE"
        $msgLab = "Introduce etiqueta particion final de $freeMB MB [Default: $defLabel]"
    }

    $labIn = Read-Host $msgLab
    if ([string]::IsNullOrWhiteSpace($labIn)) { $labIn = $defLabel }
    $labIn = $labIn.Trim().ToUpper()
    if ($labIn.Length -gt 11) { $labIn = $labIn.Substring(0, 11) }

    Write-Host "Creando y formateando en FAT16 con etiqueta $labIn ..." -Foreground Yellow

    $cmds = @"
select disk $dnum
create partition primary $sizePar
format fs=fat unit=64k label="$labIn" quick
assign
"@

    $res = $cmds | diskpart | Out-String
    if ($res -match "satisfactoriamente" -or $res -match "correctamente" -or $res -match "successfully") {
        Write-Host "[OK] Particion creada, formateada y etiquetada como $labIn." -Foreground Green
    } else {
        Write-Host $res -Foreground Red
        Write-Warning "Hubo un error al ejecutar Diskpart."
        break
    }

    if (-not $isFull) { break }
    $count++
    Start-Sleep -Seconds 1
}

Write-Host "=== ESTRUCTURA FINAL DEL DISCO CONCLUIDA ===" -ForegroundColor Cyan
Get-Partition -DiskNumber $dnum | Sort-Object PartitionNumber | ForEach-Object {
    $vol = if ($_.DriveLetter) { Get-Volume -DriveLetter $_.DriveLetter -ErrorAction SilentlyContinue } else { $null }
    [PSCustomObject]@{
        PartitionNumber = $_.PartitionNumber
        DriveLetter     = if ($_.DriveLetter) { $_.DriveLetter } else { "-" }
        FileSystemLabel = if ($vol) { $vol.FileSystemLabel } else { "" }
        FileSystem      = if ($vol) { $vol.FileSystem } else { "" }
        "Size(MB)"      = [math]::Round($_.Size / 1MB, 0)
    }
} | Format-Table -AutoSize

Write-Host "Proceso finalizado." -ForegroundColor Green
