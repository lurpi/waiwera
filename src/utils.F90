!   Copyright 2016 University of Auckland.

!   This file is part of Waiwera.

!   Waiwera is free software: you can redistribute it and/or modify
!   it under the terms of the GNU Lesser General Public License as published by
!   the Free Software Foundation, either version 3 of the License, or
!   (at your option) any later version.

!   Waiwera is distributed in the hope that it will be useful,
!   but WITHOUT ANY WARRANTY; without even the implied warranty of
!   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!   GNU Lesser General Public License for more details.

!   You should have received a copy of the GNU Lesser General Public License
!   along with Waiwera.  If not, see <http://www.gnu.org/licenses/>.

module utils_module
  !! Utility functions for string handling, formatting, file names
  !! etc. and constants.

#include <petsc/finclude/petsc.h>

  use petsc
  use kinds_module

  implicit none
  private

  PetscReal, parameter, public :: pi = 4._dp * atan(1._dp)

  interface polynomial
     module procedure polynomial_single
     module procedure polynomial_multiple
  end interface polynomial

  interface polynomial_derivative
     module procedure polynomial_derivative_single
     module procedure polynomial_derivative_multiple
  end interface polynomial_derivative

  interface polynomial_integral
     module procedure polynomial_integral_single
     module procedure polynomial_integral_multiple
  end interface polynomial_integral

  interface array_cumulative_sum
     module procedure array_cumulative_sum_real
     module procedure array_cumulative_sum_integer
  end interface array_cumulative_sum

  interface array_sorted
     module procedure array_sorted_int
     module procedure array_sorted_real
  end interface array_sorted

  interface newton1d
     module procedure newton1d_general
     module procedure newton1d_polynomial
  end interface newton1d

  public :: str_to_lower, &
       int_str_len, str_array_index, &
       split_filename, change_filename_extension, &
       date_time_str, degrees_to_radians, rotation_matrix_2d, &
       polynomial, polynomial_derivative, polynomial_integral, &
       array_pair_sum, array_cumulative_sum, &
       array_exclusive_products, array_sorted, &
       array_indices_in_int_array, clock_elapsed_time, &
       array_is_permutation, array_is_permutation_of, &
       array_unique, array_progressive_limit, newton1d, sign_test

contains

!------------------------------------------------------------------------

  elemental function str_to_lower(a) result(b)
    !! Converts a string to all lower case.

    character(len = *), intent(in) :: a !! Input string
    character(len = len(a)) :: b !! Output lowercase string
    integer :: i,j

    b = a
    do i = 1, len(b)
       j = iachar(b(i:i))
       if (j >= iachar("A") .and. j <= iachar("Z") ) then
          b(i:i) = achar(iachar(b(i:i)) + 32)
       end if
    end do

  end function str_to_lower

!------------------------------------------------------------------------

  recursive function int_str_len(i) result (w)
    !! Returns minimum length of string needed to represent a given
    !! integer i.

    PetscInt, intent(in) :: i !! Input integer
    PetscInt :: w !! Output string length

    if (i == 0) then
       w = 1
    else if (i > 0) then
       w = 1 + int(log10(real(i)))
    else
       w = 1 + int_str_len(-i)
    end if

  end function int_str_len

