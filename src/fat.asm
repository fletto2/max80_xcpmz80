; xcpmz80 FAT layer. Runs in A2. FAT12, FAT16 and FAT32 volumes of
; 512-byte sectors, under 200000h sectors and 100000h clusters.
; The BPB in sector 0 describes each volume.

; Select drive A (0-2) for the cache and point IX at it. Z if it has
; a device, else NZ and A = E_BADDRV.
seldrv:	cp	NDRV
	jr	nc,sd1
	ld	(drvnum),a
	call	drvix
	ld	a,(ix+D_TYPE)
	or	a
	jr	z,sd1
	xor	a
	ret
sd1:	ld	a,E_BADDRV
	or	a
	ret

; Mount drive A: select it, and read its BPB if not mounted yet.
; Z on success, else NZ and A = error. A floppy that gives no BPB is
; tried once more from the other first sector number: Lobo's layout
; numbers from 0, a PC's from 1, on either connector.
mount:	call	seldrv
	ret	nz
	call	mnt_0
	ret	nz
	jp	setdir
mnt_0:	ld	a,(ix+D_MNT)		; mounted already: Z, A = 0
	dec	a
	ret	z
	call	mount1
	ret	z
	cp	E_READ
	ret	nz
	ld	a,(ix+D_TYPE)
	cp	DT_FLOPPY
	ld	a,E_READ
	ret	nz
	ld	a,(ix+D_SBASE)
	xor	1
	ld	(ix+D_SBASE),a
	ld	a,(drvnum)		; what was read from the other is wrong
	call	bforget
	ld	a,(drvnum)
	call	seldrv
mount1:	ld	a,(ix+D_TYPE)		; the hard disk: its partition first
	cp	DT_SASI
	jr	nz,mt0
	call	pfind
	ret	nz
mt0:	ld	de,0
	xor	a
	ld	(lbax),a
	call	getsec
	ret	nz
	push	hl
	pop	iy			; IY = the boot sector
	ld	a,(iy+0Bh)		; 512 bytes a sector
	or	a
	jr	nz,mtbad
	ld	a,(iy+0Ch)
	cp	2
	jr	nz,mtbad
	ld	a,(iy+0Dh)		; sectors per cluster, a power of 2
	or	a
	jr	z,mtbad
	ld	(ix+D_SPC),a
	ld	b,a
	dec	a
	and	b
	jr	nz,mtbad
	ld	a,b
	ld	b,0
mt1:	rrca
	jr	c,mt2
	inc	b
	jr	mt1
mtbad:	ld	a,E_READ		; not a BPB we take
	or	a
	ret
mt2:	ld	(ix+D_SPCSH),b
	ld	l,(iy+0Eh)		; reserved
	ld	h,(iy+0Fh)
	ld	(ix+D_FATSEC),l
	ld	(ix+D_FATSEC+1),h
	ld	a,(iy+10h)
	or	a
	jr	z,mtbad
	ld	(ix+D_NFATS),a
	ld	c,(iy+16h)		; sectors per FAT: 16 bits, or when 0
	ld	b,(iy+17h)		; FAT32's 32, under 65536
	ld	a,b
	or	c
	jr	nz,mt_f
	ld	a,(iy+26h)
	or	(iy+27h)
	jr	nz,mtbad
	ld	c,(iy+24h)
	ld	b,(iy+25h)
mt_f:	ld	(ix+D_SPF),c
	ld	(ix+D_SPF+1),b
	ld	a,(ix+D_NFATS)
