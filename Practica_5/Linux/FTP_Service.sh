#!/bin/bash

CONF="/etc/vsftpd.conf"
BASE="/srv/ftp"
export PATH=$PATH:/usr/sbin:/sbin:/usr/bin:/bin

Configurar_Servicio(){
    echo "[+] Automatizando configuración de vsftpd..."
    
    set_conf() {
        local key="$1"
        local value="$2"
        if grep -q "^$key=" "$CONF"; then
            sed -i "s/^$key=.*/$key=$value/" "$CONF"
        elif grep -q "^#$key=" "$CONF"; then
            sed -i "s/^#$key=.*/$key=$value/" "$CONF"
        else
            echo "$key=$value" >> "$CONF"
        fi
    }

    set_conf "anonymous_enable"        "YES"
    set_conf "local_enable"            "YES"
    set_conf "write_enable"            "YES"
    set_conf "anon_upload_enable"      "NO"
    set_conf "anon_mkdir_write_enable" "NO"   
    set_conf "anon_other_write_enable" "NO"   
    set_conf "chroot_local_user"       "YES"
    set_conf "allow_writeable_chroot"  "YES"  
    set_conf "listen"                  "YES"
    set_conf "listen_ipv6"             "NO"
    set_conf "pam_service_name"        "vsftpd"
    set_conf "userlist_enable"         "NO"
    set_conf "tcp_wrappers"            "YES"

    grep -q "anon_root"         "$CONF" || echo "anon_root=$BASE/general"                    >> "$CONF"
    grep -q "pasv_min_port"     "$CONF" || echo -e "pasv_min_port=40000\npasv_max_port=40100" >> "$CONF"
    grep -q "secure_chroot_dir" "$CONF" || echo "secure_chroot_dir=/var/run/vsftpd/empty"    >> "$CONF"

    systemctl restart vsftpd
    echo "[OK] vsftpd.conf configurado y servicio reiniciado."
}

Setup_Entorno(){
    echo "[+] Preparando directorios en $BASE..."
    mkdir -p $BASE/general $BASE/reprobados $BASE/recursadores

    echo "Bienvenido al servidor FTP Publico" > $BASE/general/LEEME.txt

    for g in reprobados recursadores ftpwrite; do
        getent group "$g" > /dev/null || groupadd "$g"
    done
chown root:ftpwrite   $BASE/general
    chmod 775             $BASE/general

    chown root:reprobados   $BASE/reprobados
    chown root:recursadores $BASE/recursadores
    chmod 770 $BASE/reprobados $BASE/recursadores

    echo "[OK] Estructura de directorios y permisos listos."
}

GestionUG(){
    while true; do
        echo -e "\n[*] Gestión de Usuarios y Grupos"
        echo "1) Crear Usuarios (Masivo)"
        echo "2) Cambiar Usuario de Grupo"
        echo "7) Volver al Menú"
        read -p "Opcion: " op
        case $op in
            1) CrearUser ;;
            2) CambiarGrupo ;;
            7) return 0 ;;
            *) echo "Opción no válida." ;;
        esac
    done
}

CrearUser(){
    clear
    echo " [*] Creación de Usuarios"
    read -p "Cantidad de usuarios a crear: " N_Usuarios

    for (( i=1; i<=$N_Usuarios; i++ ))
    do
        echo -e "\n--- Usuario $i de $N_Usuarios ---"
        read -p "Nombre de usuario: " Nombre_Usuario
        read -s -p "Contraseña: " Passwd_Usuario
        echo -e "\nGrupo: 1) reprobados | 2) recursadores"
        read -p "Opción: " G_Opt

        [[ "$G_Opt" == "1" ]] && Grupo="reprobados" || Grupo="recursadores"

        if id "$Nombre_Usuario" &>/dev/null; then
            echo "[!] El usuario $Nombre_Usuario ya existe. Saltando..."
        else
            useradd -m -g "$Grupo" -G ftpwrite -s /bin/bash "$Nombre_Usuario"
            echo "$Nombre_Usuario:$Passwd_Usuario" | chpasswd

            Home_User="/home/$Nombre_Usuario"
            chown root:root "$Home_User"
            chmod 555 "$Home_User"

            mkdir -p "$Home_User/general" "$Home_User/$Grupo" "$Home_User/$Nombre_Usuario"

            mount --bind $BASE/general "$Home_User/general"
            mount --bind $BASE/$Grupo  "$Home_User/$Grupo"

            grep -q "$Home_User/general" /etc/fstab \
                || echo "$BASE/general  $Home_User/general  none  bind  0  0" >> /etc/fstab
            grep -q "$Home_User/$Grupo"  /etc/fstab \
                || echo "$BASE/$Grupo    $Home_User/$Grupo    none  bind  0  0" >> /etc/fstab

            chown "$Nombre_Usuario:$Grupo" "$Home_User/$Nombre_Usuario"
            chmod 700 "$Home_User/$Nombre_Usuario"

            echo "[+] Usuario $Nombre_Usuario configurado con éxito."
        fi
    done
    sleep 2
}

CambiarGrupo(){
    echo -e "\n--- Cambio de Grupo Dinámico ---"
    read -p "Nombre del usuario: " Nombre_Usuario

    if ! id "$Nombre_Usuario" &>/dev/null; then
        echo "[!] El usuario no existe."
        return 1
    fi

    echo "Seleccione NUEVO Grupo: 1) reprobados | 2) recursadores"
    read -p "Opción: " G_Opt

    if [ "$G_Opt" == "1" ]; then
        NuevoGrupo="reprobados"; ViejoGrupo="recursadores"
    else
        NuevoGrupo="recursadores"; ViejoGrupo="reprobados"
    fi

    usermod -g "$NuevoGrupo" "$Nombre_Usuario"

    chown "$Nombre_Usuario:$NuevoGrupo" "/home/$Nombre_Usuario/$Nombre_Usuario"

    umount -l "/home/$Nombre_Usuario/$ViejoGrupo" 2>/dev/null
    rm -rf "/home/$Nombre_Usuario/$ViejoGrupo"
    sed -i "\|\/home\/$Nombre_Usuario\/$ViejoGrupo|d" /etc/fstab

    mkdir -p "/home/$Nombre_Usuario/$NuevoGrupo"
    mount --bind "$BASE/$NuevoGrupo" "/home/$Nombre_Usuario/$NuevoGrupo"
    grep -q "/home/$Nombre_Usuario/$NuevoGrupo" /etc/fstab \
        || echo "$BASE/$NuevoGrupo  /home/$Nombre_Usuario/$NuevoGrupo  none  bind  0  0" >> /etc/fstab

    echo "[OK] $Nombre_Usuario movido a $NuevoGrupo."
}

menu_FTP(){
    servicio="vsftpd"
    mon_servicer $servicio      

    Setup_Entorno
    Configurar_Servicio

    while true; do
        echo -e "\n================================"
        echo "          Menú FTP              "
        echo "================================"
        echo "1) Gestión de Usuarios (Masiva)"
        echo "2) Consultar estado (systemctl)"
        echo "3) Reiniciar servicio"
        echo "4) Volver al Orquestador"
        read -p "Opción: " opcion
        case $opcion in
            1) GestionUG ;;
            2) systemctl status $servicio --no-pager ;;
            3) systemctl restart $servicio ;;
            4) return 0 ;;
            *) echo "Opción no válida." ;;
        esac
    done
}
