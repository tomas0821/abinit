!{\src2tex{textfont=tt}}
!!****f* ABINIT/outkss
!! NAME
!! outkss
!!
!! FUNCTION
!!  This routine creates an output file containing the Kohn-Sham electronic Structure
!!  for a large number of eigenstates (energies and eigen-functions).
!!  The resulting file (_KSS) is needed for a GW post-treatment.
!!
!! The routine drives the following operations:
!!  - Re-ordering G-vectors according to stars (sets of Gs related by symmetry operations).
!!    A set of g for all k-points is created.
!!  - Creating and opening the output "_KSS'" file
!!  - Printing out output file header information...
!! ... and, for each k-point:
!!    According to 'kssform', either
!!      - Re-computing <G|H|G_prim> matrix elements for all (G, G_prim).
!!        Diagonalizing H in the plane-wave basis.
!!   or - Taking eigenvalues/vectors from congugate-gradient ones.
!!  - Writing out eigenvalues and eigenvectors.
!!
!! COPYRIGHT
!! Copyright (C) 2000-2012 ABINIT group (MT, VO, AR, MG)
!! This file is distributed under the terms of the
!! GNU General Public License, see ~abinit/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!! For the initials of contributors, see ~abinit/doc/developers/contributors.txt.
!!
!! INPUTS
!!  cg(2,mcg)=planewave coefficients of wavefunctions.
!!  usecprj=1 if cprj datastructure has been allocated (ONLY PAW)
!!  Cprj(natom,mcprj*usecprj) <type(cprj_type)>=
!!    projected input wave functions <Proj_i|Cnk> with all NL projectors (only for PAW)
!!    NOTE that Cprj are unsorted, see ctoprj.F90
!!  Dtfil <type(datafiles_type)>=variables related to files
!!  Dtset <type(dataset_type)>=all input variables for this dataset
!!  ecut=cut-off energy for plane wave basis sphere (Ha)
!!  eigen(mband*nkpt*nsppol)=array for holding eigenvalues (hartree)
!!  gmet(3,3)=reciprocal space metric tensor in bohr**-2.
!!  gprimd(3,3)=dimensional reciprocal space primitive translations
!!  Hdr <type(hdr_type)>=the header of wf, den and pot files
!!  kssform=govern the Kohn-Sham Structure file format
!!  mband=maximum number of bands
!!  mcg=size of wave-functions array (cg) =mpw*nspinor*mband*mkmem*nsppol
!!  mcprj=size of projected wave-functions array (cprj) =nspinor*mband*mkmem*nsppol
!!  mgfft=maximum size of 1D FFTs
!!  mkmem =number of k points which can fit in memory; set to 0 if use disk
!!  MPI_enreg=information about MPI parallelization
!!  mpsang= 1+maximum angular momentum for nonlocal pseudopotentials
!!  mpw=maximum dimensioned size of npw.
!!  natom=number of atoms in cell.
!!  nfft=(effective) number of FFT grid points (for this processor)
!!  nkpt=number of k points.
!!  npwarr(nkpt)=number of planewaves in basis at this k point
!!  nsppol=1 for unpolarized, 2 for spin-polarized
!!  nspden=number of density components
!!  nsym=number of symmetries in space group
!!  ntypat=number of types of atoms in unit cell.
!!  occ(mband*nkpt*nsppol)=occupation number for each band (usually 2) for each k.
!!  Pawtab(Psps%ntypat*Psps%usepaw) <type(pawtab_type)>=paw tabulated starting data
!!  Pawfgr<pawfgr_type>=fine grid parameters and related data
!!  prtvol=control print volume and debugging output
!!  Psps <type(pseudopotential_type)>=variables related to pseudopotentials
!!  rprimd(3,3)=dimensional primitive translations for real space (bohr)
!!  Wffnow=information about wf disk file
!!  vtrial(nfft,nspden)=the trial potential
!!  xred(3,natom)=reduced dimensionless atomic coordinates
!!
!! OUTPUT
!!  Output is written on file.
!!  ierr=Status error.
!!
!! NOTES
!! * The routine can be time consuming (in particular when computing
!!   <G|H|G_prim> elements for all (G, G_prim)) (kssform=1).
!!   So, it is recommended to call it once per run...
!!
!! * when kssform==1, the routine RE-computes all Hamiltonian terms.
!!   So it is equivalent to an additional electronic SC cycle.
!!   (This has no effect is convergence was reach...
!!   If not, eigenvalues/vectors may differs from the congugaste gradient ones)
!!
!! *  The KB form factors and derivatives are not calculated correctly if there are
!!    pseudos with more than one projector in an angular momentum channel.
!!
!! * In the ETSF output format (Dtset%accesswff == 3), the complete symmetry set
!!   is output. So, if reading programs need only the symmorphic symmetries, they
!!   will need to remove themselves the non-symmorphic ones.
!!
!! * There exists two file formats:
!!    kssform==1 diagonalized file _KSS in real(dp) is generated.
!!    kssform==3 same as kssform=1 but the wavefunctions are not diagonalized
!!               (they are taken from conjugate-gradient ones)
!!    Old kssform=0 and kssform=2 are obsolete and no longer available
!!
!! TESTS
!! * ETSF_IO output is tested in tests/etsf_io/t02.
!!
!! TODO
!! * Rewrite the parallel part in particular the exchange of data between master and
!!   the node taking care of (k,s).
!!
!! PARENTS
!!      outscfcv
!!
!! CHILDREN
!!      clsopn,cprj_alloc,cprj_copy,cprj_exch,cprj_free,dsksta
!!      etsf_io_low_close,get_kg,hdr_skip,init_ddiago_ctl,k2gamma_centered
!!      ks_ddiago,memkss,merge_and_sort_kg,remove_inversion,rwwf,timab
!!      write_kss_header,write_kss_wfgk,wrtout,xbarrier_mpi,xcomm_init
!!      xexch_mpi
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

