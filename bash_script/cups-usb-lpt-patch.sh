#!/bin/bash

if [ "$EUID" -ne 0 ]; then
  echo "[!] Please run this script with sudo: sudo ./setup_lpt_rules.sh"
  exit 1
fi

PRINTER_NAME=""
COLS=$(tput cols)

printf '%*s\n' "$COLS" '' | tr ' ' '='
echo "CUPS USB-to-LPT Converter Patcher Script"
printf '%*s\n' "$COLS" '' | tr ' ' '='
echo "NOTE : This will set CUPS flags on printer and set USB timeout."
echo "WARNING : Only use if using USB-to-LPT Converter."
echo "          If host PC have parallel port, connect printer on that instead."
echo "Press 'Ctrl + C' to cancel."
printf '%*s\n' "$COLS" '' | tr ' ' '='

while true; do
    read -rp "[-] Please Enter Printer Name : " PRINTER_NAME
    echo "[*] Searching printer named '$PRINTER_NAME'..."
    if lpstat -p | grep -q "^printer $PRINTER_NAME "; then
        echo "[/] Found '$PRINTER_NAME'!"
        echo "[*] Configure CUPS URI Flags for '$PRINTER_NAME'..."
        lpadmin -p "$PRINTER_NAME" -o usb-unidir-default=true
        lpadmin -p "$PRINTER_NAME" -o usb-no-reattach-default=true
        lpadmin -p "$PRINTER_NAME" -o printer-op-policy=default
        lpadmin -p "$PRINTER_NAME" -o wait-for-job=false
        lpadmin -p "$PRINTER_NAME" -o print-is-bidi=false
        lpadmin -p "$PRINTER_NAME" -o printer-error-policy=retry-job
        echo "[/] Done configure CUPS URI Flags for '$PRINTER_NAME'."
        if grep -q "^USBPortTimeout" /etc/cups/cupsd.conf; then
            echo "[*] Modifying USBPortTimeout in CUPS config..."
            sudo sed -i 's/^USBPortTimeout.*/USBPortTimeout 1/' /etc/cups/cupsd.conf 2>/dev/null
        else
            echo "[*] Adding USBPortTimeout in CUPS config..."
            echo "USBPortTimeout 1" | sudo tee -a /etc/cups/cupsd.conf 2>/dev/null
        fi
        echo "[*] Cancel any lingering backend locks..."
        cancel -a
        echo "[*] Enabling for '$PRINTER_NAME'..."
        cupsenable "$PRINTER_NAME"
        echo "[*] Accepting job for '$PRINTER_NAME'..."
        cupsaccept "$PRINTER_NAME"
        echo "[*] Restart CUPS service..."
        systemctl restart cups
        break
    else
        echo "[X] Cant find printer named '$PRINTER_NAME'..."
    fi
done

if [ -n "$PRINTER_NAME" ]; then
    echo "[/] Done add flags for '$PRINTER_NAME'."
    printf '%*s\n' "$COLS" '' | tr ' ' '='
    echo "NOTE : Please change communcation port setting on printer, disconnect and reconnect USB converter."
    echo "E.G. : Datamax I4208"
    echo "       MENU"
    echo "       └ COMMUNICATIONS"
    echo "         └ PARALLEL PORT A (or B)"
    echo "           └ PORT DIRECTION"
    echo "             └ Set to 'UNIDIRECTIONAL'"
    printf '%*s\n' "$COLS" '' | tr ' ' '='
    sleep 3
else
    echo "[X] Unable to add flags for '$PRINTER_NAME'."
    sleep 3
    exit 1
fi
