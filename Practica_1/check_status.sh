#!/bin/bash
echo "--------------------------------------" 
echo -e "\nEspacio en disco disponible \n" 
df -hT
echo ""
echo -e "--------------------------------------\n" 
echo  -n "Nombre de la maquina - "; hostname 
echo -n "IP: "; hostname -I