#include "abi_common.h"

subroutine outkss(Dtfil,Dtset,ecut,gmet,gprimd,Hdr,&
& kssform,mband,mcg,mcprj,mgfft,mkmem,MPI_enreg,mpsang,mpw,natom,&
& nfft,nkpt,npwarr,nspden,nsppol,nsym,ntypat,occ,Pawtab,Pawfgr,Paw_ij,&
& prtvol,Psps,rprimd,Wffnow,vtrial,xred,cg,usecprj,Cprj,eigen,ierr)

 use m_profiling

 use defs_basis
 use defs_datatypes
 use defs_abitypes
 use defs_wvltypes
 use m_xmpi
 use m_errors
 use m_wffile
#if defined HAVE_TRIO_ETSF_IO
 use etsf_io
#endif

 use m_io_tools,         only : get_unit
 !$use m_numeric_tools,  only : bisect
 use m_gsphere,          only : merge_and_sort_kg, table_gbig2kg, get_kg
 use m_io_kss,           only : write_kss_wfgk, write_kss_header, k2gamma_centered
 use m_hamiltonian,      only : ddiago_ctl_type, init_ddiago_ctl
 use m_linalg_interfaces

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'outkss'
 use interfaces_14_hidewrite
 use interfaces_18_timing
 use interfaces_42_geometry
 use interfaces_44_abitypes_defs
 use interfaces_51_manage_mpi
 use interfaces_57_iovars
 use interfaces_59_io_mpi
 use interfaces_67_common
!End of the abilint section

 implicit none

!Arguments ------------------------------------
!scalars
 integer,intent(in) :: kssform,mband,mcg,mcprj,mgfft,mkmem,mpsang,mpw,natom,usecprj
 integer,intent(in) :: nfft,nkpt,nsppol,nspden,nsym,ntypat,prtvol
 integer,intent(out) :: ierr
 real(dp),intent(in) :: ecut
 type(MPI_type),intent(inout) :: MPI_enreg
 type(Datafiles_type),intent(in) :: Dtfil
 type(Dataset_type),intent(in) :: Dtset
 type(Hdr_type),intent(inout) :: Hdr
 type(Pseudopotential_type),intent(in) :: Psps
 type(Wffile_type),intent(inout) :: Wffnow
 type(pawfgr_type), intent(in) :: Pawfgr
!arrays
 integer,intent(in),target :: npwarr(nkpt)
 real(dp),intent(in) :: gmet(3,3),gprimd(3,3),occ(mband*nkpt*nsppol)
 real(dp),intent(in) :: rprimd(3,3)
 real(dp),intent(inout) :: vtrial(nfft,nspden)
 real(dp),intent(in) :: xred(3,natom)
 real(dp),intent(in) :: cg(2,mcg),eigen(mband*nkpt*nsppol)
 type(Cprj_type),intent(in) :: Cprj(natom,mcprj*usecprj)
 type(Pawtab_type),intent(in) :: Pawtab(Psps%ntypat*Psps%usepaw)
 type(paw_ij_type),intent(in) :: Paw_ij(natom*Psps%usepaw)

!Local variables-------------------------------
!scalars
 integer,parameter :: tim_rwwf=0
 integer,parameter :: bufnb=20
 integer :: untkss,onband_diago
 integer :: bdtot_index,i,iatom,ib,ibp,accesswff
 integer :: ibsp,ibsp1,ibsp2,ibg,ig,ii,ikpt
 integer :: master,receiver,sender,spinor_shift1,shift
 integer :: ishm,ispinor,isppol,itypat,istwf_k,my_rank,j
 integer :: k_index,maxpw,mcg_disk,mproj,n1,n2,n2dim,n3,n4,n5,n6,nband_k
 integer :: nbandkss_k,nbandksseff,nbase,nprocs,npw_k,onpw_k,npwkss
 integer :: nrst1,nrst2,nsym2,ntemp,pinv,sizepw,spaceComm,comm_self
 integer :: pad1,pad2
 integer :: bufrt,bufsz
 real(dp) :: cinf=1.0e24,csup=zero,einf=1.0e24,esup=zero
 real(dp) :: norm,cfact,ecut_eff
 logical :: do_diago,found,ltest,lhack 
 logical,parameter :: skip_test_ortho=.FALSE.
 character(len=500) :: msg
 character(len=80) :: frmt1,frmt2
 character(len=10) :: stag(2)=(/'          ','          '/)
!arrays
 integer :: nbandkssk(nkpt)
 integer,pointer :: symrel2(:,:,:)
 integer,pointer :: gbig(:,:)
 integer,allocatable :: kg_dum(:,:)
 integer,pointer :: shlim(:)
 integer,pointer :: kg_k(:,:)
 integer,allocatable :: dimlmn(:)
 real(dp) :: ovlp(2),kpoint(3),tsec(2)
 real(dp),pointer :: tnons2(:,:)
 real(dp),allocatable :: cg_disk(:,:)
 real(dp),allocatable :: eig_dum(:),ene(:)
 real(dp),pointer :: eig_ene(:),eig_vec(:,:,:)
 real(dp),allocatable :: occ_dum(:)
 real(dp),allocatable :: occ_k(:)
 real(dp),allocatable,target :: wfg(:,:,:)
 real(dp),pointer :: ug1(:,:),ug2(:,:)
 type(Cprj_type),allocatable :: Cprjnk_k(:,:)
 type(Cprj_type),pointer :: Cprj_diago_k(:,:)
 type(ddiago_ctl_type) :: Diago_ctl
#if defined HAVE_TRIO_ETSF_IO
 logical :: lstat
 type(etsf_io_low_error) :: Error
