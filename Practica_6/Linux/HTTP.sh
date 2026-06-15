detener_competencia(){
    local actual=$1
    local p=${PUERTO_ACTUAL:-80}
  
}

aplicar_puerto_http(){
    local servicio=$1
    local p=${PUERTO_ACTUAL:-"N/A"}
    
    if ! [[ "$p" =~ ^[0-9]+$ ]]; then
        echo -e "\e[31m[!] Error: El puerto actual ($p) no es válido. Ve a la opción 7 primero.\e[0m"
        return 1
    fi
    
    echo -e "\e[34m[*] Configurando $servicio en puerto $p...\e[0m"

    case $servicio in
        "nginx")
        
            sed -i -E "s/listen [0-9]+ default_server;/listen $p default_server;/g" /etc/nginx/sites-available/default
            sed -i -E "s/listen \[::\]:[0-9]+ default_server;/listen [::]:$p default_server;/g" /etc/nginx/sites-available/default
            
            sed -i "s|root /var/www/html;|root /var/www/nginx;|g" /etc/nginx/sites-available/default
            mkdir -p /var/www/nginx
            
            echo "<h1>Servidor NGINX Desplegado en Puerto $p</h1>" > /var/www/nginx/index.html
            ;;

        "apache2")
          
            sed -i "s/Listen [0-9]*/Listen $p/g" /etc/apache2/ports.conf
            sed -i "s/:[0-9]*>/:$p>/g" /etc/apache2/sites-available/000-default.conf
            
            sed -i "s|DocumentRoot /var/www/html|DocumentRoot /var/www/apache2|g" /etc/apache2/sites-available/000-default.conf
            mkdir -p /var/www/apache2
            
            echo "<h1>Servidor APACHE2 Desplegado en Puerto $p</h1>" > /var/www/apache2/index.html
            ;;

        "tomcat10")
            local xml_file="/etc/tomcat10/server.xml"
            if [ -f "$xml_file" ]; then
                sed -i "s/Connector port=\"[0-9]*\"/Connector port=\"$p\"/g" "$xml_file"
            fi
            
            local t_root="/var/lib/tomcat10/webapps/ROOT"
            mkdir -p "$t_root"
            echo "<h1>Servidor TOMCAT 10 Desplegado en Puerto $p</h1>" > "$t_root/index.html"
            chown -R tomcat:tomcat "$t_root" 2>/dev/null
            ;;
    esac

    systemctl restart "$servicio" > /dev/null 2>&1
    
    if systemctl is-active --quiet "$servicio"; then
        echo -e "\e[32m[OK] $servicio está ONLINE en http://localhost:$p\e[0m"
    else
        echo -e "\e[31m[!] Error al iniciar $servicio en el puerto $p\e[0m"
    fi
}

menu_http(){
    while true; do
        local mostrar_puerto=${PUERTO_ACTUAL:-"80 (Default)"}
        echo -e "\n================================================"
        echo "                MÓDULO HTTP                     "
        echo "  Puerto configurado para despliegue: $mostrar_puerto"
        echo "================================================"
        echo "1) Instalar Nginx (Elegir Versión)"
        echo "2) Instalar Apache (Elegir Versión)"
        echo "3) Instalar Tomcat (Elegir Versión)"
        
        echo "4) Desplegar Nginx en puerto $mostrar_puerto"
        echo "5) Desplegar Apache en puerto $mostrar_puerto"
        echo "6) Desplegar Tomcat en puerto $mostrar_puerto"
        echo "7) Configurar/Cambiar Puerto de Red"
        echo "8) Volver al Orquestador"
        echo "------------------------------------------------"
        read -p "Seleccione una opción: " opcion

        case $opcion in
            1) mon_servicer "nginx" ;;
            2) mon_servicer "apache2" ;;
            3) mon_servicer "tomcat10" ;;
            
            4) 
                detener_competencia "nginx"
                aplicar_puerto_http "nginx" 
                ;;
            5) 
                detener_competencia "apache2"
                aplicar_puerto_http "apache2"
                ;;
            6) 
                detener_competencia "tomcat10"
                aplicar_puerto_http "tomcat10"
                ;;
            
            7) validar_puerto ;;
            8) return 0 ;;
            *) echo "Opción no válida." ;;
        esac
    done
}