mt3:	add	hl,bc			; root = reserved + FATs * SPF
	jr	c,mtbad
	dec	a
	jr	nz,mt3
	ld	(ix+D_ROOTSEC),l
	ld	(ix+D_ROOTSEC+1),h
	ex	de,hl			; DE = root
	ld	l,(iy+11h)		; root entries, 16 a sector, whole; none
	ld	h,(iy+12h)		; on FAT32, below
	ld	a,l
	and	0Fh
	jr	nz,mtbad
	ld	(ix+D_ROOTENT),l
	ld	(ix+D_ROOTENT+1),h
	ld	b,4
	call	shrb
	add	hl,de
	jr	c,mtbad
	ld	(ix+D_DATASEC),l
	ld	(ix+D_DATASEC+1),h
	ex	de,hl			; DE = data start
	ld	l,(iy+13h)		; total sectors, C:HL: the 16-bit count,
	ld	h,(iy+14h)		; or when it is 0 the 32-bit one, under
	ld	c,0			; 200000h, the SASI command's 21 bits
	ld	a,h			;
	or	l
	jr	nz,mt_t
	ld	a,(iy+23h)
	or	a
	jp	nz,mtbad
	ld	c,(iy+22h)
	ld	a,c
	cp	20h
	jp	nc,mtbad
	ld	l,(iy+20h)
	ld	h,(iy+21h)
	or	h
	or	l
	jp	z,mtbad
mt_t:	ld	(ix+D_TOTALH),h		; its high byte, for a floppy
	or	a
	sbc	hl,de
	ld	a,c
	sbc	a,0
	jp	c,mtbad
	ld	c,a
	ld	b,(ix+D_SPCSH)		; clusters = data sectors >> SPCSH
	inc	b
mt_sh:	dec	b
	jr	z,mt_sd
	srl	c
	rr	h
	rr	l
	jr	mt_sh
mt_sd:	ld	a,c			; 1 to FFFFFh
	or	h
	or	l
	jp	z,mtbad
	ld	a,c
	cp	10h
	jp	nc,mtbad
	ld	de,1			; highest cluster = clusters + 1
	add	hl,de
	adc	a,d
	ld	(ix+D_MAXCL),l
	ld	(ix+D_MAXCL+1),h
	ld	(ix+D_MAXCLX),a
	or	a			; FAT32 past FFF6h, FAT16 from 4086
	jr	nz,mt_32
	ld	de,-0FFF7h
	add	hl,de
	jr	c,mt_32
	ld	de,0FFF7h-(4085+1)
	add	hl,de
	sbc	a,a			; 0 or 1
	neg
	jr	mt_ty
mt_32:	ld	a,2
mt_ty:	ld	(ix+D_FAT16),a
	ld	l,(ix+D_MAXCL)		; sectors per FAT enough for the
	ld	h,(ix+D_MAXCL+1)	; entries, 0 to the highest
	inc	hl
	or	a
	jr	z,mt12
	dec	a
	jr	nz,mt32f
	ld	a,l			; FAT16: 256 a sector
	or	a
	ld	l,h
	ld	h,0
	jr	z,mt4
	inc	hl
	jr	mt4
mt32f:	dec	hl			; FAT32: 128 a sector, from MAXCL
	ld	de,128			; as inc may have wrapped
	add	hl,de
	ld	a,(ix+D_MAXCLX)
	adc	a,0
	add	hl,hl
	rla
	ld	l,h
	ld	h,a
	jr	mt4
mt12:	ld	d,h			; FAT12: 3 bytes for 2, 1024 for 3 sectors
	ld	e,l
	add	hl,hl
	add	hl,de
	ld	de,1023
	add	hl,de
	ld	b,10
	call	shrb
mt4:	ex	de,hl
	ld	l,(ix+D_SPF)
	ld	h,(ix+D_SPF+1)
	or	a
	sbc	hl,de
	jp	c,mtbad
	ld	a,(ix+D_ROOTENT)	; a root of entries on FAT12 and FAT16,
	or	(ix+D_ROOTENT+1)	; none on FAT32
	ld	b,a
	ld	a,(ix+D_FAT16)
	cp	2
	ld	a,b
	jr	z,mt_r32
	or	a
	jp	z,mtbad
	jr	mt_rk
