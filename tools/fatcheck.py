#!/usr/bin/env python3
"""Check a FAT12, FAT16 or FAT32 volume the way fsck does, without
changing it: every FAT copy the same, each file's chain the length its
size needs, each folder's . and .. right, no cluster in two chains, no
used cluster in no chain, and on FAT32 FSInfo's free count the free
clusters, if it gives one. Folders are followed.

Usage: python3 tools/fatcheck.py IMAGE

IMAGE is a raw image (mkdisk.py --raw or --hd, or an IMD through
lobo_max80's tools/imd2raw.py). Prints "clean" and exits 0, or lists the faults
and exits 1.
"""
import struct
import sys


def check(disk):
    bps, spc, rsvd, nfats, nroot, total, _, spf = struct.unpack_from(
        '<HBHBHHBH', disk, 0x0b)
    if total == 0:
        total = struct.unpack_from('<I', disk, 0x20)[0]
    if spf == 0:
        spf = struct.unpack_from('<I', disk, 0x24)[0]
    root0 = rsvd + nfats * spf
    data0 = root0 + nroot * 32 // bps
    nclus = (total - data0) // spc
    bits = 32 if nclus >= 65525 else 16 if nclus >= 4085 else 12
    eoc = {12: 0xff8, 16: 0xfff8, 32: 0xffffff8}[bits]
    faults = []

    fats = [disk[(rsvd + k * spf) * bps:(rsvd + (k + 1) * spf) * bps]
            for k in range(nfats)]
    for k in range(1, nfats):
        if fats[k] != fats[0]:
            faults.append('FAT %d differs from FAT 1' % (k + 1))
    fat = fats[0]

    def get(n):
        if bits == 32:
            return struct.unpack_from('<I', fat, n * 4)[0] & 0xfffffff
        if bits == 16:
            return struct.unpack_from('<H', fat, n * 2)[0]
        v = struct.unpack_from('<H', fat, n * 3 // 2)[0]
        return v >> 4 if n & 1 else v & 0xfff

    owner = {}
    csize = spc * bps

    def walk(first, name):
        """The chain from first, each cluster marked as name's"""
        chain = []
        c = first
        while 2 <= c < eoc and len(chain) <= nclus:
            if c >= nclus + 2:
                faults.append('%s: cluster %d past the end' % (name, c))
                return chain
            if c in owner:
                faults.append('%s: cluster %d is also in %s' % (name, c, owner[c]))
                return chain
            owner[c] = name
            chain.append(c)
            c = get(c)
        if 0 < c < 2 or (eoc > c >= nclus + 2 and c != 0):
            faults.append('%s: chain ends on %d' % (name, c))
        elif c == 0 and chain:  # the next file written takes it
            faults.append('%s: chain ends on a free cluster, after %d'
                          % (name, chain[-1]))
        return chain

    def folder(data, path, me, parent):
        """Check the entries in data, the folder path, and the folders in it"""
        for i in range(len(data) // 32):
            e = data[i * 32:i * 32 + 32]
            if e[0] == 0:
                break
            if e[0] == 0xe5 or e[11] & 0x08:
                continue
            name = (e[:8].decode('latin-1').rstrip() + '.' +
                    e[8:11].decode('latin-1').rstrip())
            first, size = struct.unpack_from('<HI', e, 26)
            if bits == 32:
                first |= struct.unpack_from('<H', e, 20)[0] << 16
            if e[11] & 0x10:
                if e[0] == 0x2e:  # . and ..
                    want = me if e[1] == 0x20 else parent
                    if first != want:
                        faults.append('%s%s: cluster %d, not %d'
                                      % (path, e[:2].decode().strip(), first, want))
                    continue
                full = path + name.rstrip('.')
                if not first:
                    faults.append('%s: a folder with no cluster' % full)
                    continue
                chain = walk(first, full)
                sub = b''.join(disk[(data0 + (c - 2) * spc) * bps:
                                    (data0 + (c - 1) * spc) * bps]
                               for c in chain)
                if sub[0:11] != b'.          ' or sub[32:43] != b'..         ':
                    faults.append('%s: no . and .. first' % full)
                folder(sub, full + '\\', first, me)
                continue
            full = path + name
            need = (size + csize - 1) // csize
            chain = walk(first, full)
            if first == 0 and size:
                faults.append('%s: %d bytes and no cluster' % (full, size))
            if len(chain) != need:
                faults.append('%s: %d bytes need %d clusters, the chain has %d'
                              % (full, size, need, len(chain)))

    def clusters(chain):
        return b''.join(disk[(data0 + (c - 2) * spc) * bps:
                             (data0 + (c - 1) * spc) * bps] for c in chain)

    if bits == 32:
        rootcl = struct.unpack_from('<I', disk, 0x2c)[0]
        folder(clusters(walk(rootcl, '\\')), '', 0, 0)
    else:
        folder(disk[root0 * bps:root0 * bps + nroot * 32], '', 0, 0)
    lost = [n for n in range(2, nclus + 2) if get(n) and n not in owner]
    if lost:
        faults.append('%d lost clusters, the first %d' % (len(lost), lost[0]))
    if bits == 32:
        fsi = struct.unpack_from('<H', disk, 0x30)[0] * bps
        lead, = struct.unpack_from('<I', disk, fsi)
        sig, free, nxt = struct.unpack_from('<III', disk, fsi + 484)
        if lead != 0x41615252 or sig != 0x61417272:
            faults.append('FSInfo: no signature')
        elif free != 0xffffffff:
            real = sum(1 for n in range(2, nclus + 2) if get(n) == 0)
            if free != real:
                faults.append('FSInfo: %d free, not %d' % (free, real))
    return faults


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    faults = check(open(sys.argv[1], 'rb').read())
    for f in faults:
        print(f)
    if faults:
        sys.exit(1)
    print('clean')


if __name__ == '__main__':
    main()
