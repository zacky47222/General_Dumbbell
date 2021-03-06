program General_Dumbbell
    use Integrate
    use Generate_Initial_Conditions
    use Dumbbell_util
    use omp_lib
    implicit none

    integer*8 :: Nsteps, steps, time(1:8), seed, i, Ntraj, VR_opt, dist_opt, lookup_opt
    integer :: NTimeSteps, timestep, Ndtwidths, Nvals
    real*8 :: Nrelax_times, dt, dW(3), output_delay, output_delay_dist,  delay_counter, delay_counter_dist
    real*8 :: sr, alpha, h, a, Q0, YMinMax(2), Ymin, Ymax, k(3,3)
    type(measured_variables) :: out_var
    !large arrays must be declared allocatable so they go into heap, otherwise
    !OpenMP threads run out of memory
    real*8, dimension(:, :), allocatable :: Q, Q_eq_VR, storage_vals
    real*8, dimension(:), allocatable :: Yvals, Qvals, timestepwidths

    call date_and_time(values=time)
    seed = time(8)*100 + time(7)*10

    open(unit=31, file='inputparameters.inp')
    open(unit=30, file='timestepdata.inp')
    open(unit=32, file='options.inp')
    open(unit=25, file='Q_dist_output.dat', form='unformatted')

    open(unit=19, file='F.dat')
    open(unit=20, file='Ql.dat')
    open(unit=21, file='S.dat')
    open(unit=22, file='eta.dat')
    open(unit=23, file='psi.dat')
    open(unit=24, file='psi2.dat')
    open(unit=40, file='chiG.dat')
    open(unit=41, file='chiTau.dat')

    read (32, *) VR_opt, dist_opt, lookup_opt
    read (31, *) sr, alpha, h, Q0
    read (30, *) Ntraj, Ndtwidths, Nrelax_times, output_delay, output_delay_dist
    allocate(timestepwidths(Ndtwidths))
    do i=1,Ndtwidths
        read(30, *) timestepwidths(i)
    end do

    allocate(Q(3,1:Ntraj))
    if (VR_opt.eq.1) then
        allocate(Q_eq_VR(3,1:Ntraj))
    end if

    if (lookup_opt.eq.1) then
        allocate(Yvals(2*Nvals), Qvals(2*Nvals), storage_vals(2*Nvals, 2))
    end if

    a = h*sqrt(PI)

    !For shear flow
    k(:,:) = 0.D0
    k(1,2) = 1.D0
    k = sr*k

    Nvals = 1001

    !lookup table branch, applies when lookup_opt == 1
    if (lookup_opt.eq.1) then
        do timestep=1,Ndtwidths

            dt = timestepwidths(timestep)
            NtimeSteps = int(Nrelax_times/dt)
            delay_counter = 0.D0
            delay_counter_dist = 0.D0

            !Also works for Fraenkel, FENE and Hookean springs
            !Reduce final input for faster computation of equilibrium dist
            Q(:,:) = generate_Q_FF(Q0, alpha, Ntraj, seed, 10000)

            storage_vals = generate_lookup_table(real(dt*alpha/4.D0,kind=quad), real(Q0, kind=quad), real(alpha, kind=quad), Nvals)
            Yvals = storage_vals(:,1)
            Qvals = storage_vals(:,2)

            call initialise_output_files_timestep()

            if (dist_opt.eq.1) then
                write(25) dt
            end if

            call write_distribution_to_file(0)

            !$OMP PARALLEL DEFAULT(firstprivate) SHARED(Q, Q_eq_VR, VR_opt, out_var)
            !$ seed = seed + 932117 + OMP_get_thread_num()*2685821657736338717_8
            if (VR_opt.eq.0) then
                do steps=1,Ntimesteps
                    !$OMP DO schedule(dynamic, 100)
                    do i=1,Ntraj
                        dW = Wiener_step(seed, dt)
                        Q(:,i) = step(Q(:,i), k, dt, Q0, alpha, a, dW, Yvals, Qvals)
                    end do
                    !$OMP END DO
                    delay_counter = delay_counter + dt
                    if ((steps.eq.1).or.(delay_counter.ge.(output_delay-1.D-10)).or.(steps.eq.NTimeSteps)) then
                        call write_data_to_files_no_VR(steps)
                        if (delay_counter.ge.(output_delay-1.D-10)) then
                            delay_counter = delay_counter - output_delay
                        end if
                    end if
                    delay_counter_dist = delay_counter_dist + dt
                    if ((steps.eq.1).or.(delay_counter_dist.ge.(output_delay_dist-1.D-10)).or.(steps.eq.NTimeSteps)) then
                        call write_distribution_to_file(steps)
                        if (delay_counter_dist.ge.(output_delay_dist-1.D-10)) then
                            delay_counter_dist = delay_counter_dist - output_delay_dist
                        end if
                    end if
                end do

            elseif (VR_opt.eq.1) then
                !$OMP single
                Q_eq_VR(:,:) = Q(:,:)
                !$OMP end single
                do steps=1,Ntimesteps
                    !$OMP DO schedule(dynamic, 100)
                    do i=1,Ntraj
                        dW = Wiener_step(seed, dt)
                        Q(:,i) =  step(Q(:,i), k, dt, Q0, alpha, a, dW, Yvals, Qvals)
                        Q_eq_VR(:,i) = step(Q_eq_VR(:,i), dt, Q0, alpha, a, dW, Yvals, Qvals)
                    end do
                    !$OMP END DO
                    delay_counter = delay_counter + dt
                    if ((steps.eq.1).or.(delay_counter.ge.(output_delay-1.D-10)).or.(steps.eq.NTimeSteps)) then
                        call write_data_to_files_no_VR(steps)
                        if (delay_counter.ge.(output_delay-1.D-10)) then
                            delay_counter = delay_counter - output_delay
                        end if
                    end if
                    delay_counter_dist = delay_counter_dist + dt
                    if ((steps.eq.1).or.(delay_counter_dist.ge.(output_delay_dist-1.D-10)).or.(steps.eq.NTimeSteps)) then
                        call write_distribution_to_file(steps)
                        if (delay_counter_dist.ge.(output_delay_dist-1.D-10)) then
                            delay_counter_dist = delay_counter_dist - output_delay_dist
                        end if
                    end if
                end do

            else
                print *, "Variance Reduction option not set, place in options.inp file"
            end if
            !$OMP END PARALLEL

        end do
    !Original method branch, applies for lookup_opt == 0
    elseif (lookup_opt.eq.0) then
        do timestep=1,Ndtwidths

            dt = timestepwidths(timestep)
            NtimeSteps = int(Nrelax_times/dt)
            delay_counter = 0.D0
            delay_counter_dist = 0.D0

            !Also works for Fraenkel, FENE and Hookean springs
            !Reduce final input for faster computation of equilibrium dist
            Q(:,:) = generate_Q_FF(Q0, alpha, Ntraj, seed, 10000)

            call initialise_output_files_timestep()

            if (dist_opt.eq.1) then
                write(25) dt
            end if

            call write_distribution_to_file(0)

            !$OMP PARALLEL DEFAULT(firstprivate) SHARED(Q, Q_eq_VR, VR_opt, out_var)
            !$ seed = seed + 932117 + OMP_get_thread_num()*2685821657736338717_8
            if (VR_opt.eq.0) then
                do steps=1,Ntimesteps
                    !$OMP DO schedule(dynamic, 100)
                    do i=1,Ntraj
                        dW = Wiener_step(seed, dt)
                        Q(:,i) = step(Q(:,i), k, dt, Q0, alpha, a, dW)
                    end do
                    !$OMP END DO
                    delay_counter = delay_counter + dt
                    if ((steps.eq.1).or.(delay_counter.ge.(output_delay-1.D-10)).or.(steps.eq.NTimeSteps)) then
                        call write_data_to_files_no_VR(steps)
                        if (delay_counter.ge.(output_delay-1.D-10)) then
                            delay_counter = delay_counter - output_delay
                        end if
                    end if
                    delay_counter_dist = delay_counter_dist + dt
                    if ((steps.eq.1).or.(delay_counter_dist.ge.(output_delay_dist-1.D-10)).or.(steps.eq.NTimeSteps)) then
                        call write_distribution_to_file(steps)
                        if (delay_counter_dist.ge.(output_delay_dist-1.D-10)) then
                            delay_counter_dist = delay_counter_dist - output_delay_dist
                        end if
                    end if
                end do

            elseif (VR_opt.eq.1) then
                !$OMP single
                Q_eq_VR(:,:) = Q(:,:)
                !$OMP end single
                do steps=1,Ntimesteps
                    !$OMP DO schedule(dynamic, 100)
                    do i=1,Ntraj
                        dW = Wiener_step(seed, dt)
                        Q(:,i) =  step(Q(:,i), k, dt, Q0, alpha, a, dW)
                        Q_eq_VR(:,i) = step(Q_eq_VR(:,i), dt, Q0, alpha, a, dW)
                    end do
                    !$OMP END DO
                    delay_counter = delay_counter + dt
                    if ((steps.eq.1).or.(delay_counter.ge.(output_delay-1.D-10)).or.(steps.eq.NTimeSteps)) then
                        call write_data_to_files_no_VR(steps)
                        if (delay_counter.ge.(output_delay-1.D-10)) then
                            delay_counter = delay_counter - output_delay
                        end if
                    end if
                    delay_counter_dist = delay_counter_dist + dt
                    if ((steps.eq.1).or.(delay_counter_dist.ge.(output_delay_dist-1.D-10)).or.(steps.eq.NTimeSteps)) then
                        call write_distribution_to_file(steps)
                        if (delay_counter_dist.ge.(output_delay_dist-1.D-10)) then
                            delay_counter_dist = delay_counter_dist - output_delay_dist
                        end if
                    end if
                end do

            else
                print *, "Variance Reduction option not set, place in options.inp file"
            end if
            !$OMP END PARALLEL

        end do
    else
        print *, "lookup_opt not set, place in options.inp file"
    end if

    close(unit=19)
    close(unit=20)
    close(unit=21)
    close(unit=22)
    close(unit=23)
    close(unit=24)
    close(unit=25)

    deallocate(Q)
    if (VR_opt.eq.1) then
        deallocate(Q_eq_VR)
    end if
    if (lookup_opt.eq.1) then
        deallocate(Yvals, Qvals, storage_vals)
    end if

    contains

    subroutine write_distribution_to_file(NoSteps)
        implicit none
        integer*8, intent(in) :: NoSteps

        !$OMP single
        if (dist_opt.eq.1) then
            write(25) NoSteps*dt
            write(25) Q
        elseif ((dist_opt.eq.2).and.(NoSteps.eq.NTimeSteps)) then
            write(25) NoSteps*dt
            write(25) Q
        end if
        !$OMP end single

    end subroutine

    subroutine write_data_to_files_no_VR(NoSteps)
        implicit none
        integer*8, intent(in) :: NoSteps
        call measure_shear_no_VR(out_var, Q, Q0, alpha, sr, Ntraj)

        121 format(E11.4, 2X, E15.8, 2X, E15.8)
        !$OMP single
        write(19,121) NoSteps*dt, out_var%AvgF, out_var%ErrF
        write(20,121) NoSteps*dt, out_var%AvgQ, out_var%ErrQ
        write(21,121) NoSteps*dt, out_var%S, out_var%ErrS
        write(22,121) NoSteps*dt, out_var%AvgEta, out_var%ErrEta
        write(23,121) NoSteps*dt, out_var%AvgPsi, out_var%ErrPsi
        write(24,121) NoSteps*dt, out_var%AvgPsi2, out_var%ErrPsi2
        write(40,121) NoSteps*dt, out_var%AvgChiG, out_var%ErrChiG
        write(41,121) NoSteps*dt, out_var%AvgChiTau, out_var%ErrChiTau
        !$OMP end single

    end subroutine

    subroutine write_data_to_files_with_VR(NoSteps)
        implicit none
        integer*8, intent(in) :: NoSteps
        call measure_shear_with_VR(out_var, Q, Q_eq_VR, Q0, alpha, sr, Ntraj)

        121 format(E11.4, 2X, E15.8, 2X, E15.8)
        !$OMP single
        write(19,121) NoSteps*dt, out_var%AvgF, out_var%ErrF
        write(20,121) NoSteps*dt, out_var%AvgQ, out_var%ErrQ
        write(21,121) NoSteps*dt, out_var%S, out_var%ErrS
        write(22,121) NoSteps*dt, out_var%AvgEta, out_var%ErrEta
        write(23,121) NoSteps*dt, out_var%AvgPsi, out_var%ErrPsi
        write(24,121) NoSteps*dt, out_var%AvgPsi2, out_var%ErrPsi2
        write(40,121) NoSteps*dt, out_var%AvgChiG, out_var%ErrChiG
        write(41,121) NoSteps*dt, out_var%AvgChiTau, out_var%ErrChiTau
        !$OMP end single

    end subroutine

    subroutine initialise_output_files_timestep()
        implicit none

        write(19,'(E11.4)') dt
        write(20,'(E11.4)') dt
        write(21,'(E11.4)') dt
        write(22,'(E11.4)') dt
        write(23,'(E11.4)') dt
        write(24,'(E11.4)') dt
        write(40,'(E11.4)') dt
        write(41,'(E11.4)') dt

    end subroutine

end program