mt_r32:	or	(iy+2Fh)		; FAT32: the root a chain from its
	jp	nz,mtbad		; cluster, the FATs mirrored
	bit	7,(iy+28h)
	jp	nz,mtbad
	ld	l,(iy+2Ch)
	ld	h,(iy+2Dh)
	ld	a,(iy+2Eh)
	ld	(clx),a
	call	fateoc
	jp	c,mtbad
	ld	(ix+D_ROOTCL),l
	ld	(ix+D_ROOTCL+1),h
	ld	a,(clx)
	ld	(ix+D_ROOTCL+2),a
	ld	a,(iy+31h)		; FSInfo's sector, under 256, 0 none
	or	a
	ld	a,(iy+30h)
	jr	z,mt_fi
	xor	a
mt_fi:	ld	(ix+D_FSINFO),a
mt_rk:	ld	a,(iy+18h)		; floppy geometry
	ld	(ix+D_SPT),a
	ld	a,(iy+1Ah)
	ld	(ix+D_HEADS),a
	call	freeptr			; free clusters: counted when asked
	ld	a,0FFh
	ld	(hl),a
	inc	hl
	ld	(hl),a
	inc	hl
	ld	(hl),a
	ld	hl,0			; and a folder's place on another disk
	ld	(dscix),hl
	ld	(ix+D_HINT),2
	ld	(ix+D_HINT+1),0
	ld	(ix+D_HINTX),0
	ld	a,(ix+D_FAT16)		; FAT32: both from FSInfo
	cp	2
	call	z,fsiget
	ld	(ix+D_MNT),1
	jp	cwdchk

; FSInfo, FAT32's free count and next free cluster, so the free space
; is not a scan of the FAT. Kept as the count changes, through the
; cache. Without its signatures it is not used, D_FSINFO 0.

; The free count and the hint from FSInfo, when it has them
fsiget:	call	fsisec
	ret	nz
	ld	de,491			; the count's top byte: 0, or not known
	add	hl,de
	ld	a,(hl)
	or	a
	jr	nz,fsg_1
	dec	hl
	dec	hl
	dec	hl
	push	hl
	call	freeptr
	ex	de,hl
	pop	hl
	ld	bc,3
	ldir
fsg_1:	inc	hl			; the next free cluster, for the hint
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	c,(hl)
	inc	hl
	ld	a,(hl)
	or	a
	ret	nz
	ld	a,c
	ld	(clx),a
	ex	de,hl
	call	fateoc
	ret	c
	ld	(ix+D_HINT),l
	ld	(ix+D_HINT+1),h
	ld	a,(clx)
	ld	(ix+D_HINTX),a
	ret

; The free count, when known, and the hint into FSInfo. Keeps BC, DE
; and HL.
fsiput:	ld	a,(ix+D_FAT16)
	cp	2
	ret	nz
	push	bc
	push	de
	push	hl
	call	fsisec
	jr	nz,fsp_9
	ld	de,488
	add	hl,de
	ex	de,hl
	call	freeptr
	ld	bc,3
	ldir
	xor	a
	ld	(de),a
	inc	de
	ld	a,(ix+D_HINT)
	ld	(de),a
	inc	de
	ld	a,(ix+D_HINT+1)
	ld	(de),a
	inc	de
	ld	a,(ix+D_HINTX)
	ld	(de),a
	inc	de
	xor	a
	ld	(de),a
	call	bdirty
fsp_9:	pop	hl
	pop	de
	pop	bc
	ret

; HL = FSInfo's sector in the cache, its signatures right: Z. NZ when
; there is none or a read fails.
fsisec:	ld	a,(ix+D_FSINFO)
	or	a
	jr	z,fsi_n
	ld	e,a
	ld	d,0
	xor	a
	ld	(lbax),a
	call	getsec
	ret	nz
	push	hl
	ld	de,fsisig
	ld	b,4
	call	match
	pop	hl
	jr	nz,fsi_b
	push	hl
	ld	de,484
	add	hl,de
	ld	de,fsisig+4
	ld	b,4
	call	match
	pop	hl
	ret	z