#endif
! *********************************************************************

 DBG_ENTER("COLL")

 call timab(933,1,tsec) ! outkss
 call timab(934,1,tsec) ! outkss(Gsort+hd)

 call xcomm_init(MPI_enreg,spaceComm)
 my_rank = xcomm_rank(spaceComm)
 nprocs  = xcomm_size(spaceComm)
 master=0

 accesswff = Dtset%accesswff

 nullify(eig_ene)
 nullify(eig_vec)
 nullify(Cprj_diago_k)

!MG: since in seq case MPI_enreg%proc_distrb is not defined
!we hack a bit the data type in order to get rid of MPI preprocessing options.
!The previous status of %proc_distrb is restored before exiting.
!Note that in case of seq run MPI_enreg%proc_distrb is nullified at the very beginning of abinit.F90
!
!FIXME this is a design flaw that should be solved: proc_distrb should always
!be allocated and filled with my_rank in case of sequential run otherwise checks like
!if (nprocs>1.and.MPI_enreg%proc_distrb(ii)==me) leads to SIGFAULT under gfortran.
!as the second array is not allocated.
 lhack=.FALSE.
 if (nprocs==1) then
   ltest=ASSOCIATED(MPI_enreg%proc_distrb)
   if (.not.ltest) then
     ABI_ALLOCATE(MPI_enreg%proc_distrb,(nkpt,mband,nsppol))
     MPI_enreg%proc_distrb=my_rank
     lhack=.TRUE.
   end if
   ltest=ALL(MPI_enreg%proc_distrb==my_rank)
   ABI_CHECK(ltest,'wrong values in %proc_distrb')
 end if
!
!============================
!==== Perform some tests ====
!============================
 ierr=0

 if (kssform==3) then
   write(msg,'(a,70("="),4a)')ch10,ch10,&
&   ' Calculating and writing out Kohn-Sham electronic Structure file',ch10, &
&   ' Using conjugate gradient wavefunctions and energies (kssform=3)'
 else if (kssform==1) then
   write(msg,'(a,70("="),4a,i1,a)') ch10,ch10, &
&   ' Calculating and writing out Kohn-Sham electronic Structure file',ch10, &
&   ' Using diagonalized wavefunctions and energies (kssform=',kssform,')'
 else
   write(msg,'(a,i0,2a)')&
&   " Unsupported value for kssform: ",kssform,ch10,&
&   "  Program does not stop but _KSS file will not be created..."
   ierr=ierr+1
 end if
 call wrtout(std_out,msg,'COLL')
 call wrtout(ab_out,msg,'COLL')
!
!* Check whether nband is constant in metals
 if ( (Dtset%occopt>=2.and.Dtset%occopt<=8) .and. (ANY(Dtset%nband(1:nkpt*nsppol)/=Dtset%nband(1))) ) then
   write(msg,'(3a,i4,a,i3,a,i4,3a)')&
&   ' The number of bands must be the same for all k-points ',ch10,&
&   ' but nband(1)=',Dtset%nband(1),' is different of nband(',&
&   ikpt+(isppol-1)*nkpt,')=',Dtset%nband(ikpt+(isppol-1)*nkpt),'.',ch10,&
&   '  Program does not stop but _KSS file will not be created...'
   MSG_WARNING(msg)
   ierr=ierr+1
 end if
!* istwfk must be 1 for each k-point
 if (ANY(Dtset%istwfk(1:nkpt)/=1).and.kssform/=3) then
   write(msg,'(7a)')&
&   ' istwfk/=1 not allowed when kssform/=3 :',ch10,&
&   ' States output not programmed for time-reversal symmetry.',ch10,&
&   ' Action : change istwfk in input file (put it to 1 for all kpt).',ch10,&
&   ' Program does not stop but _KSS file will not be created...'
   MSG_WARNING(msg)
   ierr=ierr+1
 end if
!* Check spin-orbit
 if (Psps%mpssoang/=mpsang) then
   write(msg,'(3a)')&
&   ' Variable mpspso should be 1 !',ch10,&
&   ' Program does not stop but _KSS file will not be created...'
   MSG_WARNING(msg)
   ierr=ierr+1
 end if
!* Check mproj
 mproj=MAXVAL(Psps%indlmn(3,:,:))
 if (mproj>1.and.Psps%usepaw==0) then ! TODO One has to deriver the expression for [Vnl,r], in particular HGH and GTH psps
   write(msg,'(8a)')ch10,&
&   ' outkss : COMMENT - ',ch10,&
&   ' At least one NC pseudopotential has more that one projector per angular channel',ch10,&
&   ' Note that inclvkb==0 should be used in screening, since the evaluation of the commutator',ch10,&
&   ' for this particular case is not implemented yet'
   call wrtout(std_out,msg,'COLL') ; call wrtout(ab_out,msg,'COLL')
 end if
!* Check max angular momentum
 if (MAXVAL(Psps%indlmn(1,:,:))+1 >= 5) then
   write(msg,'(3a)')&
&   ' Pseudopotentials with f-projectors not implemented',ch10,&
&   ' Program does not stop but _KSS file will not be created...'
   MSG_WARNING(msg)
   ierr=ierr+1
 end if
!* Check useylm
 if (Psps%useylm/=0.and.Psps%usepaw==0) then
   write(msg,'(3a)')&
&   ' The present version of outkss does not work with useylm/=0 !',ch10,&
&   ' Program does not stop but _KSS file will not be created...'
   MSG_WARNING(msg)
   ierr=ierr+1
 end if
!* Check PAW and kssform value
 if (Psps%usepaw/=0) then
   if (nprocs>1.and.kssform==1) then
     write(msg,'(3a)')&
&     ' Parallel PAW with kssform=1, not yet allowed',ch10,&
&     ' Program does not stop but _KSS file will not be created...'
     MSG_WARNING(msg)
     ierr=ierr+1
   end if
   if (kssform==3.and.usecprj/=1) then
     write(msg,'(3a)')&
&     ' If PAW and kssform=3, usecprj must be 1',ch10,&
&     ' Program does not stop but _KSS file will not be created...'
     MSG_WARNING(msg)
     ierr=ierr+1
   end if
   if (mkmem==0) then
     write(msg,'(3a)')&
