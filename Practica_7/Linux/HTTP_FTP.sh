#!/bin/bash

# ================================================================
# 1. FUNCIONES DE APOYO (SIEMPRE AL INICIO)
# ================================================================

instalar_binario() {
    local s=$1; local f=$2
    echo -e "\e[34m[*] Instalando binario manual de $s...\e[0m"
    if [[ "$f" == *.deb ]]; then 
        sudo dpkg -i "$f"
    else 
        sudo rm -rf /opt/tomcat 2>/dev/null
        sudo mkdir -p /opt/tomcat
        sudo tar -xzf "$f" -C /opt/tomcat --strip-components=1
  
        if [ -d "/opt/${s,,}/bin" ]; then
            sudo chmod +x /opt/${s,,}/bin/*.sh
        fi
        echo -e "\e[32m[OK] Extraído en /opt/tomcat\e[0m"
    fi
}

detener_competencia_manual(){
    echo -e "\e[33m[*] Limpiando servicios para evitar conflictos de puerto...\e[0m"
    sudo systemctl stop nginx apache2 tomcat10 2>/dev/null
    sudo pkill -9 java 2>/dev/null
}

verificar_final() {
    local s=$1
    local p_http=${PUERTO_ACTUAL:-80}
    echo -e "\n[*] Verificando estado del servicio (Paciencia, Java es lento)..."
    
    for i in {1..3}; do
        sleep 5
        if ss -tuln | grep -qE ":443|:$p_http"; then
            echo -e "\n\e[32m--- RESUMEN DE SEGURIDAD ($s) ---\e[0m"
            echo -e "Puerto Seguro/Personalizado: \e[32mONLINE\e[0m"
            echo "Certificado: $DOMINIO [OK]"
            echo -e "\e[32m--------------------------------------\e[0m"
            return 0
        fi
        echo "[...] Reintentando verificación ($i/3)..."
    done

    echo -e "\n\e[31m--- RESUMEN DE SEGURIDAD ($s) ---\e[0m"
    echo -e "Estado: \e[31mOFFLINE\e[0m"
    echo "[!] Tip: Si es Tomcat manual, revisa /opt/tomcat/logs/catalina.out"
    echo -e "\e[31m--------------------------------------\e[0m"
}

# ================================================================
# 2. CONFIGURACIÓN DE SEGURIDAD SSL/TLS
# ================================================================

configurar_seguridad_completa() {
    local serv=${1,,}
    local p_http=${PUERTO_ACTUAL:-80}
    
    sudo mkdir -p "$DIR_SSL"
    if [ ! -f "$DIR_SSL/reprobados.crt" ]; then
        echo "[*] Generando Certificado SSL para $DOMINIO..."
        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$DIR_SSL/reprobados.key" \
            -out "$DIR_SSL/reprobados.crt" \
            -subj "/C=MX/ST=Sinaloa/L=LosMochis/O=Reprobados/CN=$DOMINIO"
    fi

    case $serv in
        "nginx")
            detener_competencia_manual
cat <<EOF | sudo tee /etc/nginx/sites-available/default > /dev/null
server {
    listen $p_http ssl; # Uso de p_http directo
    server_name www.reprobados.com;

    ssl_certificate /etc/ssl/reprobados/reprobados.crt;
    ssl_certificate_key /etc/ssl/reprobados/reprobados.key;

    location / {
        root /var/www/nginx;
        index index.html;
    }
}
EOF
            sudo mkdir -p /var/www/nginx
            echo "<h1>Nginx Seguro - Puerto $p_http</h1>" | sudo tee /var/www/nginx/index.html > /dev/null
            sudo systemctl restart nginx
            ;;

        "apache"|"apache2")
            detener_competencia_manual
            sudo a2enmod ssl rewrite headers >/dev/null 2>&1
            echo "Listen $p_http" | sudo tee /etc/apache2/ports.conf > /dev/null
cat <<EOF | sudo tee /etc/apache2/sites-available/000-default.conf > /dev/null
<VirtualHost *:$p_http>
    ServerName www.reprobados.com
    DocumentRoot /var/www/apache2
    
    SSLEngine on
    SSLCertificateFile /etc/ssl/reprobados/reprobados.crt
    SSLCertificateKeyFile /etc/ssl/reprobados/reprobados.key
    
    ErrorDocument 400 "Por favor, use HTTPS para conectar a este puerto."
</VirtualHost>
EOF
            sudo mkdir -p /var/www/apache2
            echo "<h1>Apache Seguro - Puerto $p_http</h1>" | sudo tee /var/www/apache2/index.html > /dev/null
            sudo a2ensite 000-default.conf >/dev/null 2>&1
            sudo systemctl restart apache2
            ;;

       "tomcat"|"tomcat10")
            detener_competencia_manual
            
            local T_CONF=""
            local T_WWW=""
            if [ -d "/opt/tomcat" ]; then
                T_CONF="/opt/tomcat/conf/server.xml"
                T_HOME="/opt/tomcat"
                T_WWW="/opt/tomcat/webapps/ROOT"
            else
                T_CONF="/etc/tomcat10/server.xml"
                T_HOME="/usr/share/tomcat10"
                T_WWW="/var/lib/tomcat10/webapps/ROOT"
            fi

            if [ -f "$T_CONF" ]; then
                echo "[*] Configurando HTTPS DIRECTO en $T_CONF (Puerto: $p_http)..."
                sudo sed -i '/<Connector port="/,/ \/>/d' "$T_CONF"
                sudo sed -i '/<Service name="Catalina">/a \
    <Connector port="'$p_http'" protocol="org.apache.coyote.http11.Http11NioProtocol" \
               maxThreads="150" SSLEnabled="true" scheme="https" secure="true"> \
        <SSLHostConfig> \
            <Certificate certificateFile="'$DIR_SSL'/reprobados.crt" \
                         certificateKeyFile="'$DIR_SSL'/reprobados.key" \
                         type="RSA" /> \
        </SSLHostConfig> \
    </Connector>' "$T_CONF"
                
                sudo mkdir -p "$T_WWW"
                echo "<h1>Tomcat Seguro - Puerto $p_http</h1>" | sudo tee "$T_WWW/index.html" > /dev/null

                if [[ "$T_CONF" == *"/opt/"* ]]; then
                    echo "[*] Iniciando Tomcat Manual (startup.sh)..."
                    sudo /opt/tomcat/bin/startup.sh
                else
                    echo "[*] Reiniciando Tomcat por Service..."
                    sudo systemctl restart tomcat10
                fi
            fi
            ;;

        "vsftpd")
            sudo sed -i "s/ssl_enable=NO/ssl_enable=YES/" /etc/vsftpd.conf
            echo -e "rsa_cert_file=$DIR_SSL/reprobados.crt\nrsa_private_key_file=$DIR_SSL/reprobados.key\nforce_local_data_ssl=YES\nforce_local_logins_ssl=YES" | sudo tee -a /etc/vsftpd.conf > /dev/null
            sudo systemctl restart vsftpd
            ;;
    esac
    verificar_final "$serv"
}

# ================================================================
# 3. MOTOR HÍBRIDO E INSTALACIÓN
# ================================================================

motor_instalacion_hibrida() {
    local servicio=$1
    local paquete_apt=${servicio,,}
    [ "$servicio" == "Apache" ] && paquete_apt="apache2"
    [ "$servicio" == "Tomcat" ] && paquete_apt="tomcat10"

    echo -e "\n\e[34m[I]\e[0m --- Instalando: $servicio ---"
    echo "1) APT (Oficial) | 2) FTP (Privado)"
    read -p "Elija origen: " origen

    if [ "$origen" -eq 1 ]; then
        sudo apt update && sudo apt install -y $paquete_apt
    else
        mapfile -t versiones < <(curl -s -u "$FTP_USER:$FTP_PASS" "$FTP_BASE/$servicio/" | awk '{print $NF}' | grep -v ".sha256")
        [ ${#versiones[@]} -eq 0 ] && { echo "Error al conectar al FTP"; return 1; }
        
        for i in "${!versiones[@]}"; do echo "$((i+1))) ${versiones[$i]}"; done
        read -p "Seleccione versión: " v_idx
        archivo="${versiones[$((v_idx-1))]}"
        
        curl -u "$FTP_USER:$FTP_PASS" -O "$FTP_BASE/$servicio/$archivo"
        curl -u "$FTP_USER:$FTP_PASS" -O "$FTP_BASE/$servicio/$archivo.sha256"
        
        if sha256sum -c "$archivo.sha256" --status; then
            instalar_binario "$servicio" "$archivo"
        else
            echo "Error de integridad (Hash)"; return 1
        fi
    fi

    read -p "¿Desea aplicar SSL/TLS ahora? [S/N]: " opt_ssl
    [[ "$opt_ssl" =~ ^[Ss]$ ]] && configurar_seguridad_completa "$paquete_apt"
}

# ================================================================
# 4. MENÚ PRINCIPAL DEL MÓDULO
# ================================================================

menu_ftp_http(){
    FTP_IP=$(ip addr show $interfaz | grep "inet " | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    FTP_USER="anonymous"; FTP_PASS=""; FTP_BASE="ftp://$FTP_IP/documentos_publicos/http/Linux"
    DIR_SSL="/etc/ssl/reprobados"; DOMINIO="www.reprobados.com"

    while true; do
        local p_actual=${PUERTO_ACTUAL:-"N/A"}
        echo -e "\n===================================================="
        echo -e "      MODULO HTTP/FTP - IP: $FTP_IP"
        echo -e "      PUERTO CONFIGURADO: $p_actual"
        echo -e "===================================================="
        echo " 1) Instalar Nginx (SSL)"
        echo " 2) Instalar Apache2 (SSL)"
        echo " 3) Instalar Tomcat (SSL)"
        echo " 4) Configurar FTP Seguro (TLS)"
        echo " 5) Configurar/Cambiar Puerto (Validar Puerto)"
        echo "----------------------------------------------------"
        echo " 6) Verificar Netstat"
        echo " 7) Volver al Orquestador"
        echo "===================================================="
        read -p " Opción: " opcion

        case $opcion in
            1) motor_instalacion_hibrida "Nginx" ;;
            2) motor_instalacion_hibrida "Apache" ;;
            3) motor_instalacion_hibrida "Tomcat" ;;
            4) configurar_seguridad_completa "vsftpd" ;;
            5) validar_puerto ;; 
            6) ss -tuln | grep -E "(:443|:21|:$p_actual)" ; read -p "Enter..." ;;
            7) return 0 ;;
            *) echo "Inválido" ;;
        esac
    done
}