fsi_b:	ld	(ix+D_FSINFO),0
fsi_n:	or	1
	ret
fsisig:	db	"RRaArrAa"

; Unmount drive A, after writing out its buffers
umount:	push	af
	call	drvix
	ld	(ix+D_MNT),0
	ld	(ix+D_RO),0		; and not write protected (28)
	pop	af
	call	frlose
	jp	bforget

; Drive A is unmounted: its fresh cluster is forgotten, never zeroed
; on a disk that may have been changed since. Keeps A.
frlose:	ld	hl,frdrv
	inc	a
	cp	(hl)
	jr	nz,frl_1
	ld	(hl),0
frl_1:	dec	a
	ret

; ------------------------------------------------------------------
; Clusters are 24 bits, clx:HL, the third byte in clx. Each one
; kept is 3 bytes, low first.

; clx:HL = the cluster at HL. Keeps BC and DE.
ldcl:	push	de
	ld	e,(hl)
	inc	hl
	ld	d,(hl)
	inc	hl
	ld	a,(hl)
	ld	(clx),a
	ex	de,hl
	pop	de
	ret

; The cluster at DE = clx:HL. Keeps BC and HL.
stcl:	ld	a,l
	ld	(de),a
	inc	de
	ld	a,h
	ld	(de),a
	inc	de
	ld	a,(clx)
	ld	(de),a
	dec	de
	dec	de
	ret

; Z if clx:HL is the cluster at DE. Keeps BC, DE and HL.
clcmp:	ld	a,(de)
	cp	l
	ret	nz
	inc	de
	ld	a,(de)
	cp	h
	inc	de
	ld	a,(de)
	dec	de
	dec	de
	ret	nz
	push	hl
	ld	hl,clx
	cp	(hl)
	pop	hl
	ret

; clx:HL + 1. Keeps BC and DE.
clinc:	inc	hl
	ld	a,h
	or	l
	ret	nz
	push	hl
	ld	hl,clx
	inc	(hl)
	pop	hl
	ret

; Z if clx:HL is 0. Keeps everything else.
clzero:	ld	a,(clx)
	or	h
	or	l
	ret

; ------------------------------------------------------------------
; FAT entries. IX = the mounted drive, drvnum = its number.

; clx:HL = the entry for cluster clx:HL. Z on success. On FAT32 an
; entry past 20 bits is an end, FFFFFFh: no cluster is that far.
fatget:	call	fatloc			; HL = data
	ret	nz
	ld	e,(hl)
	call	fatnext
	ret	nz
	ld	d,(hl)
	ld	a,(ix+D_FAT16)
	cp	2
	jr	z,fg32
	ex	de,hl
	ld	b,a
	xor	a
	ld	(clx),a
	ld	a,b
	dec	a			; FAT16: done, Z
	ret	z
	ld	a,(fodd)
	or	a
	ld	a,h
	jr	z,fg1			; even: the low 12 bits
	add	hl,hl			; odd: the top 12 bits, H = bits 4-11
	add	hl,hl
	add	hl,hl
	add	hl,hl
	ld	l,h
	rrca				; and A = bits 12-15
	rrca
	rrca
	rrca
fg1:	and	0Fh
	ld	h,a
	xor	a
	ret
fg32:	inc	hl			; an entry is in one sector, 28 bits
	ld	c,(hl)			; and the top 4 kept
	inc	hl
	ld	a,(hl)
	and	0Fh
	ex	de,hl
	ld	a,c
	jr	nz,fg_e
	cp	10h
	jr	c,fg_x
fg_e:	ld	a,0FFh
	ld	h,a
	ld	l,a
fg_x:	ld	(clx),a
	xor	a
	ret

; The entry for cluster clx:HL an end of chain, or free. Keeps clx.
fatend:	ld	a,0FFh
	ld	d,a
	ld	e,a
	jr	fs_v
