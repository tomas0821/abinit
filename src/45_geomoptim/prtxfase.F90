!{\src2tex{textfont=tt}}
!!****f* ABINIT/prtxfase
!!
!! NAME
!! prtxfase
!!
!! FUNCTION
!! Print the values of xcart (X), forces (F)
!! acell (A), Stresses (S), and energy (E)
!! All values come from the history hist
!! Also compute and print max and rms forces.
!! Also compute absolute and relative differences
!! with previous calculation
!!
!! COPYRIGHT
!! Copyright (C) 1998-2012 ABINIT group (DCA, XG, GMR)
!! This file is distributed under the terms of the
!! GNU General Public License, see ~abinit/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!! For the initials of contributors,
!! see ~abinit/doc/developers/contributors.txt .
!!
!! INPUTS
!! ab_mover<type ab_movetype>=Subset of dtset only related with
!!          |                 movement of ions and acell, contains:
!!          | dtion:  Time step
!!          ! natom:  Number of atoms
!!          | vis:    viscosity
!!          | iatfix: Index of atoms and directions fixed
!!          | amass:  Mass of ions
!! hist<type ab_movehistory>=Historical record of positions, forces
!!      |                    acell, stresses, and energies,
!!      |                    contains:
!!      | mxhist:  Maximun number of records
!!      | histA:   Historical record of acell(A) and rprimd(R)
!!      | histE:   Historical record of energy(E)
!!      | histEk:  Historical record of Ionic kinetic energy(Ek)
!!      | histT:   Historical record of time(T) (For MD or iteration for GO)
!!      | histR:   Historical record of rprimd(R)
!!      | histS:   Historical record of strten(S)
!!      | histV:   Historical record of velocity(V)
!!      | histXF:  Historical record of positions(X) and forces(F)
!! iout=unit number for printing
!!
!! OUTPUT
!!  (only writing)
!!
!! PARENTS
!!      mover
!!
!! CHILDREN
!!      gettag,wrtout
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

subroutine prtxfase(ab_mover,hist,iout,pos)

 use m_profiling

! define dp,sixth,third,etc...
use defs_basis
! type(ab_movetype), type(ab_movehistory)
use defs_mover

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'prtxfase'
 use interfaces_14_hidewrite
 use interfaces_45_geomoptim, except_this_one => prtxfase
!End of the abilint section

implicit none

!Arguments ------------------------------------
!scalars
type(ab_movetype),intent(in) :: ab_mover
type(ab_movehistory),intent(in) :: hist
integer,intent(in) :: iout
integer,intent(in) :: pos
!arrays

!Local variables-------------------------------
!scalars
integer :: jj,kk,unfixd,iprt
real(dp) :: val_max,val_rms,ucvol ! Values maximal and RMS, Volume of Unitary cell
real(dp) :: dEabs,dErel ! Diff of energy absolute and relative
real(dp) :: ekin
real(dp) :: angle(3),rmet(3,3)
character(len=80*(max(ab_mover%natom,3)+1)) :: message
character(len=18)   :: fmt1
logical :: prtallatoms
!arrays
logical :: atlist(ab_mover%natom)

! ***********************************************************

 fmt1='(a,a,1p,3e22.14)'

!###########################################################
!### 1. Organize list of atoms to print

 prtallatoms=.TRUE.
 do kk=1,ab_mover%natom
   if (ab_mover%prtatlist(kk)/=kk) prtallatoms=.FALSE.
 end do

 atlist(:)=.FALSE.
 do iprt=1,ab_mover%natom
   if (ab_mover%prtatlist(iprt)>0.and.ab_mover%prtatlist(iprt)<=ab_mover%natom) atlist(ab_mover%prtatlist(iprt))=.TRUE.
 end do

!write(iout,*) 'GAF_NATOM=',ab_mover%natom 

!###########################################################
!### 1. Positions

 write(message, '(a,a)' )&
& ch10,' Cartesian coordinates (xcart) [bohr]'
 call prtnatom(atlist,iout,message,ab_mover%natom,&
& prtallatoms,hist%histXF(:,:,1,hist%ihist))

 write(message, '(a)' )&