&     ' PAW with mkmem==0 not yet implemented ',ch10,&
&     ' Program does not stop but _KSS file will not be created...'
     MSG_WARNING(msg)
     ierr=ierr+1
   end if
 end if
!* Check parallelization
 if (MPI_enreg%paralbd/=0) then
   write(msg,'(3a)')&
&   ' outkss cannot be used with parallelization on bands (paralbd/=0) !',ch10,&
&   ' Program does not stop but _KSS file will not be created...'
   MSG_WARNING(msg)
   ierr=ierr+1
 end if
 if (MPI_enreg%paral_spin/=0) then
   write(msg,'(3a)')&
&   ' outkss cannot be used yet with parallelization on nspinors !',ch10,&
&   ' Program does not stop but _KSS file will not be created...'
   MSG_WARNING(msg)
   ierr=ierr+1

 endif
 if (ierr/=0) then
   write(msg,'(3a)')&
&   ' outkss: Not allowed options found !',ch10,&
&   ' Program does not stop but _KSS file will not be created...'
   call wrtout(std_out,msg,'COLL')
   call wrtout(ab_out,msg,'COLL')
   write(msg,'(a)')&
&   ' outkss: see the log file for more information.'
   call wrtout(ab_out,msg,'COLL')
   RETURN ! Houston we have a problem!
 end if
!
!Estimate required memory in case of diagonalization.
!TODO to be modified to take into account the case nsppol=2
 if (kssform/=3) then
   call memkss(mband,mgfft,mkmem,MPI_enreg,mproj,Psps%mpssoang,mpw,natom,Dtset%ngfft,nkpt,dtset%nspinor,nsym,ntypat)
 end if
!
!=== Initialize some variables ===
 if (nsppol==2) stag(:)=(/'SPIN UP:  ','SPIN DOWN:'/)
 n1=Dtset%ngfft(1); n2=Dtset%ngfft(2); n3=Dtset%ngfft(3)
 n4=Dtset%ngfft(4); n5=Dtset%ngfft(5); n6=Dtset%ngfft(6)
 ecut_eff = ecut * Dtset%dilatmx**2  ! Use ecut_eff instead of ecut_eff since otherwise
!one cannot restart from a previous density file
 sizepw=2*mpw ; do_diago=(kssform/=3)
 ABI_ALLOCATE(dimlmn,(natom*Psps%usepaw))
 if (Psps%usepaw==1) then
   do iatom=1,natom
     itypat=Dtset%typat(iatom)
     dimlmn(iatom)=Pawtab(itypat)%lmn_size
   end do
 end if
!
!============================================================
!=== Prepare set containing all G-vectors sorted by stars ===
!============================================================
 write(msg,'(2a)')ch10,' Sorting g-vecs for an output of states on an unique "big" PW basis.'
 call wrtout(std_out,msg,'COLL')
!
!=== Analyze symmetry operations ===
 if (Dtset%symmorphi==0) then  ! Old (Obsolete) implementation: Suppress inversion from symmetries list:
   nullify(symrel2,tnons2)
   call remove_inversion(nsym,Dtset%symrel,Dtset%tnons,nsym2,symrel2,tnons2,pinv)
   if (ANY(ABS(tnons2(:,1:nsym2))>tol8)) then
     write(msg,'(3a)')&
&     ' Non-symmorphic operations still remain in the symmetries list ',ch10,&
&     ' Program does not stop but _KSS file will not be created...'
     MSG_WARNING(msg)
     ierr=ierr+1 ; RETURN
   end if
 else if (Dtset%symmorphi==1) then
!  If in the input file symmorphi==1 all the symmetry operations are retained:
!  both identity and inversion (if any) as well as non-symmorphic operations.
   nsym2=nsym ; pinv=1
   ABI_ALLOCATE(symrel2,(3,3,nsym))
   ABI_ALLOCATE(tnons2,(3,nsym))
   symrel2(:,:,:)=Dtset%symrel(:,:,1:nsym)
   tnons2(:,:)   =Dtset%tnons(:,1:nsym)
 else
   write(msg,'(a,i4,3a)')&
&   ' symmorphi = ',Dtset%symmorphi,' while it must be 0 or 1',ch10,&
&   ' Program does not stop but KSS file will not be created...'
   MSG_WARNING(msg)
   ierr=ierr+1 ; RETURN
 end if
!
!===================================================================
!==== Merge the set of k-centered G-spheres into a big set gbig ====
!===================================================================
!* Vectors in gbig are ordered by shells
!
 nullify(gbig,shlim)
 call merge_and_sort_kg(nkpt,Dtset%kptns,ecut_eff,nsym2,pinv,symrel2,gprimd,gbig,prtvol,shlim_p=shlim)

 nbase = SIZE(shlim)   ! Number of independent G in the big sphere.
 maxpw = shlim(nbase)  ! Total number of G"s in the big sphere.
!
!* Determine optimal number of bands and G"s to be written.
 npwkss=Dtset%npwkss
 if ((npwkss==0).or.(npwkss>=maxpw)) then
   npwkss=maxpw
   write(msg,'(5a)')&
&   ' Since the number of g''s to be written on file',ch10,&
&   ' was 0 or too large, it has been set to the max. value.,',ch10,&
&   ' computed from the union of the sets of G vectors for the different k-points.'
   call wrtout(std_out,msg,'COLL')
 end if

 ishm=0
 do ii=1,nbase
   if (shlim(ii)<=npwkss) then
     ishm=ii
   else
     EXIT
   end if
 end do
!! ishm=bisect(shlim,npwkss)

 if (shlim(ishm)/=npwkss) then
   nrst1=shlim(ishm)
   nrst2=MIN0(shlim(MIN0(ishm+1,nbase)),maxpw)
   if (IABS(npwkss-nrst2)<IABS(npwkss-nrst1)) nrst1=nrst2
   npwkss=nrst1
   if (shlim(ishm)<npwkss) ishm=ishm+1
   write(msg,'(3a)')&
