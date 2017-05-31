;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	KCWI_STAGE6DRR
;
; PURPOSE:
;	This procedure applies a slice relative response correction.
;
; CATEGORY:
;	Data reduction for the Keck Cosmic Web Imager (KCWI).
;
; CALLING SEQUENCE:
;	KCWI_STAGE6DRR, Procfname, Pparfname
;
; OPTIONAL INPUTS:
;	Procfname - input proc filename generated by KCWI_PREP
;			defaults to './redux/kcwi.proc'
;	Pparfname - input ppar filename generated by KCWI_PREP
;			defaults to './redux/kcwi.ppar'
;
; KEYWORDS:
;	VERBOSE	- set to verbosity level to override value in ppar file
;	DISPLAY - set to display level to override value in ppar file
;
; OUTPUTS:
;	None
;
; SIDE EFFECTS:
;	Outputs processed files in output directory specified by the
;	KCWI_PPAR struct read in from Pparfname.
;
; PROCEDURE:
;	Reads Pparfname to derive input/output directories and reads the
;	corresponding '*.proc' file in output directory to derive the list
;	of input files and their associated rr files.  Each input
;	file is read in and the required rr is generated and 
;	divided out of the observation.
;
; EXAMPLE:
;	Perform stage6drr reductions on the images in 'night1' directory and 
;	put results in 'night1/redux':
;
;	KCWI_STAGE6DRR,'night1/redux/rr.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2013-NOV-12	Initial version
;	2013-NOV-15	Fixed divide by zero in rr correction
;	2014-APR-05	Use master ppar and link files
;	2014-APR-06	Apply to nod-and-shuffle sky and obj cubes
;	2014-MAY-13	Include calibration image numbers in headers
;	2014-SEP-29	Added infrastructure to handle selected processing
;	2017-APR-21	Modified from kcwi_stage6rr.pro for direct images
;-
pro kcwi_stage6drr,procfname,ppfname,help=help,verbose=verbose, display=display
	;
	; setup
	pre = 'KCWI_STAGE6DRR'
	startime=systime(1)
	q = ''	; for queries
	;
	; help request
	if keyword_set(help) then begin
		print,pre+': Info - Usage: '+pre+', Proc_filespec, Ppar_filespec'
		print,pre+': Info - default filespecs usually work (i.e., leave them off)'
		return
	endif
	;
	; get ppar struct
	ppar = kcwi_read_ppar(ppfname)
	;
	; verify ppar
	if kcwi_verify_ppar(ppar,/init) ne 0 then begin
		print,pre+': Error - pipeline parameter file not initialized: ',ppfname
		return
	endif
	;
	; directories
	if kcwi_verify_dirs(ppar,rawdir,reddir,cdir,ddir,/nocreate) ne 0 then begin
		kcwi_print_info,ppar,pre,'Directory error, returning',/error
		return
	endif
	;
	; check keyword overrides
	if n_elements(verbose) eq 1 then $
		ppar.verbose = verbose
	if n_elements(display) eq 1 then $
		ppar.display = display
	;
	; log file
	lgfil = reddir + 'kcwi_stage6drr.log'
	filestamp,lgfil,/arch
	openw,ll,lgfil,/get_lun
	ppar.loglun = ll
	printf,ll,'Log file for run of '+pre+' on '+systime(0)
	printf,ll,'DRP Ver: '+kcwi_drp_version()
	printf,ll,'Raw dir: '+rawdir
	printf,ll,'Reduced dir: '+reddir
	printf,ll,'Calib dir: '+cdir
	printf,ll,'Data dir: '+ddir
	printf,ll,'Filespec: '+ppar.filespec
	printf,ll,'Ppar file: '+ppfname
	if ppar.clobber then $
		printf,ll,'Clobbering existing images'
	printf,ll,'Verbosity level   : ',ppar.verbose
	printf,ll,'Plot display level: ',ppar.display
	;
	; read proc file
	kpars = kcwi_read_proc(ppar,procfname,imgnum,count=nproc)
	;
	; gather configuration data on each observation in reddir
	kcwi_print_info,ppar,pre,'Number of input images',nproc
	;
	; loop over images
	for i=0,nproc-1 do begin
		;
		; image to process
		;
		; first check for input file
		obfil = kcwi_get_imname(kpars[i],imgnum[i],'_img',/reduced)
		;
		; check if input file exists
		if file_test(obfil) then begin
			;
			; read configuration
			kcfg = kcwi_read_cfg(obfil)
			;
			; final output file
			ofil = kcwi_get_imname(kpars[i],imgnum[i],'_imgr',/reduced)
			;
			; trim image type
			kcfg.imgtype = strtrim(kcfg.imgtype,2)
			;
			; check of output file exists already
			if kpars[i].clobber eq 1 or not file_test(ofil) then begin
				;
				; print image summary
				kcwi_print_cfgs,kcfg,imsum,/silent
				if strlen(imsum) gt 0 then begin
					for k=0,1 do junk = gettok(imsum,' ')
					imsum = string(i+1,'/',nproc,format='(i3,a1,i3)')+' '+imsum
				endif
				print,""
				print,imsum
				printf,ll,""
				printf,ll,imsum
				flush,ll
				;
				; do we have a rr link?
				do_rr = (1 eq 0)
				if strtrim(kpars[i].masterrr,2) ne '' then begin
					;
					; master rr file name
					mrfile = kpars[i].masterrr
					;
					; is rr file already built?
					if file_test(mrfile) then begin
						do_rr = (1 eq 1)
						;
						; log that we got it
						kcwi_print_info,ppar,pre,'direct rr file = '+mrfile
					endif else begin
						;
						; does input rr image exist?
						;
						; check for input direct rr image
						rinfile = repstr(mrfile,'_drr','_img')
						if file_test(rinfile) then begin
							do_rr = (1 eq 1)
							kcwi_print_info,ppar,pre,'building direct rr file = '+mrfile
						endif else begin
							;
							; log that we haven't got it
							kcwi_print_info,ppar,pre,'direct rr input file not found: '+rinfile,/warning
						endelse
					endelse
				endif
				;
				; let's read in or create master rr
				if do_rr then begin
					;
					; build master rr if necessary
					if not file_test(mrfile) then begin
						;
						; get observation info
						rcfg = kcwi_read_cfg(rinfile)
						;
						; build master rr
						kcwi_direct_rr,rcfg,kpars[i]
					endif
					;
					; read in master rr
					mrr = mrdfits(mrfile,0,mrhdr,/fscale,/silent)
					;
					; get dimensions
					mrsz = size(mrr,/dimension)
					;
					; get master rr image number
					mrimgno = sxpar(mrhdr,'FRAMENO')
					;
					; avoid divide by zero
					zs = where(mrr le 0., nzs)
					;
					; divide by large number
					if nzs gt 0 then mrr[zs] = 1.e9
					;
					; read in image
					img = mrdfits(obfil,0,hdr,/fscale,/silent)
					;
					; get dimensions
					sz = size(img,/dimension)
					;
					; log sizes
					kcwi_print_info,ppar,pre,'Input direct rr size',mrsz, $
						format='(a,2i7)'
					kcwi_print_info,ppar,pre,'Input object    size',sz, $
						format='(a,2i7)'
					;
					; do correction
					img = img / mrr
					;
					; update header
					sxaddpar,hdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,hdr,'RRCOR','T',' drr corrected?'
					sxaddpar,hdr,'MRFILE',mrfile,' master drr file applied'
					sxaddpar,hdr,'MRIMNO',mrimgno,' master drr image number'
					;
					; write out rr corrected image
					ofil = kcwi_get_imname(kpars[i],imgnum[i],'_imgr',/nodir)
					kcwi_write_image,img,hdr,ofil,kpars[i]
					;
					; handle the case when no drr frames were taken
				endif else begin
					kcwi_print_info,ppar,pre,'cannot associate with any master drr: '+ $
						kcfg.obsfname,/warning
				endelse
			;
			; end check if output file exists already
			endif else begin
				kcwi_print_info,ppar,pre,'file not processed: '+obfil+' type: '+kcfg.imgtype,/warning
				if kpars[i].clobber eq 0 and file_test(ofil) then $
					kcwi_print_info,ppar,pre,'processed file exists already',/warning
			endelse
		;
		; end check if input file exists
		endif
	endfor	; loop over images
	;
	; report
	eltime = systime(1) - startime
	print,''
	printf,ll,''
	kcwi_print_info,ppar,pre,'run time in seconds',eltime
	kcwi_print_info,ppar,pre,'finished on '+systime(0)
	;
	; close log file
	free_lun,ll
	;
	return
end