& ' Reduced coordinates (xred)'
 call prtnatom(atlist,iout,message,ab_mover%natom,&
& prtallatoms,hist%histXF(:,:,2,hist%ihist))


!###########################################################
!### 2. Forces

 if(pos==mover_AFTER)then
!  Compute max |f| and rms f,
!  EXCLUDING the components determined by iatfix
   val_max=0.0_dp
   val_rms=0.0_dp
   unfixd=0
   do kk=1,ab_mover%natom
     do jj=1,3
       if (ab_mover%iatfix(jj,kk) /= 1) then
         unfixd=unfixd+1
         val_rms=val_rms+hist%histXF(jj,kk,3,hist%ihist)**2
         val_max=max(val_max,abs(hist%histXF(jj,kk,3,hist%ihist)**2))
       end if
     end do
   end do
   if ( unfixd /= 0 ) val_rms=sqrt(val_rms/dble(unfixd))

   write(message, '(a,1p,2e12.5,a)' ) &
&   ' Cartesian forces (fcart) [Ha/bohr]; max,rms=',&
&   sqrt(val_max),val_rms,' (free atoms)'
   call prtnatom(atlist,iout,message,ab_mover%natom,&
&   prtallatoms,hist%histXF(:,:,3,hist%ihist))


   write(message, '(a)' )&
&   ' Reduced forces (fred)'
   call prtnatom(atlist,iout,message,ab_mover%natom,&
&   prtallatoms,hist%histXF(:,:,4,hist%ihist))

 end if

!###########################################################
!### 3. Velocities

!Only if the velocities are being used
 if (hist%isVused)then
!  Only if velocities are recorded in a history
   if (associated(hist%histV))then
!    Compute max |v| and rms v,
!    EXCLUDING the components determined by iatfix
     val_max=0.0_dp
     val_rms=0.0_dp
     unfixd=0
     do kk=1,ab_mover%natom
       do jj=1,3
         if (ab_mover%iatfix(jj,kk) /= 1) then
           unfixd=unfixd+1
           val_rms=val_rms+hist%histV(jj,kk,hist%ihist)**2
           val_max=max(val_max,abs(hist%histV(jj,kk,hist%ihist)**2))
         end if
       end do
     end do
     if ( unfixd /= 0 ) val_rms=sqrt(val_rms/dble(unfixd))

     write(message, '(a,1p,2e12.5,a)' ) &
&     ' Cartesian velocities (vel) [bohr*Ha/hbar]; max,rms=',&
&     sqrt(val_max),val_rms,' (free atoms)'
     call prtnatom(atlist,iout,message,ab_mover%natom,&
&     prtallatoms,hist%histV(:,:,hist%ihist))

!    Compute the ionic kinetic energy (no cell shape kinetic energy yet)
     ekin=0.0_dp
     do kk=1,ab_mover%natom
       do jj=1,3
!        Warning : the fixing of atoms is implemented in reduced
!        coordinates, so that this expression is wrong
         if (ab_mover%iatfix(jj,kk) == 0) then
           ekin=ekin+0.5_dp*ab_mover%amass(kk)*hist%histV(jj,kk,hist%ihist)**2
         end if
       end do
     end do
     write(message, '(a,1p,e22.14,a)' )&
&     ' Kinetic energy of ions (ekin) [Ha]=',&
&     ekin
     call wrtout(iout,message,'COLL')


   end if
 end if

!###########################################################
!### 3. ACELL

!Only if the acell is being used
 if (hist%isARused)then
!  Only if acell is recorded in a history
   if (associated(hist%histA))then

     write(message, '(a)' ) &
&     ' Scale of Primitive Cell (acell) [bohr]'
     write(message,fmt1)&
&     TRIM(message),ch10,&
&     hist%histA(:,hist%ihist)
     call wrtout(iout,message,'COLL')
   end if
 end if

!###########################################################
!### 4. RPRIMD

!Only if the acell is being used
 if (hist%isARused)then
!  Only if rprimd is recorded in a history
   if (associated(hist%histR))then
     write(message, '(a)' ) &
&     ' Real space primitive translations (rprimd) [bohr]'
     do kk=1,3
       write(message,fmt1)&
&       TRIM(message),ch10,&
&       hist%histR(:,kk,hist%ihist)
     end do
     call wrtout(iout,message,'COLL')
   end if
 end if

