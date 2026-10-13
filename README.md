# MSX-cosas
Scripts y movidas varias para MSX

---
Particionador de tarjetas SD para OneChipMSX y OneChipBook.
---
Históricamente mucha gente tiene problemas para particionar y formatear en FAT16 con clústeres de 64 KB tarjetas SD de más de 4 GB para el OneChipMSX y el OneChipBook. Windows no permite hacerlo desde la interfaz gráfica, teniendo que hacerlo con los comandos esotéricos de diskpart. Por ese motivo (y por comodidad mía, que narices) he creado este script en PowerShell que automatiza todo el proceso de forma segura.

IMPORTANTE: El script debe ejecutarse con usuario *Administrador*.

Flujo y características:
* Muestra los discos del sistema para elegir la unidad. Si seleccionas un disco de sistema o arranque, te avisa en rojo y te permite volver a elegir sin cerrar el script.
* Muestra la estructura de particiones actual del disco seleccionado (número, letra, etiqueta y tamaño).
* Permite conservar las particiones existentes (lo habitual si ya creamos anteriormente la partición de arranque con OCM-SDBIOS Pack).
* Detecta el espacio libre utilizable real y permite definir interactivamente el tamaño de cada partición (entre 32 MB y 4095 MB, sugiriendo el máximo posible por defecto al pulsar Enter).
* Solicita una etiqueta para cada partición (saneada automáticamente a 11 caracteres y mayúsculas).
* Aplica formato FAT16 con clústeres de 64 KB y asigna una letra de unidad al vuelo por si quieres copiar cosillas en la SD antes de conectarla a tu OCM.
* Respeta estrictamente el tope físico de 4 particiones primarias MBR y permite detenerse en cualquier momento.
* Al finalizar, muestra una tabla resumen limpia con todas las particiones resultantes.

Ejemplo de uso:
En una tarjeta de 16 GB con una partición ya creada con el script new-sdcard.cmd del OCM-SDBIOS Pack, este script permite crear un máximo de 3 particiones adicionales (en este caso dos de 4095 MB y la última de 2000 y pico MB aprovechando exactamente todo el espacio restante disponible).

Sentíos libres de añadir, modificar o mejorar lo que consideréis. Es un script hecho por y para la comunidad MSX. ¡Disfrutadlo!
---