&   ' The number of G''s to be written on file is not a whole number of stars ',ch10,&
&   ' the program set it to the nearest star limit.'
   call wrtout(std_out,msg,'COLL')
 end if

 write(msg,'(a,i5)')' Number of g-vectors written on file is: ',npwkss
 call wrtout(std_out,msg,'COLL')
!
!=== Check on the number of stored bands ===
 if (do_diago) then

   if (Dtset%nbandkss==-1.or.Dtset%nbandkss>=maxpw) then
     nbandkssk(1:nkpt)=npwarr(1:nkpt)
     write(msg,'(6a)')ch10,&
&     ' Since the number of bands to be computed was (-1) or',ch10,&
&     ' too large, it has been set to the max. value. allowed for each k,',ch10,&
&     ' thus, the minimum of the number of plane waves for each k point.'
     call wrtout(std_out,msg,'COLL')
   else
     nbandkssk(1:nkpt)=Dtset%nbandkss
     found=.FALSE.
     do ikpt=1,nkpt
       if (Dtset%nbandkss>npwarr(ikpt)) then
         nbandkssk(ikpt)=npwarr(ikpt)
         found=.TRUE.
       end if
     end do
     if (found) then
       write(msg,'(7a)')&
&       ' The value choosen for the number of bands in file',ch10,&
&       ' (nbandkss) was greater than at least one number of plane waves ',ch10,&
&       ' for a given k-point (npw_k).',ch10,' It has been modified consequently.'
       MSG_WARNING(msg)
     end if
   end if
   found=.FALSE.
   do ikpt=1,nkpt
     if (nbandkssk(ikpt)>npwkss) then
       nbandkssk(ikpt)=npwkss
       found=.TRUE.
     end if
   end do
   if (found) then
     write(msg,'(5a)')&
&     ' The number of bands to be computed (for one k) was',ch10,&
&     ' greater than the number of g-vectors to be written.',ch10,&
&     ' It has been modified consequently.'
     MSG_WARNING(msg)
   end if
   nbandksseff=MINVAL(nbandkssk)

 else ! .not. do_diago
   do ikpt=1,nkpt
     do isppol=1,nsppol
       nbandkssk(ikpt)=Dtset%nband(ikpt+(isppol-1)*nkpt)
     end do
   end do
   nbandksseff=MINVAL(nbandkssk)
   if (Dtset%nbandkss>0 .and. Dtset%nbandkss<nbandksseff) then
     write(msg,'(a,i5,a,i5,2a)')&
&     ' Number of bands calculated=',nbandksseff,', greater than nbandkss=',Dtset%nbandkss,ch10,&
&     ' will write nbandkss bands on the KSS file'
     MSG_COMMENT(msg)
     nbandksseff=Dtset%nbandkss
   end if
 end if

 write(msg,'(a,i5)')' Number of bands written on file is: ',nbandksseff
 call wrtout(std_out,msg,'COLL')

 found= ANY(nbandkssk(1:nkpt)<npwarr(1:nkpt))

 if (do_diago) then
   if (found) then
     write(msg,'(6a)')ch10,&
&     ' Since the number of bands to be computed',ch10,&
&     ' is less than the number of G-vectors found,',ch10,&
&     ' the program will perform partial diagonalizations.'
   else
     write(msg,'(6a)')ch10,&
&     ' Since the number of bands to be computed',ch10,&
&     ' is equal to the nb of G-vectors found for each k-pt,',ch10,&
&     ' the program will perform complete diagonalizations.'
   end if
   call wrtout(std_out,msg,'COLL')
 end if
!
!==========================================================================
!=== Open KSS file for output, write header with dimensions and kb sign ===
!==========================================================================
!
!* Output required disk space.
 call dsksta(ishm,Psps%usepaw,nbandksseff,mpsang,natom,ntypat,npwkss,nkpt,dtset%nspinor,nsppol,nsym2,dimlmn)

 if (my_rank==master) then
   call write_kss_header(dtfil%fnameabo_kss,npwkss,ishm,nbandksseff,mband,nsym2,symrel2,tnons2,occ,gbig,shlim,&
&   Dtset,Hdr,Psps,accesswff,untkss)
 end if

 ABI_DEALLOCATE(shlim)

 if (     do_diago) msg = ' Diagonalized eigenvalues'
 if (.not.do_diago) msg = ' Conjugate gradient eigenvalues'
 call wrtout(ab_out,msg,'COLL')

 if (Dtset%enunit==1) then
   msg='   k    eigenvalues [eV]'
 else
   msg='   k    eigenvalues [Hartree]'
 end if
 call wrtout(ab_out,msg,'COLL')
!
!=== Prepare WF file for reading ===
 if ((.not.do_diago).and.mkmem==0) then
   mcg_disk=mpw*dtset%nspinor*mband
   ABI_ALLOCATE(eig_dum,(mband))
   ABI_ALLOCATE(kg_dum,(3,0))
   ABI_ALLOCATE(occ_dum,(mband))
   ABI_ALLOCATE(cg_disk,(2,mcg_disk))
   call clsopn(Wffnow)
   call hdr_skip(Wffnow,ierr)
!  Define offsets, in case of MPI I/O
!  call WffKg(Wffnow,0)
!  call xdefineOff(0,Wffnow,MPI_enreg,Dtset%nband,npwarr,dtset%nspinor,nsppol,nkpt)
 end if
 call timab(934,2,tsec) ! outkss(Gsort+hd)
!

 k_index=0; bdtot_index=0; ibg=0

 do isppol=1,nsppol ! Loop over spins