!------------------------------------------------------------------------

  PetscInt function str_array_index(str, str_array) result(index)
    !! Returns index of given string in an array of strings (or -1 if
    !! it isn't in there).

    character(len = *), intent(in) :: str
    character(len = *), intent(in) :: str_array(:)
    ! Locals:
    PetscInt :: i, n

    index = -1
    n = size(str_array)
    do i = 1, n
       if (trim(str) == trim(str_array(i))) then
          index = i
          exit
       end if
    end do

  end function str_array_index

!------------------------------------------------------------------------

  subroutine split_filename(filename, base, ext)
    !! Splits filename into base and extension.

    character(*), intent(in) :: filename !! File name
    character(:), allocatable, intent(out) :: base !! Base part of filename
    character(:), allocatable, intent(out) :: ext !! File extension
    ! Locals:
    PetscInt:: i, n, base_end, ext_start
  
    n = len(filename)
    i = scan(filename, '.', PETSC_TRUE)
    if ((i > 0) .and. (i < n)) then
       base_end = i - 1
       ext_start = i + 1
       base = filename(1: base_end)
       ext = filename(ext_start: n)
    else
       base = filename
       ext = ""
    end if

  end subroutine split_filename

!------------------------------------------------------------------------

  function change_filename_extension(filename, ext) result(new_filename)
    !! Changes filename extension.

    character(*), intent(in) :: filename !! File name
    character(*), intent(in) :: ext !! New file extension
    character(:), allocatable :: new_filename !! Output file name
    ! Locals:
    character(:), allocatable :: base, oldext

    call split_filename(filename, base, oldext)
    new_filename = trim(base) // '.' // trim(ext)

    deallocate(base, oldext)

  end function change_filename_extension

!------------------------------------------------------------------------

  character(25) function date_time_str()
    !! Returns string with current date and time.

    ! Locals:
    character(8) :: datestr
    character(10) :: timestr
    character(5) :: zonestr

    call date_and_time(datestr, timestr, zonestr)

    date_time_str = datestr // ' ' // timestr // ' ' // zonestr

  end function date_time_str

!------------------------------------------------------------------------

  PetscReal function degrees_to_radians(degrees) result(radians)
    !! Converts angle from degrees to radians.

    PetscReal, intent(in) :: degrees

    radians = degrees * pi / 180._dp

  end function degrees_to_radians

!------------------------------------------------------------------------

  function rotation_matrix_2d(angle) result(M)
    !! Returns a 2x2 rotation matrix corresponding to the given angle
    !! (anti-clockwise, in radians).

    PetscReal, intent(in) :: angle
    PetscReal :: M(2, 2)
    ! Locals:
    PetscReal :: c, s

    c = cos(angle)
    s = sin(angle)
    M = reshape([c, -s, s, c], [2, 2])

  end function rotation_matrix_2d

!------------------------------------------------------------------------

  function polynomial_single(a, x) result(p)
    !! Evaluate polynomial a1 + a2*x + a3 * x^2 + ..., using Horner's
    !! method.

    PetscReal, intent(in) :: a(:)
    PetscReal, intent(in) :: x
    PetscReal :: p
    ! Locals:
    PetscInt :: i

    associate(n => size(a))
      p = a(n)
      do i = n - 1, 1, -1
         p = a(i) + x * p
      end do
    end associate

  end function polynomial_single

!------------------------------------------------------------------------

  function polynomial_multiple(a, x) result(p)
    !! Evaluate polynomials a(:, 1) + a(:, 2) * x + a(:, 3) * x^2 +
    !! ..., using Horner's method.

    PetscReal, intent(in) :: a(:, :)
    PetscReal, intent(in) :: x
    PetscReal :: p(size(a, 1))
    ! Locals:
    PetscInt :: i

    associate(n => size(a, 2))
      p = a(:, n)
      do i = n - 1, 1, -1
         p = a(:, i) + x * p
      end do
    end associate

  end function polynomial_multiple

!------------------------------------------------------------------------

  PetscReal function array_pair_sum(a) result(s)
    !! Returns sum of products of consecutive pairs in an array
    !! (including the pair formed by the last and first elements).

    PetscReal, intent(in) :: a(:)
    ! Locals:
    PetscInt :: i, i1

    s = 0._dp
    associate(n => size(a))
      if (n == 1) then
         s = a(1)
      else
         do i = 1, n
            i1 = i + 1
            if (i1 > n) i1 = i1 - n
            s = s + a(i) * a(i1)
         end do
      end if
    end associate

  end function array_pair_sum

!------------------------------------------------------------------------

  function polynomial_derivative_single(a) result(da)
    !! Takes coefficient array of a polynomial and returns the
    !! coefficient array of its derivative.

    PetscReal, intent(in) :: a(:)
    PetscReal :: da(size(a) - 1)
    ! Locals:
    PetscInt :: i

    do i = 1, size(a) - 1
       da(i) = i * a(i + 1)
    end do

  end function polynomial_derivative_single

!------------------------------------------------------------------------

  function polynomial_derivative_multiple(a) result(da)
    !! Takes coefficient array for multiple polynomials and returns
    !! the coefficient array of their derivatives.

    PetscReal, intent(in) :: a(:, :)
    PetscReal :: da(size(a, 1), size(a, 2) - 1)
    ! Locals:
    PetscInt :: i

    do i = 1, size(a, 2) - 1
       da(:, i) = i * a(:, i + 1)
    end do

  end function polynomial_derivative_multiple

!------------------------------------------------------------------------

  function polynomial_integral_single(a) result(ai)
    !! Takes coefficient array of a polynomial and returns the
    !! coefficient array of its integral.

    PetscReal, intent(in) :: a(:)
    PetscReal :: ai(size(a) + 1)
    ! Locals:
    PetscInt :: i

    ai(1) = 0._dp
    do i = 2, size(a) + 1
       ai(i) = a(i - 1) / real(i - 1)
    end do

  end function polynomial_integral_single

!------------------------------------------------------------------------

  function polynomial_integral_multiple(a) result(ai)
    !! Takes coefficient array for multiple polynomials and returns
    !! the coefficient array of their integrals.

    PetscReal, intent(in) :: a(:, :)
    PetscReal :: ai(size(a, 1), size(a, 2) + 1)
    ! Locals:
    PetscInt :: i

    ai(:, 1) = 0._dp
    do i = 2, size(a) + 1
       ai(:, i) = a(:, i - 1) / real(i - 1)
    end do

  end function polynomial_integral_multiple

!------------------------------------------------------------------------

  function array_cumulative_sum_real(a) result(s)
    !! Cumulative sums of a real array.

    PetscReal, intent(in) :: a(:)
    PetscReal :: s(size(a))
    ! Locals:
    PetscInt :: i

    associate(n => size(a))
      if (n > 0) then
         s(1) = a(1)
         do i = 2, n
            s(i) = s(i - 1) + a(i)
         end do
      end if
    end associate

  end function array_cumulative_sum_real

!------------------------------------------------------------------------

  function array_cumulative_sum_integer(a) result(s)
    !! Cumulative sums of an integer array.

    PetscInt, intent(in) :: a(:)
    PetscInt :: s(size(a))
    ! Locals:
    PetscInt :: i

    associate(n => size(a))
      if (n > 0) then
         s(1) = a(1)
         do i = 2, n
            s(i) = s(i - 1) + a(i)
         end do
      end if
    end associate

  end function array_cumulative_sum_integer

!------------------------------------------------------------------------

  function array_exclusive_products(a) result(p)
    !! Returns products of array elements, excluding successive
    !! elements of the array. If the array has only one element, the
    !! returned result is 1.

    PetscReal, intent(in) :: a(:)
    PetscReal :: p(size(a))
    ! Locals:
    PetscInt :: i
    PetscReal :: x(size(a))

    do i = 1, size(a)
       x = a
       x(i) = 1._dp
       p(i) = product(x)
    end do

  end function array_exclusive_products

!------------------------------------------------------------------------

  PetscBool function array_sorted_int(a) result(sorted)
    !! Returns true if specified integer array a is monotonically
    !! increasing.

    PetscInt, intent(in) :: a(:)
    ! Locals:
    PetscInt :: i

    sorted = PETSC_TRUE
    associate(n => size(a))
      do i = 1, n - 1
         if (a(i + 1) < a(i)) then
            sorted = PETSC_FALSE
            exit
         end if
      end do
    end associate

  end function array_sorted_int

!------------------------------------------------------------------------

  PetscBool function array_sorted_real(a) result(sorted)
    !! Returns true if specified real array a is monotonically
    !! increasing.

    PetscReal, intent(in) :: a(:)
    ! Locals:
    PetscInt :: i

    sorted = PETSC_TRUE
    associate(n => size(a))
      do i = 1, n - 1
         if (a(i + 1) < a(i)) then
            sorted = PETSC_FALSE
            exit
         end if
      end do
    end associate

  end function array_sorted_real

!------------------------------------------------------------------------

  function array_indices_in_int_array(a, b) result(indices)
    !! Returns (1-based) indices of the elements of integer array b in
    !! array a. It is assumed that a and b are permutations of each
    !! other.

    PetscInt, intent(in) :: a(:), b(:)
    PetscInt :: indices(size(a))
    ! Locals:
    PetscInt :: fa(size(a)), fb(size(a)), fbi(size(a))
    PetscInt :: i
    PetscErrorCode :: ierr

    associate (n => size(a))

      ! Find sort permutations for a and b:
      fa = [(i, i = 0, n - 1)]
      call PetscSortIntWithPermutation(n, a, fa, ierr); CHKERRQ(ierr)
      fa = fa + 1
      fb = [(i, i = 0, n - 1)]
      call PetscSortIntWithPermutation(n, b, fb, ierr); CHKERRQ(ierr)
      fb = fb + 1

      ! Invert permutation for b:
      fbi = -1
      do i = 1, n
         fbi(fb(i)) = i
      end do

      do i = 1, n
         indices(i) = fa(fbi(i))
      end do

    end associate

  end function array_indices_in_int_array

!------------------------------------------------------------------------

  PetscReal function clock_elapsed_time(start)
    !! Returns elapsed time from start clock time, using
    !! the Fortran system_clock() function.

    use iso_fortran_env, only: int32, real32

    integer(int32), intent(in) :: start
    ! Locals:
    integer(int32) :: end, rate

    call system_clock(end, rate)
    clock_elapsed_time = real(real(end - start, real32) / &
         real(rate, real32), dp)

  end function clock_elapsed_time

!------------------------------------------------------------------------

  PetscBool function array_is_permutation(a)
    !! Returns true if the integer array a is a permutation.

    PetscInt, intent(in) :: a(:)
    ! Locals:
    PetscInt, allocatable :: count(:)
    PetscInt :: i, amin, amax

    associate(n => size(a))
      amin = minval(a)
      amax = amin + n - 1
      allocate(count(amin: amax))
      count = 0
      array_is_permutation = PETSC_TRUE
      do i = 1, n
         if (a(i) <= amax) then
            count(a(i)) = count(a(i)) + 1
         else
            array_is_permutation = PETSC_FALSE
            exit
         end if
      end do
      array_is_permutation = (array_is_permutation .and. all(count == 1))
      deallocate(count)
    end associate

  end function array_is_permutation

!------------------------------------------------------------------------

  PetscBool function array_is_permutation_of(a, b)
    !! Returns true if the integer arrays a and b are permutations of
    !! each other.

    PetscInt, intent(in) :: a(:), b(:)
    ! Locals:
    PetscInt :: asort(size(a)), bsort(size(b))
    PetscCount :: na, nb
    PetscErrorCode :: ierr

    na = size(a)
    nb = size(b)
    if (na == nb) then
       asort = a
       bsort = b
       call PetscSortInt(na, asort, ierr); CHKERRQ(ierr)
       call PetscSortInt(nb, bsort, ierr); CHKERRQ(ierr)
       array_is_permutation_of = all(asort == bsort)
    else
       array_is_permutation_of = PETSC_FALSE
    end if

  end function array_is_permutation_of

!------------------------------------------------------------------------

  function array_unique(v)
    !! Returns an array of the unique values in the integer array v.

    PetscInt, intent(in) :: v(:)
    PetscInt, allocatable :: array_unique(:)
    ! Locals:
    PetscInt :: i, n, num
    PetscBool :: mask(size(v))

    mask = PETSC_FALSE
    n = size(v)

    do i = 1, n
       num = count(v == v(i))
       if (num == 1) then
          mask(i) = PETSC_TRUE
       else
          mask(i) = (.not. any(v(i) == v .and. mask))
       end if
    end do

    array_unique = pack(v, mask)

  end function array_unique

!------------------------------------------------------------------------

  function array_progressive_limit(a, total, order) result(limit)
    !! Returns array of limits required to apply to real array a
    !! progressively so that it sums to the specified total: each
    !! element of a is limited in order until the required total is
    !! reached. The optional order array specifies a permutation so
    !! that the limiting can be carried out in any order.

    PetscReal, intent(in) :: a(:) !! Quantities to limit
    PetscReal, intent(in) :: total !! Target total of a array
    PetscInt, intent(in), optional :: order(:) !! Permutation for limiting order
    PetscReal :: limit(size(a)) !! Output limits for a
    ! Locals:
    PetscInt :: limit_order(size(a))
    PetscInt :: i, j
    PetscReal :: sum_a, next_sum_a

    associate(n => size(a))

      if (present(order)) then
         limit_order = order
      else
         limit_order = [(i, i = 1, n)]
      end if

      limit = 0._dp
      sum_a = 0._dp
      do i = 1, n
         j = limit_order(i)
         next_sum_a = sum_a + a(j)
         if (next_sum_a > total) then
            limit(j) = total - sum_a
            exit
         else
            limit(j) = a(j)
            sum_a = next_sum_a
         end if
      end do

    end associate

  end function array_progressive_limit

!------------------------------------------------------------------------

  recursive subroutine newton1d_general(f, x, ftol, xtol, &
       max_iterations, x_increment, err)
    !! 1-D Newton solve to find f(x) = 0, for the specified function
    !! f, function tolerance, variable tolerance, maximum number of
    !! iterations and relative variable increment. The error flag
    !! returns nonzero if there were any errors in function evaluation
    !! or the iteration limit was exceeded.

    interface
       PetscReal function f(x, err)
         PetscReal, intent(in) :: x
         PetscErrorCode, intent(out) :: err
       end function f
    end interface

    PetscReal, intent(in out) :: x !! Starting and final variable value
    PetscReal, intent(in) :: ftol !! Function tolerance
    PetscReal, intent(in) :: xtol !! Variable tolerance
    PetscInt, intent(in) :: max_iterations !! Maximum number of iterations
    PetscReal, intent(in) :: x_increment !! Relative variable increment
    PetscErrorCode, intent(out) :: err !! Error code
    ! Locals:
    PetscReal :: delx, fx, fxd, df, dx
    PetscInt :: i
    PetscBool :: found

    delx = x_increment * x
    found = PETSC_FALSE

    do i = 1, max_iterations
       fx = f(x, err)
       if (err == 0) then
          if (abs(fx) <= ftol) then
             found = PETSC_TRUE
             exit
          else
             fxd = f(x + delx, err)
             if (err == 0) then
                df = (fxd - fx) / delx
                dx = - fx / df
                x = x + dx
                if (abs(dx) <= xtol) then
                   found = PETSC_TRUE
                   exit
                end if
             else
                exit
             end if
          end if
       else
          exit
       end if
    end do

    if ((err == 0) .and. (.not.(found))) then
       err = 1
    end if

  end subroutine newton1d_general

!------------------------------------------------------------------------

  recursive subroutine newton1d_polynomial(f, x, ftol, xtol, &
       max_iterations, err)
    !! 1-D Newton solve to find f(x) = 0, for the specified polynomial
    !! f, function tolerance, variable tolerance and maximum number of
    !! iterations. The error flag returns nonzero if the iteration
    !! limit was exceeded.

    PetscReal, intent(in) :: f(:)
    PetscReal, intent(in out) :: x !! Starting and final variable value
    PetscReal, intent(in) :: ftol !! Function tolerance
    PetscReal, intent(in) :: xtol !! Variable tolerance
    PetscInt, intent(in) :: max_iterations !! Maximum number of iterations
    PetscErrorCode, intent(out) :: err !! Error code

    ! Locals:
    PetscReal :: fdash(size(f) - 1)
    PetscReal :: fx, df, dx
    PetscInt :: i
    PetscBool :: found

    fdash = polynomial_derivative(f)
    found = PETSC_FALSE

    do i = 1, max_iterations
       fx = polynomial(f, x)
       if (abs(fx) <= ftol) then
          found = PETSC_TRUE
          exit
       else
          df = polynomial(fdash, x)
          dx = - fx / df
          x = x + dx
          if (abs(dx) <= xtol) then
             found = PETSC_TRUE
             exit
          end if
       end if
    end do

    if (found) then
       err = 0
    else
       err = 1
    end if

  end subroutine newton1d_polynomial

!------------------------------------------------------------------------

  PetscInt function sign_test(a, b)
    !! Return -1 if a and b are of opposite sign, 0 if either argument
    !! is zero or 1 if a, b are of the same sign.

    PetscReal, intent(in) :: a, b
    ! Locals:
    PetscReal, parameter :: tol = 1.e-16_dp

    if ((abs(a) < tol) .or. (abs(b) < tol)) then
       sign_test = 0
    else
       sign_test = nint(sign(1._dp, a) * sign(1._dp, b))
    end if

  end function sign_test

!------------------------------------------------------------------------

end module utils_module
