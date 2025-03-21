module source_network_reinjector_test

  ! Test for source network reinjector module

#include <petsc/finclude/petsc.h>

  use petsc
  use kinds_module
  use zofu
  use source_module
  use control_module
  use source_network_node_module
  use source_network_group_module
  use source_network_reinjector_module
  use source_network_module
  use source_setup_module
  use list_module

  implicit none
  private

  character(len = 512) :: data_path

  public :: setup, teardown
  public :: test_source_network_reinjector, test_source_network_deps

contains

!------------------------------------------------------------------------

  subroutine setup()

    use profiling_module, only: init_profiling

    ! Locals:
    PetscErrorCode :: ierr
    PetscInt :: ios

    call PetscInitialize(PETSC_NULL_CHARACTER, ierr); CHKERRQ(ierr)
    call init_profiling()

    call get_environment_variable('WAIWERA_TEST_DATA_PATH', &
         data_path, status = ios)
    if (ios /= 0) data_path = ''

  end subroutine setup

!------------------------------------------------------------------------

  subroutine teardown()

    PetscErrorCode :: ierr

    call PetscFinalize(ierr); CHKERRQ(ierr)

  end subroutine teardown

!------------------------------------------------------------------------

  subroutine test_source_network_reinjector(test)
    ! Source network reinjector

    use fson
    use fson_mpi_module
    use IAPWS_module
    use eos_we_module
    use mesh_module
    use tracer_module
    use dm_utils_module, only: global_vec_section, global_section_offset
    use utils_module, only: array_is_permutation_of

    class(unit_test_type), intent(in out) :: test
    ! Locals:
    type(IAPWS_type) :: thermo
    type(eos_we_type) :: eos
    type(fson_value), pointer :: json
    type(mesh_type) :: mesh
    type(tracer_type), allocatable :: tracers(:)
    Vec :: fluid_vector
    PetscInt :: fluid_range_start
    PetscReal, pointer, contiguous :: source_array(:), group_array(:), reinjector_array(:)
    PetscSection :: source_section, group_section, reinjector_section
    type(source_network_type) :: source_network
    PetscMPIInt :: rank
    PetscReal, parameter :: start_time = 100._dp, end_time = 200._dp
    PetscReal, parameter :: interval(2) = [start_time, end_time]
    PetscReal, parameter :: gravity(3) = [0._dp, 0._dp, -9.8_dp]
    PetscErrorCode :: err, ierr
    PetscInt, parameter :: expected_num_sources = 39
    PetscInt, parameter :: expected_num_groups = 6
    PetscInt, parameter :: expected_num_reinjectors = 10
    PetscInt, parameter :: expected_num_deps = 52
    PetscInt, parameter :: expected_deps(expected_num_deps, 2) = transpose(reshape( &
         [11, 0,  11, 1,  11, 7,  8, 0,  8, 1,  8, 7,  6, 0,  6, 1,  6, 7,  3, 0,  3, 1, 3, 7, &
         10, 2,  10, 5,  9, 2,  9, 5,  8, 2, 8, 5,  2, 2, 2, 5, &
         11, 0,  3, 0, &
         11, 0,  11, 10,  8, 0,  8, 10, 2, 0,  2, 10, &
         1, 9,  1, 1,  3, 9,  3, 1,  8, 9,  8, 1,  11, 9,  11, 1, &
         1, 8,  1, 2,  5, 8,  5, 2,  11, 8,  11, 2,  7, 8,  7, 2, &
         10, 9,  10, 1,  2, 9,  2, 1,  4, 9,  4, 1,  7, 9,  7, 1 &
         ], [2, expected_num_deps]))

    call MPI_COMM_RANK(PETSC_COMM_WORLD, rank, ierr)
    json => fson_parse_mpi(trim(adjustl(data_path)) // "source/test_source_network_reinjector.json")

    call thermo%init()
    call eos%init(json, thermo)
    call setup_tracers(json, eos, tracers, err = err)
    call mesh%init(eos, json)
    call DMCreateLabel(mesh%serial_dm, open_boundary_label_name, ierr); CHKERRQ(ierr)
    call mesh%configure(gravity, json, err = err)
    call DMGetGlobalVector(mesh%dm, fluid_vector, ierr); CHKERRQ(ierr) ! dummy- not used

    call setup_source_network(json, mesh%dm, mesh%cell_natural_global, eos, tracers, &
         thermo, start_time, fluid_vector, fluid_range_start, source_network, &
         err = err)

    call test%assert(0, err, "error")
    if (rank == 0) then
       call test%assert(expected_num_sources, source_network%num_sources, "number of sources")
       call test%assert(expected_num_groups, source_network%num_groups, "number of groups")
       call test%assert(expected_num_reinjectors, source_network%num_reinjectors, &
            "number of reinjectors")
    end if

    if (err == 0) then

       call global_vec_section(source_network%source, source_section)
       call global_vec_section(source_network%group, group_section)
       call global_vec_section(source_network%reinjector, reinjector_section)
       call VecGetArrayF90(source_network%source, source_array, ierr); CHKERRQ(ierr)
       call VecGetArrayF90(source_network%group, group_array, ierr); CHKERRQ(ierr)
       call VecGetArrayF90(source_network%reinjector, reinjector_array, ierr); CHKERRQ(ierr)

       call source_network%sources%traverse(source_setup_iterator)
       call source_network%groups%traverse(group_assign_iterator)
       call source_network%reinjectors%traverse(reinjector_assign_iterator)

       call source_network%separated_sources%traverse(source_separator_iterator)
       call source_network%groups%traverse(group_sum_iterator)
       call source_network%network_controls%traverse(network_control_iterator)

       call source_network%reinjectors%traverse(reinjector_capacity_iterator)
       call source_network%reinjectors%traverse(reinjector_iterator, backwards = PETSC_TRUE)

       call source_network%groups%traverse(group_test_iterator)
       call source_network%sources%traverse(source_test_iterator)
       call source_network%reinjectors%traverse(reinjector_test_iterator)

       call VecRestoreArrayF90(source_network%reinjector, reinjector_array, ierr); CHKERRQ(ierr)
       call VecRestoreArrayF90(source_network%group, group_array, ierr); CHKERRQ(ierr)
       call VecRestoreArrayF90(source_network%source, source_array, ierr); CHKERRQ(ierr)

       call source_network_dependency_test(test, source_network, expected_deps, rank)

    end if

    call source_network%destroy()
    call DMRestoreGlobalVector(mesh%dm, fluid_vector, ierr); CHKERRQ(ierr)
    call mesh%destroy_distribution_data()
    call mesh%destroy()
    call eos%destroy()
    call thermo%destroy()
    call fson_destroy_mpi(json)

  contains

    subroutine source_setup_iterator(node, stopped)

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped
      ! Locals:
      PetscInt :: s, source_offset

      stopped = PETSC_FALSE
      select type(source => node%data)
      type is (source_type)
         s = source%local_source_index
         source_offset = global_section_offset(source_section, &
              s, source_network%source_range_start)
         call source%assign(source_array, source_offset)
         select case (source%name)
         case ("p1")
            source%enthalpy = 800.e3_dp
         case ("p2")
            source%enthalpy = 800.e3_dp
         case ("p3")
            source%enthalpy = 800.e3_dp
         case ("p4")
            source%enthalpy = 900.e3_dp
         case ("p5")
            source%enthalpy = 1000.e3_dp
         case ("p6")
            source%enthalpy = 1100.e3_dp
         case ("p7")
            source%enthalpy = 800.e3_dp
         case ("p8")
            source%enthalpy = 900.e3_dp
         case ("p9")
            source%enthalpy = 900.e3_dp
         case ("p10")
            source%enthalpy = 800.e3_dp
         case ("p11")
            source%enthalpy = 800.e3_dp
         case ("p12")
            source%enthalpy = 900.e3_dp
         case ("p13")
            source%enthalpy = 900.e3_dp
         case ("p14")
            source%enthalpy = 800.e3_dp
         end select
      end select

    end subroutine source_setup_iterator

!........................................................................

    subroutine group_assign_iterator(node, stopped)

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped
      ! Locals:
      PetscInt :: g, group_offset

      stopped = PETSC_FALSE
      select type(group => node%data)
      class is (source_network_group_type)
         if (group%rank == 0) then
            g = group%local_group_index
            group_offset = global_section_offset(group_section, &
              g, source_network%group_range_start)
            call group%assign(group_array, group_offset)
         end if
      end select

    end subroutine group_assign_iterator

!........................................................................

    subroutine reinjector_assign_iterator(node, stopped)

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped
      ! Locals:
      PetscInt :: r, reinjector_offset

      stopped = PETSC_FALSE
      select type(reinjector => node%data)
      class is (source_network_reinjector_type)
         if (reinjector%rank == 0) then
            r = reinjector%local_reinjector_index
            reinjector_offset = global_section_offset(reinjector_section, &
              r, source_network%reinjector_range_start)
            call reinjector%assign(reinjector_array, reinjector_offset)
         end if
      end select

    end subroutine reinjector_assign_iterator

!........................................................................

    subroutine source_separator_iterator(node, stopped)

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped

      stopped = PETSC_FALSE
      select type(source => node%data)
      type is (source_type)
         call source%get_separated_flows()
      end select

    end subroutine source_separator_iterator

!........................................................................

    subroutine group_sum_iterator(node, stopped)

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped

      stopped = PETSC_FALSE
      select type (group => node%data)
      class is (source_network_group_type)
         call group%sum()
      end select

    end subroutine group_sum_iterator

!........................................................................

    subroutine network_control_iterator(node, stopped)

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped

      stopped = PETSC_FALSE
      select type(control => node%data)
      class is (interval_update_object_control_type)
         call control%update(interval)
      end select

    end subroutine network_control_iterator

!........................................................................

    subroutine reinjector_capacity_iterator(node, stopped)
      !! Calculates output capacity of a reinjector.

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped

      stopped = PETSC_FALSE
      select type (reinjector => node%data)
      class is (source_network_reinjector_type)
         call reinjector%capacity()
      end select

    end subroutine reinjector_capacity_iterator

!------------------------------------------------------------------------

    subroutine reinjector_iterator(node, stopped)
      !! Updates reinjection output flows to injection sources (or
      !! other reinjectors).

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped

      stopped = PETSC_FALSE
      select type (reinjector => node%data)
      class is (source_network_reinjector_type)
         call reinjector%distribute()
      end select

    end subroutine reinjector_iterator

!........................................................................

    subroutine flow_test(node, rate, water_rate, steam_rate, &
         injection_enthalpy)

      class(source_network_node_type), intent(in) :: node
      PetscReal, intent(in) :: rate, water_rate, steam_rate
      PetscReal, intent(in), optional :: injection_enthalpy

      call test%assert(rate, node%rate, trim(node%name) // " rate")
      call test%assert(water_rate, node%water_rate, &
           trim(node%name) // " water rate")
      call test%assert(steam_rate, node%steam_rate, &
           trim(node%name) //" steam rate")

      if (present(injection_enthalpy)) then
         select type (n => node)
         type is (source_type)
            call test%assert(injection_enthalpy, n%injection_enthalpy, &
                 trim(n%name) // " injection enthalpy")
         end select
      end if

    end subroutine flow_test

!........................................................................

    subroutine reinjector_test(reinjector, overflow_water_rate, &
         overflow_steam_rate, water_source_cell_indices, &
         steam_source_cell_indices)

      class(source_network_reinjector_type), intent(in) :: reinjector
      PetscReal, intent(in) :: overflow_water_rate, overflow_steam_rate
      PetscInt, intent(in) :: water_source_cell_indices(:)
      PetscInt, intent(in) :: steam_source_cell_indices(:)

      call test%assert(overflow_water_rate, reinjector%overflow%water_rate, &
           trim(reinjector%name) // " overflow water rate")
      call test%assert(overflow_steam_rate, reinjector%overflow%steam_rate, &
           trim(reinjector%name) // " overflow steam rate")
      call test%assert(array_is_permutation_of(water_source_cell_indices, &
           reinjector%water_source_cell_indices), &
           trim(reinjector%name) // " water cell_indices")
      call test%assert(array_is_permutation_of(steam_source_cell_indices, &
           reinjector%steam_source_cell_indices), &
           trim(reinjector%name) // " steam cell_indices")

    end subroutine reinjector_test

!........................................................................

    subroutine source_test_iterator(node, stopped)

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped

      stopped = PETSC_FALSE
      select type(source => node%data)
      type is (source_type)
         select case (source%name)
         case ("i1")
            call flow_test(source, 2._dp, 2._dp, 0.0_dp, 640.1853353633858e3_dp)
         case ("i2")
            call flow_test(source, 3.51189842644_dp, 3.51189842644_dp, &
                 0.0_dp, 83.9e3_dp)
         case ("i3")
            call flow_test(source, 0.4_dp, 0.0_dp, 0.4_dp, 1200.0e3_dp)
         case ("i4")
            call flow_test(source, 0.180063483479_dp, 0.0_dp, &
                 0.180063483479_dp, 2748.107614657969e3_dp)
         case ("i5")
            call flow_test(source, 2._dp, 2.0_dp, 0._dp, 90.e3_dp)
         case ("i6")
            call flow_test(source, 0.5675848219035333_dp, &
                 0.5675848219035333_dp, 0._dp, 85.e3_dp)
         case ("i7")
            call flow_test(source, 0._dp, 0._dp, 0._dp, 0._dp)
         case ("i8")
            call flow_test(source, 0.4324151780964667_dp, 0._dp, &
                 0.4324151780964667_dp, 1500.e3_dp)
         case ("i9")
            call flow_test(source, 0.9_dp, 0.9_dp, &
                 0._dp, 655.8766515067405e3_dp)
         case ("i10")
            call flow_test(source, 1._dp, 1._dp, 0._dp, 95.e3_dp)
         case ("i11")
            call flow_test(source, 4.94069064259_dp, 4.94069064259_dp, &
                 0._dp, 640.1853353633858e3_dp)
         case ("i12")
            call flow_test(source, 3._dp, 3._dp, &
                 0._dp, 640.1853353633858e3_dp)
         case ("i13")
            call flow_test(source, 1.44069064259_dp, 1.44069064259_dp, &
                 0._dp, 640.1853353633858e3_dp)
         case ("i14")
            call flow_test(source, 4._dp, 4._dp, 0._dp, 640.1853353633858e3_dp)
         case ("i15")
            call flow_test(source, 1._dp, 1._dp, 0._dp, 640.1853353633858e3_dp)
         case ("i16")
            call flow_test(source, 1.5_dp, 1.5_dp, 0._dp, 640.1853353633858e3_dp)
         case ("i17")
            call flow_test(source, 1.8_dp, 1.8_dp, 0._dp, 640.1853353633858e3_dp)
         case ("i18")
            call flow_test(source, 4._dp, 4._dp, 0._dp, 640.1853353633858e3_dp)
         case ("i19")
            call flow_test(source, 2.5_dp, 2.5_dp, 0._dp, 640.1853353633858e3_dp)
         case ("i20")
            call flow_test(source, 1.8_dp, 1.8_dp, 0._dp, 640.1853353633858e3_dp)
         case ("i21")
            call flow_test(source, 2.7_dp, 1.58138128518_dp, &
                 1.1186187148189581_dp, 1513.50433944e3_dp)
         case ("i22")
            call flow_test(source, 4._dp, 4._dp, 0._dp, 640.1853353633858e3_dp)
         case ("i23")
            call flow_test(source, 4.3_dp, 4.3_dp, 0._dp, 640.1853353633858e3_dp)
         case ("i24")
            call flow_test(source, 0.395345321295_dp, 0.395345321295_dp, &
                 0._dp, 640.1853353633858e3_dp)
         case ("i25")
            call flow_test(source, 1.18603596389_dp, 1.18603596389_dp, 0._dp, &
                 640.1853353633858e3_dp)
         end select
      end select

    end subroutine source_test_iterator

!........................................................................

    subroutine group_test_iterator(node, stopped)

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped

      stopped = PETSC_FALSE
      select type(group => node%data)
      class is (source_network_group_type)
         if (group%rank == 0) then
            select case (group%name)
            case ("group1")
               call flow_test(group, -9.5_dp, -8.779746066085552_dp, &
                    -0.7202539339144485_dp)
            case ("group2")
               call flow_test(group, -3._dp, -2.5675848219035333_dp, &
                    -0.4324151780964667_dp)
            case ("group3")
               call flow_test(group, -11._dp, -9.881381285181043_dp, &
                    -1.1186187148189581_dp)
            case ("group4")
               call flow_test(group, -11._dp, -9.881381285181043_dp, &
                    -1.1186187148189581_dp)
            case ("group5")
               call flow_test(group, -11._dp, -9.881381285181043_dp, &
                    -1.1186187148189581_dp)
            case ("group6")
               call flow_test(group, -11._dp, -9.881381285181043_dp, &
                    -1.1186187148189581_dp)
            end select
         end if
      end select

    end subroutine group_test_iterator

!........................................................................

    subroutine reinjector_test_iterator(node, stopped)

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped

      stopped = PETSC_FALSE
      select type (reinjector => node%data)
      class is (source_network_reinjector_type)
         if (reinjector%rank == 0) then
            select case (reinjector%name)
            case ("re1")
               call reinjector_test(reinjector, 3.26784763965_dp, &
                    0.140190450435_dp, [11, 8], [6, 3])
            case ("re2")
               call reinjector_test(reinjector, 0._dp, 0._dp, [10, 9, 8], [2])
            case ("re3")
               call reinjector_test(reinjector, 0.46446499954_dp, &
                    0.635535000462524_dp, [11, 3], [PetscInt::])
            case ("re4")
               call reinjector_test(reinjector, 0._dp, 1.1186187148189581_dp, &
                    [11, 8, 2], [PetscInt::])
            case ("re5")
               call reinjector_test(reinjector, 0._dp, 0._dp, [8, 2], [PetscInt::])
            case ("re6")
               call reinjector_test(reinjector, 1.58138128518_dp, &
                    1.1186187148189581_dp, [1, 3, 8, 11], [PetscInt::])
            case ("re7")
               call reinjector_test(reinjector, 0._dp, 0._dp, [3, 8], [PetscInt::])
            case ("re8")
               call reinjector_test(reinjector, 1.58138128518_dp, &
                    1.1186187148189581_dp, [1, 5, 11, 7], [7])
            case ("re9")
               call reinjector_test(reinjector, 1.58138128518_dp, &
                    1.1186187148189581_dp, [10, 2, 4, 7], [PetscInt::])
            case ("re10")
               call reinjector_test(reinjector, 0._dp, &
                    1.1186187148189581_dp, [4, 7], [PetscInt::])
            end select
         end if
      end select

    end subroutine reinjector_test_iterator

  end subroutine test_source_network_reinjector

!------------------------------------------------------------------------

  subroutine test_source_network_deps(test)
    ! Source network dependencies

    use fson
    use fson_mpi_module
    use IAPWS_module
    use eos_we_module
    use mesh_module
    use tracer_module
    use dm_utils_module, only: global_vec_section, global_section_offset

    class(unit_test_type), intent(in out) :: test
    ! Locals:
    type(IAPWS_type) :: thermo
    type(eos_we_type) :: eos
    type(fson_value), pointer :: json
    type(mesh_type) :: mesh
    type(tracer_type), allocatable :: tracers(:)
    Vec :: fluid_vector
    PetscInt :: fluid_range_start
    PetscReal, pointer, contiguous :: source_array(:), group_array(:), reinjector_array(:)
    PetscSection :: source_section, group_section, reinjector_section
    type(source_network_type) :: source_network
    PetscMPIInt :: rank
    PetscReal, parameter :: start_time = 100._dp, end_time = 200._dp
    PetscReal, parameter :: interval(2) = [start_time, end_time]
    PetscReal, parameter :: gravity(3) = [0._dp, 0._dp, -9.8_dp]
    PetscErrorCode :: err, ierr
    PetscInt, parameter :: expected_num_sources = 9
    PetscInt, parameter :: expected_num_groups = 2
    PetscInt, parameter :: expected_num_reinjectors = 2
    PetscInt, parameter :: expected_num_deps = 10
    PetscInt, parameter :: expected_deps(expected_num_deps, 2) = transpose(reshape( &
         [42, 0,  2, 4,  4, 2,  45, 6,  48, 6, 45, 17,  48, 17, 31, 6, 31, 17, 48, 45], &
         [2, expected_num_deps]))

    call MPI_COMM_RANK(PETSC_COMM_WORLD, rank, ierr)
    json => fson_parse_mpi(trim(adjustl(data_path)) // "source/test_source_network_deps.json")

    call thermo%init()
    call eos%init(json, thermo)
    call setup_tracers(json, eos, tracers, err = err)
    call mesh%init(eos, json)
    call DMCreateLabel(mesh%serial_dm, open_boundary_label_name, ierr); CHKERRQ(ierr)
    call mesh%configure(gravity, json, err = err)
    call DMGetGlobalVector(mesh%dm, fluid_vector, ierr); CHKERRQ(ierr) ! dummy- not used

    call setup_source_network(json, mesh%dm, mesh%cell_natural_global, eos, tracers, &
         thermo, start_time, fluid_vector, fluid_range_start, source_network, &
         err = err)

    call test%assert(0, err, "error")
    if (rank == 0) then
       call test%assert(expected_num_sources, source_network%num_sources, "number of sources")
       call test%assert(expected_num_groups, source_network%num_groups, "number of groups")
       call test%assert(expected_num_reinjectors, source_network%num_reinjectors, &
            "number of reinjectors")
    end if

    if (err == 0) then

       call global_vec_section(source_network%source, source_section)
       call global_vec_section(source_network%group, group_section)
       call global_vec_section(source_network%reinjector, reinjector_section)
       call VecGetArrayF90(source_network%source, source_array, ierr); CHKERRQ(ierr)
       call VecGetArrayF90(source_network%group, group_array, ierr); CHKERRQ(ierr)
       call VecGetArrayF90(source_network%reinjector, reinjector_array, ierr); CHKERRQ(ierr)

       call source_network%groups%traverse(group_assign_iterator)
       call source_network%reinjectors%traverse(reinjector_assign_iterator)

       call VecRestoreArrayF90(source_network%reinjector, reinjector_array, ierr); CHKERRQ(ierr)
       call VecRestoreArrayF90(source_network%group, group_array, ierr); CHKERRQ(ierr)
       call VecRestoreArrayF90(source_network%source, source_array, ierr); CHKERRQ(ierr)

       call source_network_dependency_test(test, source_network, expected_deps, rank)

    end if

    call source_network%destroy()
    call DMRestoreGlobalVector(mesh%dm, fluid_vector, ierr); CHKERRQ(ierr)
    call mesh%destroy_distribution_data()
    call mesh%destroy()
    call eos%destroy()
    call thermo%destroy()
    call fson_destroy_mpi(json)

  contains

!........................................................................

    subroutine group_assign_iterator(node, stopped)

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped
      ! Locals:
      PetscInt :: g, group_offset

      stopped = PETSC_FALSE
      select type(group => node%data)
      class is (source_network_group_type)
         if (group%rank == 0) then
            g = group%local_group_index
            group_offset = global_section_offset(group_section, &
              g, source_network%group_range_start)
            call group%assign(group_array, group_offset)
         end if
      end select

    end subroutine group_assign_iterator

!........................................................................

    subroutine reinjector_assign_iterator(node, stopped)

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped
      ! Locals:
      PetscInt :: r, reinjector_offset

      stopped = PETSC_FALSE
      select type(reinjector => node%data)
      class is (source_network_reinjector_type)
         if (reinjector%rank == 0) then
            r = reinjector%local_reinjector_index
            reinjector_offset = global_section_offset(reinjector_section, &
              r, source_network%reinjector_range_start)
            call reinjector%assign(reinjector_array, reinjector_offset)
         end if
      end select

    end subroutine reinjector_assign_iterator

  end subroutine test_source_network_deps

!------------------------------------------------------------------------

  subroutine source_network_dependency_test(test, source_network, &
       expected_deps, rank)

    class(unit_test_type), intent(in out) :: test
    type(source_network_type), intent(in out) :: source_network
    PetscInt, intent(in) :: expected_deps(:,:)
    PetscMPIInt, intent(in) :: rank
    ! Locals:
    PetscInt :: max_num_cells, n2
    PetscBool, allocatable :: nonzero(:, :), nonzero_exp(:, :)
    PetscBool, allocatable :: nonzero1(:), nonzero1_all(:)
    PetscInt :: i
    PetscErrorCode :: ierr

    max_num_cells = maxval(expected_deps) + 1
    allocate(nonzero(0: max_num_cells - 1, 0: max_num_cells - 1))
    allocate(nonzero_exp(0: max_num_cells - 1, 0: max_num_cells - 1))
    n2 = max_num_cells * max_num_cells

    nonzero = PETSC_FALSE
    call source_network%dependencies%traverse(dependency_iterator)
    nonzero1 = reshape(nonzero, [n2])
    if (rank == 0) then
       allocate(nonzero1_all(n2))
    else
       allocate(nonzero1_all(1))
    end if
    call MPI_reduce(nonzero1, nonzero1_all, n2, MPI_LOGICAL, MPI_LOR, &
         0, PETSC_COMM_WORLD, ierr)

    if (rank == 0) then
       nonzero = reshape(nonzero1_all, [max_num_cells, max_num_cells])
       nonzero_exp = PETSC_FALSE
       do i = 1, size(expected_deps, 1)
          nonzero_exp(expected_deps(i,1), expected_deps(i,2)) = PETSC_TRUE
       end do
       call test%assert(nonzero_exp, nonzero, "source network dependencies")
    end if

  contains

    subroutine dependency_iterator(node, stopped)

      type(list_node_type), pointer, intent(in out) :: node
      PetscBool, intent(out) :: stopped

      stopped = PETSC_FALSE
      select type (dep => node%data)
      class is (source_dependency_type)
         nonzero(dep%equation, dep%cell) = PETSC_TRUE
      end select

    end subroutine dependency_iterator

  end subroutine source_network_dependency_test

!------------------------------------------------------------------------

end module source_network_reinjector_test