!
   do ikpt=1,nkpt ! Loop over k-points.
     call timab(935,1,tsec) ! outkss(k-Loop)

     nband_k   =Dtset%nband(ikpt+(isppol-1)*nkpt)
     npw_k     =npwarr(ikpt)
     istwf_k   =Dtset%istwfk(ikpt)
     kpoint    =Dtset%kptns(:,ikpt)
     nbandkss_k=nbandkssk(ikpt)

     nullify(kg_k) ! Get G-vectors, for this k-point.
     call get_kg(kpoint,istwf_k,ecut_eff,gmet,onpw_k,kg_k)
     ABI_CHECK(onpw_k==npw_k,"Mismatch in npw_k")
!
!    ============================================
!    ==== Parallelism over k-points and spin ====
!    ============================================
     if (MPI_enreg%proc_distrb(ikpt,1,isppol)==my_rank) then

       write(msg,'(2a,i3,3x,a)')ch10,' k-point ',ikpt,stag(isppol)
       call wrtout(std_out,msg,'PERS')

       if (do_diago) then ! Direct diagonalization of the KS Hamiltonian.
         if (associated(eig_ene))  then
           ABI_DEALLOCATE(eig_ene)
         end if
         if (associated(eig_vec))  then
           ABI_DEALLOCATE(eig_vec)
         end if
         comm_self = xmpi_self

         call timab(936,1,tsec)

         call init_ddiago_ctl(Diago_ctl,"Vectors",isppol,dtset%nspinor,ecut_eff,Dtset%kptns(:,ikpt),Dtset%nloalg,gmet,&
&         nband_k=nbandkssk(ikpt),effmass=Dtset%effmass,istwf_k=Dtset%istwfk(ikpt),prtvol=Dtset%prtvol)

         call ks_ddiago(Diago_ctl,nbandkssk(ikpt),Dtset%nfft,mgfft,Dtset%ngfft,natom,&
&         Dtset%typat,nfft,dtset%nspinor,nspden,nsppol,ntypat,Pawtab,Pawfgr,Paw_ij,&
&         Psps,rprimd,vtrial,xred,onband_diago,eig_ene,eig_vec,Cprj_diago_k,comm_self,ierr)

         call timab(936,2,tsec)
       end if

     end if ! END of kpt+spin parallelism.
!
!    ===========================================================
!    ==== Transfer data between master and the working proc ====
!    ===========================================================
     call timab(937,1,tsec) !outkss(MPI_exch)
     if (nprocs==1) then

       if (Psps%usepaw==1) then ! Copy projectors for this k-point
         ABI_ALLOCATE(Cprjnk_k,(natom,nband_k*dtset%nspinor))
         call cprj_alloc(Cprjnk_k,0,dimlmn)
         if (kssform==3) then
           call cprj_copy(Cprj(:,ibg+1:ibg+dtset%nspinor*nband_k),Cprjnk_k)
         else
           MSG_WARNING("Here I have to use onband_diago") !FIXME
           call cprj_copy(Cprj_diago_k,Cprjnk_k)
         end if
       end if

     else !parallel case

       receiver=master; sender=MPI_enreg%proc_distrb(ikpt,1,isppol)

       bufsz=nbandksseff/bufnb; bufrt=nbandksseff-bufnb*bufsz

       if (my_rank==receiver.or.my_rank==sender) then

         if (do_diago.and.(my_rank==receiver.and.my_rank/=sender)) then ! Alloc arrays if not done yet.
           ABI_ALLOCATE(eig_ene,(npw_k*dtset%nspinor))
           ABI_ALLOCATE(eig_vec,(2,npw_k*dtset%nspinor,nbandkssk(ikpt)))
         end if

         if (.not.do_diago) then

           ABI_ALLOCATE(eig_vec,(2,npw_k*dtset%nspinor,nbandkssk(ikpt)))

           if (my_rank==sender) then
             do ib=1,nbandksseff
               shift = k_index + (ib-1)*npw_k*dtset%nspinor
               do ig=1,npw_k*dtset%nspinor
                 eig_vec(:,ig,ib)=cg(:,ig+shift)
               end do
             end do
           end if
!
!          In case of PAW and kssform==3, retrieve matrix elements of the PAW projectors for this k-point
!          TODO add the mkmem==0 case
           if (Psps%usepaw==1) then
             ABI_ALLOCATE(Cprjnk_k,(natom,nband_k*dtset%nspinor))
             call cprj_alloc(Cprjnk_k,0,dimlmn)
             if (my_rank==sender) then
               if (kssform==3) then
                 call cprj_copy(Cprj(:,ibg+1:ibg+dtset%nspinor*nband_k),Cprjnk_k)
               else
                 MSG_WARNING("Here I have to use onband_diago") !FIXME
                 call cprj_copy(Cprj_diago_k,Cprjnk_k)
               end if
             end if
             if (sender/=receiver) then
               n2dim=nband_k*dtset%nspinor
               call cprj_exch(natom,n2dim,dimlmn,0,Cprjnk_k,Cprjnk_k,sender,receiver,spaceComm,ierr)
             end if
           end if ! usepaw

         else ! do_diago
           call xexch_mpi(eig_ene,nbandksseff,sender,eig_ene,receiver,spaceComm,ierr)
         end if