fatzero: xor	a
	ld	d,a
	ld	e,a
fs_v:	ld	(cvx),a
; Set the entry for cluster clx:HL to cvx:DE. Z on success. Both sectors
; of a FAT12 entry that spans two are read first, by fatget, so a failed
; read changes nothing: the second fatloc and fsnext find them.
; Keeps clx.
fatset:	ld	a,(clx)
	push	hl
	push	de
	push	af
	call	fatget
	pop	bc
	ld	a,b
	ld	(clx),a
	pop	de
	pop	hl
	ret	nz
	push	de
	call	fatloc
	pop	de
	ret	nz
	ld	a,(ix+D_FAT16)
	or	a
	jr	nz,fs16
	ld	a,(fodd)
	or	a
	jr	nz,fsodd
	ld	(hl),e			; even: low 8 bits, then the low nibble
	call	fsnext			; of the next byte
	ret	nz
	ld	a,d
	xor	(hl)
	and	0Fh
	xor	(hl)
	jr	fsput
fsodd:	ld	a,e			; odd: the high nibble of this byte,
	add	a,a			; then 8 bits in the next
	add	a,a
	add	a,a
	add	a,a
	xor	(hl)
	and	0F0h
	xor	(hl)
	ld	(hl),a
	call	fsnext
	ret	nz
	ld	a,e			; DE >> 4, low byte: E's high nibble
	xor	d			; and D's low one, swapped
	and	0F0h
	xor	d
	rrca
	rrca
	rrca
	rrca
	jr	fsput
fs16:	ld	(hl),e
	call	fsnext
	ret	nz
	ld	a,(ix+D_FAT16)
	dec	a
	ld	a,d
	jr	z,fsput
	ld	(hl),a			; FAT32: then cvx, then 0Fh for an end
	inc	hl			; or 0, the top 4 bits kept
	ld	a,(cvx)
	ld	(hl),a
	inc	hl
	inc	a
	ld	a,0
	jr	nz,fs32
	ld	a,0Fh
fs32:	xor	(hl)
	and	0Fh
	xor	(hl)
fsput:	ld	(hl),a
	xor	a
	jp	bdirty

; HL = address of the first byte of cluster clx:HL's entry, in the
; cache. fodd = 1 for an odd FAT12 cluster. The sector is kept in fsecn
; and the byte in fbyte, for fatnext. Z, A = 0 on success.
fatloc:	ld	a,(ix+D_FAT16)
	or	a
	jr	z,fl12
	dec	a
	jr	nz,fl32
	ld	a,l			; FAT16: sector H, byte 2 * L
	ld	l,h
	ld	h,0
	add	a,a
	ld	c,a
	ld	b,h
	rl	b
	jr	fl1
fl32:	ld	a,(clx)			; FAT32: sector clx:HL >> 7, byte
	ld	d,a			; (L & 7Fh) * 4
	ld	e,h
	ld	a,l
	add	a,a
	rl	e
	rl	d
	add	a,a
	ld	c,a
	ld	a,0
	rla
	ld	b,a
	ex	de,hl
	jr	fl1
fl12:	ld	a,l			; FAT12: byte HL + HL / 2
	and	1
	ld	(fodd),a
	ld	d,h
	ld	e,l
	srl	d
	rr	e
	add	hl,de
	ld	a,h			; sector HL / 512, byte HL % 512
	and	1
	ld	b,a
	ld	c,l
	srl	h
	ld	l,h
	ld	h,0
fl1:	ld	(fbyte),bc
	ld	e,(ix+D_FATSEC)
	ld	d,(ix+D_FATSEC+1)
	add	hl,de
	ld	(fsecn),hl
	ex	de,hl
	xor	a			; the FATs are below 65536
	ld	(lbax),a
	call	getsec			; keeps BC
	ret	nz
	add	hl,bc			; Z, A = 0 from getsec
	ret

