#!/bin/bash

# DETENER EL SCRIPT SI ALGO FALLA
set -e

# TITULO DEL SCRIPT
t1="======================================================"
t2="   SCRIPT DE INSTALACION ARCH LINUX INScript-v1.3.0"
t3="======================================================"

# INICIO DEL SCRIPT
clear
echo
echo $t1
echo "$t2"
echo $t3
echo

# DETECTAR Y SELECCIONAR DISCO DE INSTALACION
echo ">> DISCO DE INSTALACION"
echo
mapfile -t discos < <(lsblk -dpno NAME,TYPE | grep "disk" | awk '{print $1}')
echo "==> Seleccione el disco donde desea instalar:"
echo
for i in "${!discos[@]}"; do
    echo "  [$i] ${discos[$i]}"
done
echo
while true; do
    read -p "==> Ingrese el número correspondiente: " opcion
    if [[ "$opcion" =~ ^[0-9]+$ ]] && (( opcion >= 0 && opcion < ${#discos[@]} )); then
        break
    else
        echo "<< NO HA SELECCIONADO NINGUN DISCO, INTENTE DE NUEVO >>"
    fi
done
disco="${discos[$opcion]}"
clear

# FUNCION PARA ASIGNAR CONTRASEÑA
contra_segura() {
    local pass1 pass2
    while true; do
        read -sp "==> Ingrese contraseña para $1: " pass1
        echo
        read -sp "==> Repita la contraseña para $1: " pass2
        echo
        if [[ -z "$pass1" ]]; then
            echo "<< ERROR LA CONTRASEÑA NO PUEDE ESTAR VACIA >>"
        elif [[ "$pass1" != "$pass2" ]]; then
            echo "<< ERROR LA CONTRASEÑA NO COINCIDE >>"
        else
            printf -v "$2" '%s' "$pass1"
            break
        fi
    done
}

# CREAR NOMBRE DE HOST Y CONTRASEÑA DE ROOT
echo
echo $t1
echo "$t2"
echo $t3
echo
echo ">> NOMBRE DE HOST Y CONTRASEÑA DE ROOT"
echo
while true; do
    read -p "==> Ingrese el nombre de host: " HOST_NAME
    [[ -n "$HOST_NAME" ]] && break
    echo "<< ERROR EL NOMBRE DE HOST NO PUEDE ESTAR VACIO >>"
done
echo
contra_segura "ROOT" ROOT_PASS
clear

# CREAR NOMBRE DE USUARIO Y CONTRASEÑA
echo
echo $t1
echo "$t2"
echo $t3
echo
echo ">> NOMBRE DE USUARIO Y CONTRASEÑA"
echo
while true; do
    read -p "==> Ingrese el nombre de usuario: " USER_NAME
    [[ -n "$USER_NAME" ]] && break
    echo "<< ERROR EL NOMBRE DE USUARIO NO PUEDE ESTAR VACIO >>"
done
echo
contra_segura "usuario $USER_NAME" USER_PASS
clear

# CONFIRMAR INSTALACION CONTROLADORES GRAFICOS AMD
echo
echo $t1
echo "$t2"
echo $t3
echo
echo ">> INSTALAR CONTROLADORES GRAFICOS PARA AMD"
echo
echo "==> ¿Desea instalar controladores graficos para AMD?"
echo
echo "  [1] Sí"
echo "  [2] No"
echo
read -p "==> Elija su opción: " opcion2
clear

# MOSTRAR RESUMEN Y CONFIRMAR
while true; do
    echo
    echo $t1
    echo "$t2"
    echo $t3
    echo
    echo ">> INFORMACIÓN INGRESADA"
    echo
    echo "-> Disco seleccionado:"
    echo "   $disco"
    echo
    echo "-> Nombre de host:"
    echo "   $HOST_NAME"
    echo
    echo "-> Usuario:"
    echo "   $USER_NAME"
    echo
    echo "-> Instalar controladores AMD:"
    if [[ "$opcion2" == "1" ]]; then
        echo "   Sí"
    else
        echo "   No"
    fi
    echo
    echo "=============================================="
    echo
    echo "==> ¿Es correcta esta información?"
    echo
    echo "   [1] Sí, continuar con la instalación"
    echo "   [2] No, volver a ingresar datos"
    echo
    read -p "==> Seleccione una opción: " confirm
    case "$confirm" in
        1)
            break
            ;;
        2)
            exec "$0"
            ;;
        *)
            clear
            ;;
    esac
done
clear