!        Exchange eigenvectors.
         if (bufsz>0) then
           do i=0,bufnb-1
             call xexch_mpi(eig_vec(:,:,i*bufsz+1:(i+1)*bufsz),2*npw_k*dtset%nspinor*bufsz,&
&             sender,eig_vec(:,:,i*bufsz+1:(i+1)*bufsz),receiver,spaceComm,ierr)
           end do
         end if
         if (bufrt>0) then
           call xexch_mpi(eig_vec(:,:,bufnb*bufsz+1:bufnb*bufsz+bufrt),2*npw_k*dtset%nspinor*bufrt,&
&           sender,eig_vec(:,:,bufnb*bufsz+1:bufnb*bufsz+bufrt),receiver,spaceComm,ierr)
         end if

       end if
     end if !nprocs > 1
     call timab(937,2,tsec) !outkss(MPI_exch)

     call timab(938,1,tsec) !outkss(write)

     if (my_rank==master) then ! Prepare data for writing on disk.
       ABI_ALLOCATE(ene,(nbandksseff))
       ABI_ALLOCATE(wfg,(2,npwkss*dtset%nspinor,nbandksseff))
       ene=zero; wfg=zero

       if (.not.do_diago) then
         ene(1:nbandksseff)=eigen(1+bdtot_index:nbandksseff+bdtot_index)

         if (mkmem==0) then
           call rwwf(cg_disk,eig_dum,0,0,0,ikpt,isppol,kg_dum,mband,mcg_disk,MPI_enreg,&
&           nband_k,nband_k,npw_k,dtset%nspinor,occ_dum,-2,0,tim_rwwf,Wffnow)

           call k2gamma_centered(kpoint,npw_k,istwf_k,ecut_eff,kg_k,npwkss,dtset%nspinor,nbandksseff,Dtset%ngfft,gmet,&
&           MPI_enreg,gbig,wfg,icg=0,cg=cg_disk)
         else
           if (nprocs>1) then
             call k2gamma_centered(kpoint,npw_k,istwf_k,ecut_eff,kg_k,npwkss,dtset%nspinor,nbandksseff,Dtset%ngfft,gmet,&
&             MPI_enreg,gbig,wfg,eig_vec=eig_vec)
           else
             call k2gamma_centered(kpoint,npw_k,istwf_k,ecut_eff,kg_k,npwkss,dtset%nspinor,nbandksseff,Dtset%ngfft,gmet,&
&             MPI_enreg,gbig,wfg,icg=k_index,cg=cg)
           end if
         end if

       else ! Direct diagonalization.
         ene(1:nbandksseff)=eig_ene(1:nbandksseff)

!        FIXME: receiver does not know Diago_ctl%npw_k
         call k2gamma_centered(kpoint,npw_k,istwf_k,ecut_eff,kg_k,npwkss,dtset%nspinor,nbandksseff,Dtset%ngfft,gmet,&
&         MPI_enreg,gbig,wfg,eig_vec=eig_vec)

!        * Check diagonalized eigenvalues with respect to conjugate gradient ones
         ntemp=MIN(nbandksseff,nband_k)
         if (ANY(ABS(ene(1:ntemp)-eigen(1+bdtot_index:ntemp+bdtot_index))>tol3)) then
           write(msg,'(3a)')&
&           ' The diagonalized eigenvalues differ by more than 10^-3 Hartree',ch10,&
&           ' with respect to the conjugated gradient values.'
           MSG_WARNING(msg)
         end if
       end if
!
!      * Write out energies
       if (Dtset%enunit==1) then
         cfact=Ha_eV ; frmt1='(i4,4x,9(1x,f7.2))' ; frmt2='(8x,9(1x,f7.2))'
         write(msg,'(a,i3,3x,a)')' Eigenvalues in eV for ikpt= ',ikpt,stag(isppol)
       else
         cfact=one   ; frmt1='(i4,4x,9(1x,f7.4))' ; frmt2='(8x,9(1x,f7.4))'
         write(msg,'(a,i3,3x,a)')' Eigenvalues in Hartree for ikpt= ',ikpt,stag(isppol)
       end if
       call wrtout(std_out,msg,'COLL')

       write(msg,frmt1)ikpt,(ene(ib)*cfact,ib=1,MIN(9,nbandksseff))
       call wrtout(std_out,msg,'COLL')
       call wrtout(ab_out,msg,'COLL')

       if (nbandksseff>9) then
         do j=10,nbandksseff,9
           write(msg,frmt2) (ene(ib)*cfact,ib=j,MIN(j+8,nbandksseff))
           call wrtout(std_out,msg,'COLL')
           call wrtout(ab_out,msg,'COLL')
         end do
       end if

       if (skip_test_ortho) then ! Set this if to FALSE to skip test below
         einf=one; esup=one; cinf=zero; csup=zero
       else 
         !      
         ! Test on the normalization of wavefunctions.
         ibsp=0
         do ib=1,nbandksseff
           norm=zero
           do ispinor=1,dtset%nspinor
             ibsp=ibsp+1
             spinor_shift1=(ispinor-1)*npwkss
             ug1 => wfg(:,1+spinor_shift1:npwkss+spinor_shift1,ib)

             ovlp(1) =ddot(npwkss,ug1(1,:),1,ug1(1,:),1) + ddot(npwkss,ug1(2,:),1,ug1(2,:),1)
!            ovlp(2)=ddot(npwkss,ug1(1,:),1,ug1(2,:),1) - ddot(npwkss,ug1(2,:),1,ug1(1,:),1)
             if (Psps%usepaw==1) ovlp = ovlp &
&               + paw_overlap(Cprjnk_k(:,ibsp:ibsp),Cprjnk_k(:,ibsp:ibsp),Dtset%typat,Pawtab,&
&                             spinor_comm=MPI_enreg%comm_spin)
             norm = norm + DABS(ovlp(1))
           end do
           if (norm<einf) einf=norm
           if (norm>esup) esup=norm
         end do
!
!        Test on the orthogonalization of wavefunctions.
         do ib=1,nbandksseff
           pad1=(ib-1)*dtset%nspinor
           do ibp=ib+1,nbandksseff
             pad2=(ibp-1)*dtset%nspinor
             ovlp(:)=zero
             do ispinor=1,dtset%nspinor
               ibsp1=pad1+ispinor
               ibsp2=pad2+ispinor
               spinor_shift1=(ispinor-1)*npwkss
               ug1 => wfg(:,1+spinor_shift1:npwkss+spinor_shift1,ib )
               ug2 => wfg(:,1+spinor_shift1:npwkss+spinor_shift1,ibp)

               ovlp(1)=ddot(npwkss,ug1(1,:),1,ug2(1,:),1) + ddot(npwkss,ug1(2,:),1,ug2(2,:),1)
               ovlp(2)=ddot(npwkss,ug1(1,:),1,ug2(2,:),1) - ddot(npwkss,ug1(2,:),1,ug2(1,:),1)

               if (Psps%usepaw==1) ovlp= ovlp &
