#!/usr/bin/env bash
set -ex
{
    PRINTER_NAME=${KASM_PRINTER_NAME:-Kasm-Printer}

    echo "Starting cups"
    # HACK: Some versions of cupsd cannot handle unlimited file descriptor limit
    # that docker sets..
    ulimit -n 1024 &&/usr/sbin/cupsd -f &
    until [[ "$(lpstat -r)" == "scheduler is running" ]]; do sleep 15; done

    echo "Creating a virtual printer: $PRINTER_NAME"
    lpadmin -p $PRINTER_NAME -E -v cups-pdf:/ -P /etc/cups/ppd/kasm.ppd
    lpadmin -p $PRINTER_NAME -o print-color-mode-default=color

    echo "Done!"
} 2>&1 | tee /tmp/start_cups.log