# FORMATEAR Y CREAR LAS NUEVAS PARTICIONES
echo
echo
echo
wipefs -a $disco
parted -s -a optimal $disco mklabel gpt
parted -s -a optimal $disco mkpart ESP fat32 1MiB 2049MiB
parted -s -a optimal $disco set 1 esp on
parted -s -a optimal $disco mkpart btrfs 2049MiB 100%

# COMPROBAR DISCO NVME
if [[ "$disco" == *"nvme"* ]]; then
    part1="${disco}p1"
    part2="${disco}p2"
else
    part1="${disco}1"
    part2="${disco}2"
fi

# DAR FORMATO A LAS NUEVAS PARTICIONES
mkfs.fat -F32 $part1
mkfs.btrfs -f $part2

# CREAR SUBVOLUMENES DE BTRFS
mount $part2 /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@cache
btrfs subvolume create /mnt/@snapshots
umount /mnt

# MONATAR LAS PARTICIONES Y SUBVOLUMENES
mount -o noatime,compress=zstd:1,space_cache=v2,ssd,subvol=@ $part2 /mnt
mkdir -p /mnt/{boot,home,var/log,var/cache,.snapshots}
mount $part1 /mnt/boot
mount -o noatime,compress=zstd:1,space_cache=v2,ssd,subvol=@home $part2 /mnt/home
mount -o noatime,compress=zstd:1,space_cache=v2,ssd,subvol=@log $part2 /mnt/var/log
mount -o noatime,compress=zstd:1,space_cache=v2,ssd,subvol=@cache $part2 /mnt/var/cache
mount -o noatime,compress=zstd:1,space_cache=v2,ssd,subvol=@snapshots $part2 /mnt/.snapshots
echo
echo
echo

# ACTUALIZAR CLAVES
pacman-key --init
pacman-key --populate archlinux
pacman -Syy

# INSTALAR SISTEMA BASE 
while true; do
    if pacstrap -K /mnt base linux linux-firmware networkmanager intel-ucode sudo btrfs-progs; then
        echo
        echo "<< PAQUETES INSTALADOS CORRECTAMENTE >>"
        break
    else
        echo
        echo
        echo "<< ERROR AL INSTALAR LOS PAQUETES >>"
        echo
        echo
        read -p "==> ¿Quieres reintentar la instalación? (s/n): " respuesta1
        if [[ "$respuesta1" != "s" ]]; then
            echo
            echo
            echo "<< INSTALACION CANCELADA >>"
            echo
            echo
            exit 1
        fi
    fi
done

# GENERAR ARCHIVO FSTAB
genfstab -U /mnt >> /mnt/etc/fstab

export ROOT_PASS USER_PASS USER_NAME HOST_NAME disco part1 part2 opcion2

# CREAR SCRIPT PARA LA POST INSTALACION
cat > /mnt/PostInScript.sh << 'END'
#!/bin/bash

# VARIABLES DE PREFERENCIAS
ROOT_PASS="$ROOT_PASS"
USER_PASS="$USER_PASS"
USER_NAME="$USER_NAME"
HOST_NAME="$HOST_NAME"
disco="$disco"
part1="$part1"
part2="$part2"
opcion2="$opcion2"

# CONFIGURAR ZONA HORARIA
ln -sf /usr/share/zoneinfo/America/Bogota /etc/localtime
hwclock --systohc

# CAMBIAR IDIOMA DEL SISTEMA Y TECLADO
echo
echo
echo
pacman -Syu terminus-font --noconfirm
sed -i "s/^#es_CO.UTF-8/es_CO.UTF-8/" /etc/locale.gen
locale-gen
echo "LANG=es_CO.UTF-8" > /etc/locale.conf
echo -e "KEYMAP=es\nFONT=ter-132n" > /etc/vconsole.conf

# CREAR NOMBRE Y CONTRASEÑA DEL SISTEMA
echo "$HOST_NAME" > /etc/hostname
echo "127.0.1.1        $HOST_NAME.localdomain  $HOST_NAME" >> /etc/hosts
echo "root:$ROOT_PASS" | chpasswd

# CREAR NOMBRE Y CONTRASEÑA DE USUARIO
useradd -m -G wheel -s /bin/bash "$USER_NAME"
echo "$USER_NAME:$USER_PASS" | chpasswd

# HABILITAR SUDO
sed -i "s/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/" /etc/sudoers

# HABILITAR SERVICIO DE INTERNET
echo
echo
echo
systemctl enable NetworkManager 