; The buffer at IY written, then on into fatnext
fsnext:	call	bdirty
; HL = the byte after HL in the FAT, which may be in the next sector.
; Keeps DE. One call after each fatloc: fbyte and fsecn stay put.
fatnext: inc	hl
	ld	bc,(fbyte)
	ld	a,c			; carry if fbyte is 511 (B is 0 or 1)
	add	a,b
	jr	c,fn1
	xor	a
	ret
fn1:	push	de			; the next sector
	ld	de,(fsecn)
	inc	de
	xor	a
	ld	(lbax),a
	call	getsec
	pop	de
	ret

; Carry if clx:HL ends a chain, or is free or bad: below 2 or above the
; highest cluster (which is below FF8h for FAT12, FFF8h for FAT16).
; Keeps BC, DE and HL.
fateoc:	ld	a,l
	and	0FEh
	or	h
	jr	nz,fe_1
	ld	a,(clx)
	or	a
	scf
	ret	z			; 0 or 1
fe_1:	ld	a,(ix+D_MAXCL)		; MAXCL - cluster: carry if beyond
	sub	l
	ld	a,(ix+D_MAXCL+1)
	sbc	a,h
	ld	a,(ix+D_MAXCLX)
	push	hl
	ld	hl,clx
	sbc	a,(hl)
	pop	hl
	ret

; clx:HL = a free cluster, marked as the end of a chain. NZ, A = E_FULL,
; if there is none.
fatalloc:
	ld	l,(ix+D_HINT)
	ld	h,(ix+D_HINT+1)
	ld	a,(ix+D_HINTX)
	ld	(clx),a
	ld	de,fstart
	call	stcl
fa_1:	ld	a,(clx)
	push	af
	push	hl
	call	fatget
	pop	de
	pop	bc
	ret	nz
	call	clzero
	ex	de,hl
	ld	a,b
	ld	(clx),a
	jr	z,fa_3			; free
	call	clinc
	call	fateoc
	jr	nc,fa_2
	ld	hl,2			; past the end: wrap
	xor	a
	ld	(clx),a
fa_2:	ld	de,fstart
	call	clcmp
	jr	nz,fa_1
	ld	a,E_FULL
	or	a
	ret
fa_3:	ld	(ix+D_HINT),l
	ld	(ix+D_HINT+1),h
	ld	a,(clx)
	ld	(ix+D_HINTX),a
	push	hl
	call	fatend
	pop	hl
	ret	nz
	ld	a,-1			; one fewer free
	call	freeadj
	xor	a
	ret

; clx:HL = a free cluster, marked as the end of a chain and linked on
; after cluster clx:HL, the end of a chain. When the link fails, the new
; cluster is freed again and A = the error, NZ.
fatgrow: ld	a,(clx)
	push	af
	push	hl
	call	fatalloc
	pop	de
	pop	bc
	ret	nz
	ld	a,(clx)			; the old one's entry = the new one
	ld	(cvx),a
	push	af
	push	hl
	ex	de,hl
	ld	a,b
	ld	(clx),a
	call	fatset
	pop	hl
	pop	bc
	ld	a,b
	ld	(clx),a
	ret	z
	push	af
	call	fatfree
	pop	af
	ret

; Free the chain starting at clx:HL. dsub's place in a folder goes: the
; chain it was in may be this one.
fatfree: push	hl
	ld	hl,0
	ld	(dscix),hl
	pop	hl
ffr_1:	call	fateoc
	jr	c,ff9
	call	frgone			; the fresh cluster, if it goes
	ld	a,(clx)
	push	af
	push	hl
	call	fatget
	pop	de
	pop	bc
	ret	nz
	call	clzero			; free already: not counted again
	jr	z,ff9
	ld	a,(clx)
	push	af
	push	hl
	ex	de,hl
	ld	a,b
	ld	(clx),a
	call	fatzero
	pop	hl
	pop	bc
	ld	a,b
	ld	(clx),a
	ret	nz
	ld	a,1			; one more free
	call	freeadj
	jr	ffr_1