!###########################################################
!### 5. Unitary cell volume

 if (ab_mover%optcell/=0)then

   ucvol=hist%histR(1,1,hist%ihist)*&
&   (hist%histR(2,2,hist%ihist)*hist%histR(3,3,hist%ihist)-&
&   hist%histR(3,2,hist%ihist)*hist%histR(2,3,hist%ihist))+&
&   hist%histR(2,1,hist%ihist)*&
&   (hist%histR(3,2,hist%ihist)*hist%histR(1,3,hist%ihist)-&
&   hist%histR(1,2,hist%ihist)*hist%histR(3,3,hist%ihist))+&
&   hist%histR(3,1,hist%ihist)*&
&   (hist%histR(1,2,hist%ihist)*hist%histR(2,3,hist%ihist)-&
&   hist%histR(2,2,hist%ihist)*hist%histR(1,3,hist%ihist))

   write(message, '(a,1p,e22.14)' )&
&   ' Unitary Cell Volume (ucvol) [Bohr^3]=',&
&   ucvol
   call wrtout(iout,message,'COLL')

!  ###########################################################
!  ### 5. Angles and lengths

!  Compute real space metric.
   rmet = MATMUL(TRANSPOSE(hist%histR(:,:,hist%ihist)),hist%histR(:,:,hist%ihist))

   angle(1)=acos(rmet(2,3)/sqrt(rmet(2,2)*rmet(3,3)))/two_pi*360.0d0
   angle(2)=acos(rmet(1,3)/sqrt(rmet(1,1)*rmet(3,3)))/two_pi*360.0d0
   angle(3)=acos(rmet(1,2)/sqrt(rmet(1,1)*rmet(2,2)))/two_pi*360.0d0

   write(message, '(a,a)' ) &
&   ' Angles (23,13,12)= [degrees]'
   write(message,fmt1)&
&   TRIM(message),ch10,&
&   angle(:)
   call wrtout(iout,message,'COLL')

   write(message, '(a,a)' ) &
&   ' Lengths [Bohr]'
   write(message,fmt1)&
&   TRIM(message),ch10,&
&   sqrt(rmet(1,1)),sqrt(rmet(2,2)),sqrt(rmet(3,3))
   call wrtout(iout,message,'COLL')


!  ###########################################################
!  ### 5. Stress Tensor

   if(pos==mover_AFTER)then
!    Only if strten is recorded in a history
     if (associated(hist%histS))then

       write(message, '(a)' ) &
&       ' Stress tensor in cartesian coordinates (strten) [Ha/bohr^3]'

       write(message,fmt1)&
&       TRIM(message),ch10,&
&       hist%histS(1,hist%ihist),&
&       hist%histS(6,hist%ihist),&
&       hist%histS(5,hist%ihist)
       write(message,fmt1)&
&       TRIM(message),ch10,&
&       hist%histS(6,hist%ihist),&
&       hist%histS(2,hist%ihist),&
&       hist%histS(4,hist%ihist)
       write(message,fmt1)&
&       TRIM(message),ch10,&
&       hist%histS(5,hist%ihist),&
&       hist%histS(4,hist%ihist),&
&       hist%histS(3,hist%ihist)
       call wrtout(iout,message,'COLL')
     end if
   end if
 end if

!###########################################################
!### 6. Energy

 if(pos==mover_AFTER)then
   write(message, '(a,1p,e22.14)' )&
&   ' Total energy (etotal) [Ha]=',&
&   hist%histE(hist%ihist)

   if (hist%ihist>1)then
     dEabs=hist%histE(hist%ihist)-hist%histE(hist%ihist-1)
     dErel=2*dEabs/(abs(hist%histE(hist%ihist))+&
&     abs(hist%histE(hist%ihist-1)))
     write(message, '(a,a,a,a)' )&
&     TRIM(message),ch10,ch10,&
&     ' Difference of energy with previous step (new-old):'
     write(message, '(a,a,10a,a,1p,e12.5,a,10a,a,1p,e12.5)')&
&     TRIM(message),ch10,&
&     (' ',jj=1,10),' Absolute (Ha)=',dEabs,ch10,&
&     (' ',jj=1,10),' Relative     =',dErel
   end if
   call wrtout(iout,message,'COLL')
 end if

