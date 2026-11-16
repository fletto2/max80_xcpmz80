#!/usr/bin/env python3
"""The kernel's stamp and labels, for FORMAT.COM and SYS.COM.

  kernsym.py stamp IMAGE   prints the stamp: the CRC-16 of the system
                           image assembled with KSTAMP 0, never 0
  kernsym.py inc SYM OUT   the kernel's labels from sjasmplus --sym as
                           EQUs for apps/format.asm, KSTAMP left out

FORMAT and SYS run as an overlay that calls the kernel's own routines,
so each is built with the kernel's labels, and function 201 runs it
only on the kernel whose stamp it carries.
"""
import re
import sys


def crc16(data):
    crc = 0xFFFF
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = (crc << 1) ^ 0x1021 if crc & 0x8000 else crc << 1
            crc &= 0xFFFF
    return crc


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "stamp":
        with open(sys.argv[2], "rb") as f:
            print(crc16(f.read()) or 1)
        return 0
    if len(sys.argv) == 4 and sys.argv[1] == "inc":
        out = []
        with open(sys.argv[2]) as f:
            for line in f:
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*): EQU 0x([0-9A-Fa-f]+)$",
                             line.strip())
                if not m:
                    sys.exit("kernsym: not a label: " + line.strip())
                if m.group(1) == "KSTAMP":
                    continue
                out.append("%s\tequ\t0%Xh\n" % (m.group(1), int(m.group(2), 16)))
        with open(sys.argv[3], "w") as f:
            f.write("; The kernel's labels, made by tools/kernsym.py\n")
            f.writelines(out)
        return 0
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main())