&                 + paw_overlap(Cprjnk_k(:,ibsp1:ibsp1),Cprjnk_k(:,ibsp2:ibsp2),Dtset%typat,Pawtab,&
&                               spinor_comm=MPI_enreg%comm_spin)
             end do
             norm = DSQRT(ovlp(1)**2+ovlp(2)**2)
             if (norm<cinf) cinf=norm
             if (norm>csup) csup=norm
           end do
         end do
       end if

       write(msg,'(a,i3,3x,a)')' Writing out eigenvalues/vectors for ikpt=',ikpt,stag(isppol)
       call wrtout(std_out,msg,'COLL')
!
!      * Write occupation numbers on std_out.
       ABI_ALLOCATE(occ_k,(MAX(nband_k,nbandksseff)))
       occ_k(1:nband_k)=occ(1+bdtot_index:nband_k+bdtot_index)
       if (nband_k < nbandksseff) occ_k(nband_k+1:nbandksseff)=zero

       write(msg,'(a,i3,3x,a)')' Occupation numbers for ikpt=',ikpt,stag(isppol)
       call wrtout(std_out,msg,'COLL')
       write(msg,'(i4,4x,9(1x,f7.4))')ikpt,(occ_k(ib),ib=1,MIN(9,nbandksseff))
       call wrtout(std_out,msg,'COLL')
       if (nbandksseff>9) then
         do j=10,nbandksseff,9
           write(msg,'(8x,9(1x,f7.4))') (occ_k(ib),ib=j,MIN(j+8,nbandksseff))
           call wrtout(std_out,msg,'COLL')
         end do
       end if
!
!      =================================================================
!      ==== Write wavefunctions, KB and PAW matrix elements on disk ====
!      =================================================================
       call write_kss_wfgk(untkss,ikpt,isppol,kpoint,dtset%nspinor,npwkss,npw_k,kg_k,&
&           nbandksseff,natom,Psps,ene,occ_k,rprimd,gbig,wfg,Cprjnk_k,accesswff)

       ABI_DEALLOCATE(occ_k)
       ABI_DEALLOCATE(ene)
       ABI_DEALLOCATE(wfg)

     end if ! my_rank==master
     call timab(938,2,tsec) !outkss(write)

     if (my_rank==master.or.my_rank==MPI_enreg%proc_distrb(ikpt,1,isppol)) then
       if (associated(eig_ene))  then
         ABI_DEALLOCATE(eig_ene)
       end if
       if (associated(eig_vec))  then
         ABI_DEALLOCATE(eig_vec)
       end if

       if (Psps%usepaw==1) then
         call cprj_free(Cprjnk_k)
         ABI_DEALLOCATE(Cprjnk_k)
       end if
     end if

     if (associated(kg_k))  then
       ABI_DEALLOCATE(kg_k)
     end if

!    if (MPI_enreg%paral_compil_kpt==1) then !cannot be used in seq run!
     if (MINVAL(ABS(MPI_enreg%proc_distrb(ikpt,:,isppol)-my_rank))==0) then
       k_index=k_index+npw_k*nband_k*dtset%nspinor
       ibg=ibg+dtset%nspinor*nband_k
     end if
     bdtot_index=bdtot_index+nband_k

     call xbarrier_mpi(spaceComm) ! FIXME this barrier is detrimental in the case of direct diago!

     call timab(935,2,tsec) !outkss(k-loop)
   end do ! ! End loop over k-points.
 end do ! spin

 write(msg,'(3a,f9.6,2a,f9.6,4a,f9.6,2a,f9.6,a)')&
& ' Test on the normalization of the wavefunctions',ch10,&
& '  min sum_G |a(n,k,G)| = ',einf,ch10,&
& '  max sum_G |a(n,k,G)| = ',esup,ch10,&
& ' Test on the orthogonalization of the wavefunctions',ch10,&
& '  min sum_G a(n,k,G)* a(n'',k,G) = ',cinf,ch10,&
& '  max sum_G a(n,k,G)* a(n'',k,G) = ',csup,ch10
 call wrtout(std_out,msg,'COLL')
 call wrtout(ab_out,msg,'COLL')

 ABI_DEALLOCATE(gbig)
 ABI_DEALLOCATE(symrel2)
 ABI_DEALLOCATE(tnons2)
 if (Psps%usepaw==1)  then
   ABI_DEALLOCATE(dimlmn)
 end if
 if ((.not.do_diago).and.(mkmem==0))  then
   ABI_DEALLOCATE(eig_dum)
   ABI_DEALLOCATE(kg_dum)
   ABI_DEALLOCATE(occ_dum)
   ABI_DEALLOCATE(cg_disk)
 end if
!
!* Close file
 if (my_rank==master) then
   if (accesswff==IO_MODE_FORTRAN) close(unit=untkss)
#if defined HAVE_TRIO_ETSF_IO
   if (accesswff==IO_MODE_ETSF) then
     call etsf_io_low_close(untkss, lstat, Error)
     ETSF_CHECK_ERROR(lstat,Error)
   end if
#endif
 end if

 if (associated(Cprj_diago_k)) then
   call cprj_free(Cprj_diago_k)
   ABI_DEALLOCATE(Cprj_diago_k)
 end if

 if (lhack)  then
   ABI_DEALLOCATE(MPI_enreg%proc_distrb)
 end if

 call xbarrier_mpi(spaceComm)

 DBG_EXIT("COLL")
 call timab(933,2,tsec) ! outkss

end subroutine outkss
!!***