end subroutine prtxfase
!!***


!{\src2tex{textfont=tt}}
!!****f* ABINIT/gettag
!!
!! NAME
!! gettag
!!
!! FUNCTION
!! Set the tag associated to each atom,
!! 
!!
!! COPYRIGHT
!! Copyright (C) 1998-2012 ABINIT group (DCA, XG, GMR)
!! This file is distributed under the terms of the
!! GNU General Public License, see ~abinit/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!! For the initials of contributors,
!! see ~abinit/doc/developers/contributors.txt .
!!
!! INPUTS
!! prtallatoms = Logical for PRTint ALL ATOMS
!! atlist      = ATom LIST
!! index       = index for each atom
!! natom       = Number of ATOMs
!!
!! OUTPUT
!!  tag = The string to put for aech atom
!!
!! PARENTS
!!      prtxfase
!!
!! CHILDREN
!!      gettag,wrtout
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

subroutine gettag(atlist,index,natom,prtallatoms,tag)

 use m_profiling

! define dp,sixth,third,etc...
use defs_basis

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'gettag'
!End of the abilint section

implicit none

!Arguments ------------------------------------
!scalars
  logical,intent(in) :: prtallatoms
  logical,intent(in) :: atlist(natom)
  integer,intent(in) :: index
  integer,intent(in) :: natom
  character(len=7),intent(out)   :: tag

!Local variables -------------------------

! *********************************************************************
!The numbering will be from (1) to (9999)

 if (prtallatoms)then
   tag=''
 elseif (atlist(index)) then
   if (natom<10) then
     write(tag, '(a,I1.1,a)') ' (',index,')'
   elseif (natom<100) then
     write(tag, '(a,I2.2,a)') ' (',index,')'
   elseif (natom<1000) then
     write(tag, '(a,I3.3,a)') ' (',index,')'
   elseif (natom<10000) then
     write(tag, '(a,I4.4,a)') ' (',index,')'
   end if
 end if

end subroutine gettag
!!***

!!****f* ABINIT/prtnatom
!!
!! NAME
!! prtnatom
!!
!! FUNCTION
!! Print information for N atoms
!! 
!!
!! COPYRIGHT
!! Copyright (C) 1998-2012 ABINIT group (DCA, XG, GMR)
!! This file is distributed under the terms of the
!! GNU General Public License, see ~abinit/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!! For the initials of contributors,
!! see ~abinit/doc/developers/contributors.txt .
!!
!! INPUTS
!! prtallatoms = Logical for PRTint ALL ATOMS
!! atlist      = ATom LIST
!! index       = index for each atom
!! natom       = Number of ATOMs
!!
!! OUTPUT
!!  tag = The string to put for aech atom
!!
!! PARENTS
!!      prtxfase
!!
!! CHILDREN
!!      gettag,wrtout
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

#include "abi_common.h"


subroutine prtnatom(atlist,iout,message,natom,prtallatoms,thearray)

 use m_profiling

! define dp,sixth,third,etc...
use defs_basis

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'prtnatom'
 use interfaces_14_hidewrite
 use interfaces_45_geomoptim, except_this_one => prtnatom
!End of the abilint section

implicit none

!Arguments ------------------------------------
!scalars
  logical,intent(in) :: prtallatoms
  logical,intent(in) :: atlist(natom)
  integer,intent(in) :: iout
  integer,intent(in) :: natom
  character(len=80*(max(natom,3)+1)) :: message
!arrays
  real(dp) :: thearray(3,natom)

!Local variables-------------------------------
!scalars
  integer :: kk
  character(len=7)   :: tag ! Maximal ' (9999)'
  character(len=18)   :: fmt

! *********************************************************************

 fmt='(a,a,1p,3e22.14,a)'

 do kk=1,natom

   if (atlist(kk)) then
     call gettag(atlist,kk,natom,prtallatoms,tag)
     write(message,fmt)&
&     TRIM(message),ch10,&
&     thearray(:,kk),&
&     tag
   end if
   
 end do
 call wrtout(iout,message,'COLL')

end subroutine prtnatom
!!***
