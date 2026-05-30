#!/bin/bash

# --- 1. KONFIGURACJA ---
clear
echo "=== ARCH DUAL-BOOT INSTALLER (Używa istniejącego EFI + Wolne Miejsce) ==="
echo "------------------------------------------------------------------------"

# Wyświetlamy wszystkie partycje, żeby łatwo było znaleźć EFI i Root
lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINTS
echo "------------------------------------------------------------------------"

read -p "Wpisz nazwę partycji pod SYSTEM (np. sda3 lub nvme0n1p3): " PART_ROOT
read -p "Wpisz nazwę istniejącej partycji EFI/BOOT (np. sda1 lub nvme0n1p1): " PART_BOOT

DRIVE_ROOT="/dev/$PART_ROOT"
DRIVE_BOOT="/dev/$PART_BOOT"

read -p "Podaj nazwę komputera (Hostname): " MY_HOSTNAME

echo -e "\nWybierz GPU:\n1) NVIDIA\n2) AMD\n3) Brak"
read -p "Wybór: " GPU_CHOICE

# Automatyczne wykrywanie CPU dla Microcode
CPU_UCODE=""
if grep -q "GenuineIntel" /proc/cpuinfo; then CPU_UCODE="intel-ucode"; fi
if grep -q "AuthenticAMD" /proc/cpuinfo; then CPU_UCODE="amd-ucode"; fi

echo -e "\nUWAGA: Sformatuję tylko partycję systemową $DRIVE_ROOT."
echo "Istniejąca partycja EFI $DRIVE_BOOT ZOSTANIE ZACHOWANA (dodamy tylko pliki GRUB-a)."
read -p "Kontynuować? (y/N): " CONFIRM
[[ $CONFIRM != "y" ]] && exit 1

# --- 2. PRZYGOTOWANIE ---
loadkeys pl
timedatectl set-ntp true

# --- 3. FORMATOWANIE I MONTOWANIE (Bez ruszania tablicy partycji) ---
mkfs.ext4 -F $DRIVE_ROOT
mount $DRIVE_ROOT /mnt

mkdir -p /mnt/boot/efi
mount $DRIVE_BOOT /mnt/boot/efi

# --- 4. INSTALACJA PAKIETÓW ---
PKGS="base linux linux-firmware $CPU_UCODE sof-firmware sudo base-devel grub efibootmgr nano networkmanager zram-generator os-prober pacman-contrib git ntfs-3g exfatprogs dosfstools tlp power-profiles-daemon acpi acpi_call"

if [ "$GPU_CHOICE" == "1" ]; then PKGS="$PKGS nvidia nvidia-utils nvidia-settings"; fi
if [ "$GPU_CHOICE" == "2" ]; then PKGS="$PKGS mesa lib32-mesa xf86-video-amdgpu"; fi

pacstrap /mnt $PKGS
genfstab -U /mnt >> /mnt/etc/fstab

# --- 5. CHROOT ---
# Użycie "EOF" w cudzysłowie blokuje błędy składni i bezpiecznie przekazuje zmienne
arch-chroot /mnt /bin/bash <<"EOF"
ln -sf /usr/share/zoneinfo/Europe/Warsaw /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "pl_PL.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=pl" > /etc/vconsole.conf

# Odczytanie hostname, które zostało przekazane jako czysty tekst
echo "$MY_HOSTNAME" > /etc/hostname
echo "root:1234" | chpasswd

# zRAM
echo -e "[zram0]\nzram-size = ram / 2\ncompression-algorithm = zstd" > /etc/systemd/zram-generator.conf

# Włączenie wykrywania innych systemów (np. Windows) w GRUB
echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub

# Instalacja GRUB-a obok istniejącego bootloadera w osobnym folderze
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Arch-Linux --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# --- 6. AUR (YAY & PARU) ---
useradd -m -G wheel builder
echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
sudo -u builder bash <<"AUR"
cd /home/builder
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin && makepkg -si --noconfirm
cd ..
git clone https://aur.archlinux.org/paru-bin.git
cd paru-bin && makepkg -si --noconfirm
AUR
userdel -r builder
sed -i '/builder/d' /etc/sudoers

# Usługi
systemctl enable NetworkManager
systemctl enable tlp
EOF

umount -R /mnt
clear
echo "========================================================================"
echo "Gotowe! Arch został pomyślnie zainstalowany obok Twojego systemu."
echo "Przy restarcie komputera sprawdź menu GRUB i wybierz system."
echo "========================================================================"
