#!/bin/bash
# Configure the mouse's extra buttons to emit F3 / F4 using rivalcfg.
#
# rivalcfg can only talk to the mouse over USB cable (0x1854) or the 2.4 GHz
# dongle (0x1852) - NOT over Bluetooth. The mapping is written to the mouse's
# onboard memory, so it survives unplugging and works over Bluetooth afterwards.
set -euo pipefail

VENV="$HOME/.rivalcfg"
RC="$VENV/bin/rivalcfg"

if [ ! -x "$RC" ]; then
    echo "Creating rivalcfg virtualenv at $VENV"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet rivalcfg
fi

echo "Supported Aerox 5 Wireless transports:"
"$RC" --list | sed -n '/Aerox 5 Wireless/,/^$/p' || true

echo
echo "Writing mapping: Button7 disabled, Button8 = F3, Button9 = F4"
"$RC" -b "buttons(layout=QWERTY; button7=disabled; button8=F3; button9=F4)"

echo
echo "Done. Verify with:"
echo "  $RC --battery-level"