ff9:	xor	a
	ret

; HL = HL >> B, for B 0 or more. B = 0 after.
shrb:	inc	b
sb_1:	dec	b
	ret	z
	srl	h
	rr	l
	jr	sb_1

; (lbax, DE) = first sector of cluster clx:HL, 24 bits
clsec:	ld	a,(clx)
	ld	de,-2
	add	hl,de
	adc	a,0FFh
	ld	b,(ix+D_SPCSH)
	inc	b
cs1:	dec	b
	jr	z,cs2
	add	hl,hl
	rla
	jr	cs1
cs2:	ld	e,(ix+D_DATASEC)
	ld	d,(ix+D_DATASEC+1)
	add	hl,de
	adc	a,0
	ld	(lbax),a
	ex	de,hl
	ret

; A:HL = the free clusters
fatcount:
	call	freeptr			; counted since the mount?
	ld	a,(hl)
	inc	hl
	and	(hl)
	inc	hl
	and	(hl)
	inc	a
	jr	z,fcn_0
	ld	a,(hl)
	dec	hl
	ld	d,(hl)
	dec	hl
	ld	l,(hl)
	ld	h,d
	ret
fcn_0:	push	hl			; no: count them, and keep it
	call	fcn_s
	pop	hl
	jr	nz,fcn_9		; a FAT not read: not kept
	ld	de,fcnt+2
	ex	de,hl
	ldd
	ldd
	ldd
	call	fsiput
fcn_9:	ld	hl,(fcnt)
	ld	a,(fcnt+2)
	ret
; fcnt = the free clusters. NZ if a FAT sector could not be read, fcnt
; those counted before it
fcn_s:	ld	hl,0
	ld	(fcnt),hl
	xor	a
	ld	(fcnt+2),a
	ld	(clx),a
	ld	l,2
fcn_1:	ld	a,(clx)
	push	af
	push	hl
	call	fatget
	jr	nz,fcn_e
	call	clzero
	pop	hl
	pop	bc
	ld	a,b
	ld	(clx),a
	jr	nz,fcn_2
	push	hl
	ld	hl,fcnt
	inc	(hl)
	jr	nz,fcn_i
	inc	hl
	inc	(hl)
	jr	nz,fcn_i
	inc	hl
	inc	(hl)
fcn_i:	pop	hl
fcn_2:	call	clinc
	call	fateoc
	jr	nc,fcn_1
	xor	a
	ret
fcn_e:	pop	hl
	pop	bc
	ret

; HL = drive IX's free count in dfree. Keeps BC and DE.
freeptr: push	ix
	pop	hl
	ld	a,l
	sub	low drvtab		; drive * DSZ, DSZ 32
	rrca
	rrca
	rrca
	and	1Ch			; drive * 4, NDRV up to 8
	add	a,low dfree
	ld	l,a
	ld	h,high dfree
	ret
	assert	high dfree == high (dfree+NDRV*4-1)

; The count, if kept, one less (A = -1) or more (A = 1). Keeps BC, DE, HL.
freeadj: push	hl
	push	de
	ld	e,a
	call	freeptr
	ld	a,(hl)
	inc	hl
	and	(hl)
	inc	hl
	and	(hl)
	inc	a
	jr	z,fj_9			; not counted
	dec	hl
	dec	hl
	ld	a,e			; D = E's sign, for the high bytes
	rla
	sbc	a,a
	ld	d,a
	ld	a,(hl)
	add	a,e
	ld	(hl),a
	inc	hl
	ld	a,(hl)
	adc	a,d
	ld	(hl),a
	inc	hl
	ld	a,(hl)
	adc	a,d
	ld	(hl),a
	call	fsiput
fj_9:	pop	de
	pop	hl
	ret