# INSTALAR Y CONFIGURAR FIREWALL
echo
echo
echo
pacman -Syu ufw --noconfirm 
ufw default deny incoming
ufw default allow outgoing
systemctl enable ufw.service

# HABILITAR TRIM PARA MEJORA DE RENDIMIENTO
echo
echo
echo
systemctl enable fstrim.timer

# CREAR MEMORIA SWAP
echo
echo
echo
pacman -S zram-generator --noconfirm
cat > /etc/systemd/zram-generator.conf << 'DOC'
[zram0]
zram-size = ram / 2
compression-algorithm = zstd
DOC

# INSTALAR Y CONFIGURAR EL BOOTLOADER
echo
echo
echo
pacman -S limine efibootmgr --noconfirm
mkdir -p /boot/EFI/limine
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/limine/
efibootmgr \
  --create \
  --disk $disco \
  --part 1 \
  --label "Arch Linux (Limine)" \
  --loader '\EFI\limine\BOOTX64.EFI' \
  --unicode
UUID=$(blkid -s UUID -o value $part2)
cat > /boot/EFI/limine/limine.conf <<CFG
timeout: 7

interface_branding: ${HOST_NAME} menu
interface_branding_color: 2

term_background: 1c1c1f
term_background_bright: 2e2e32
backdrop: 1c1c1f

term_palette: 241f31;c01c28;2ec27e;f5c211;1e78e4;9841bb;0ab9dc;c0bfbc
term_palette_bright: 5e5c64;ed333b;57e389;f8e45c;51a1ff;c061cb;4fd2fd;f6f5f4

term_foreground: f6f5f4
term_foreground_bright: f6f5f4

/Arch Linux
  protocol: linux
  path: boot():/vmlinuz-linux
  module_path: boot():/initramfs-linux.img
  cmdline: quiet root=UUID=${UUID} rw rootflags=subvol=@
CFG

# CONFIGURAR PACMAN 
sed -i "s/^#Color/Color\nILoveCandy/" /etc/pacman.conf
sed -i "s/^ParallelDownloads = 5/ParallelDownloads = 10/" /etc/pacman.conf
sed -i '/#\[multilib\]/ { s/#\[multilib\]/[multilib]/; n; s/#Include = /Include = /; }' /etc/pacman.conf

# INSTALAR CONTROLADORES GRAFICOS AMD
echo
echo
echo
if [[ "$opcion2" == "1" ]]; then
    while true; do
        if pacman -Syu --noconfirm mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon xf86-video-amdgpu; then
            break
        else
            echo
            echo
            echo "<< ERROR AL INSTALAR >>"
            echo
            echo
            read -p "==> ¿Quieres reintentar la instalación? (s/n): " respuesta2
            if [[ "$respuesta2" != "s" ]]; then
                echo
                echo
                echo "<< SE OMITIO LA INSTALACION DE CONTROLADORES >>"
                break
            fi
        fi
    done
else
    echo
fi

# AL FINALIZAR ELIMINAR ESTE SCRIPT
rm /PostInScript.sh
END

# DAR PERMISO DE EJECUCION AL SCRIPT DE POST INSTALACION
chmod +x /mnt/PostInScript.sh

# ABRIR CHROOT Y EJECUTAR EL SCRIPT DE POST INSTALACION
env ROOT_PASS="$ROOT_PASS" USER_PASS="$USER_PASS" USER_NAME="$USER_NAME" HOST_NAME="$HOST_NAME" disco="$disco" part1="$part1" part2="$part2" opcion2="$opcion2" arch-chroot /mnt /PostInScript.sh

# DESMONTAR AL FINALIZAR LA INSTALACION 
umount -R /mnt

# FINAL 
echo
echo
echo
echo "========================="
echo "   INSTALACION EXITOSA"
echo "========================="
echo

# REINICIAR
echo "==> ¿Desea reiniciar ahora?"
echo
echo "  [1] Sí, reiniciar ahora"
echo "  [2] No, salir sin reiniciar"
echo
while true; do
    read -p "==> Elija su opción: " opcion3
    case "$opcion3" in
        1)
            clear
            reboot
            ;;
        2)
            echo
            echo "<< INSTALACION FINALIZADA, PUEDE REINICIAR MANUALMENTE >>"
            echo
            echo
            exit 0
            ;;
        *)
            echo
            echo "<< OPCION INVALIDA, INTENTE NUEVAMENTE >>"
            echo
            ;;
    esac
done

# SCRIPT BY BRYAN-DEV
