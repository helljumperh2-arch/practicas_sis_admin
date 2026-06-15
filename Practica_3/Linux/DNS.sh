#!/bin/bash

# ==============================================================================
# MÓDULO DE GESTIÓN DNS (BIND9)
# ==============================================================================
# Parámetros: Usa la variable global $interfaz definida en el orquestador
# Retorno: 0 al volver al orquestador
# ==============================================================================

Configurar_DNS() {
    mon_servicer "bind9"
    local servicio="bind9"
    local conf_local="/etc/bind/named.conf.local"
    local IP_SRV=$(ip -4 addr show "$interfaz" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    while true; do
        echo -e "\n------------------------------------"
        echo "        MODULO GESTIÓN DNS (ABC)      "
        echo "------------------------------------"
        echo "1) Listar Dominios (Consulta)"
        echo "2) Crear Nuevo Dominio (Alta + Inversa)"
        echo "3) Borrar Dominio (Baja)"
        echo "4) Volver al Orquestador"
        read -p "Opción: " opt_dns
        case $opt_dns in
            1)
                echo -e "\n[i] Dominios configurados en $conf_local:"
                grep "zone" "$conf_local" | cut -d'"' -f2 || echo "No hay dominios registrados."
                ;;
            2)
                read -p "Nombre del dominio (ej. redes.com): " dominio
                valid_dominio "$dominio" || continue

                read -p "IP de DESTINO (Enter para $IP_SRV): " ip_dest
                local IP_FINAL=${ip_dest:-$IP_SRV}
                valid_ip "$IP_FINAL" "$IP_SRV" "host" || continue
                IFS='.' read -r o1 o2 o3 o4 <<< "$IP_FINAL"
                local ZONA_INV="$o3.$o2.$o1.in-addr.arpa"
                local FILE_INV="/etc/bind/db.$o1.$o2.$o3"
                sed -i "/zone \"$dominio\"/,/};/d" "$conf_local"
                echo "zone \"$dominio\" { type master; file \"/etc/bind/db.$dominio\"; };" >> "$conf_local"
                
                if ! grep -q "$ZONA_INV" "$conf_local"; then
                    echo "zone \"$ZONA_INV\" { type master; file \"$FILE_INV\"; };" >> "$conf_local"
                fi

                cat <<EOF > "/etc/bind/db.$dominio"
\$TTL 604800
@ IN SOA ns.$dominio. root.$dominio. ( $(date +%s) 604800 86400 2419200 604800 )
@ IN NS ns.$dominio.
@ IN A $IP_FINAL
ns IN A $IP_SRV
www IN A $IP_FINAL
EOF

                if [ ! -f "$FILE_INV" ]; then
                    cat <<EOF > "$FILE_INV"
\$TTL 604800
@ IN SOA ns.$dominio. root.$dominio. ( $(date +%s) 604800 86400 2419200 604800 )
@ IN NS ns.$dominio.
EOF
                fi
                
                if ! grep -q "^$o4" "$FILE_INV"; then
                    echo "$o4 IN PTR $dominio." >> "$FILE_INV"
                    echo "$o4 IN PTR www.$dominio." >> "$FILE_INV"
                fi

                if named-checkconf "$conf_local" && named-checkzone "$dominio" "/etc/bind/db.$dominio"; then
                    systemctl restart "$servicio"
                    echo -e "\e[32m[OK] Alta exitosa de $dominio.\e[0m"
                else
                    echo -e "\e[31m[!] Error de sintaxis en BIND9. Revise los archivos db.\e[0m"
                fi
                ;;

            3)
                read -p "Dominio a eliminar: " borrar
                [[ -z "$borrar" ]] && continue
                
                sed -i "/zone \"$borrar\"/,/};/d" "$conf_local"
                rm -f "/etc/bind/db.$borrar"
                systemctl restart "$servicio"
                echo -e "\e[32m[OK] Dominio $borrar eliminado correctamente.\e[0m"
                ;;

            4) 
                return 0 
                ;;
            *)
                echo "Opción no válida."
                ;;
        esac
    done
}
