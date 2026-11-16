; FORMAT.COM and SYS.COM (-DSYS): the kernel's FORMAT and SYS, moved
; out of it for room. The code is src/format.asm, assembled here
; against the kernel's labels (kernel.inc beside the system, found by
; -I) to run at OVLORG, in the TPA's common part, with A2 mapped. This
; copies it there and calls function 201, which runs it only on the
; kernel it was built for: the first word is that kernel's stamp,
; KSTAMP, given by the Makefile.

	include	"kernel.inc"
	include	"../src/bpb.inc"

	org	100h
	ld	a,(0007h)		; room below the BDOS, or an RSX?
	cp	high (OVLEND-1) + 1
	jr	c,nomem
	ld	hl,ovl
	ld	de,OVLORG
	ld	bc,OVLEND-OVLORG
	ldir
	ifdef	SYS
	ld	de,OVLORG+5
	else
	ld	de,OVLORG+2
	endif
	ld	c,OVLFN
	call	5			; back only if not this kernel's
	ld	de,wrong
	jr	pr
nomem:	ld	de,nomsg
pr:	ld	c,9
	call	5
	rst	0
wrong:	db	"Not for this system",0Dh,0Ah,"$"
nomsg:	db	"Not enough memory",0Dh,0Ah,"$"

ovl:
	disp	OVLORG
	dw	KSTAMP
	jp	cformat
	jp	csys
	include	"../src/format.asm"
OVLEND:
	ent
