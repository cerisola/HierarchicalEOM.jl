export HEOMsolve, TimeEvolutionHEOMSol

const DEFAULT_ODE_SOLVER_OPTIONS = (abstol = 1e-8, reltol = 1e-6, save_everystep = false, save_end = true)

@doc raw"""
    struct TimeEvolutionHEOMSol

A structure storing the results and some information from solving time evolution of hierarchical equations of motion (HEOM).

# Fields (Attributes)
- `Btier` : The tier (cutoff level) for bosonic hierarchy
- `Ftier` : The tier (cutoff level) for fermionic hierarchy
- `times::AbstractVector`: The time list of the evolution.
- `ados::Vector{ADOs}`: The list of result ADOs at each time point.
- `expect::Matrix`: The expectation values corresponding to each time point in `times`.
- `retcode`: The return code from the solver.
- `alg`: The algorithm which is used during the solving process.
- `abstol::Real`: The absolute tolerance which is used during the solving process.
- `reltol::Real`: The relative tolerance which is used during the solving process.
"""
struct TimeEvolutionHEOMSol{TT<:Vector{<:Real},TS<:Vector{ADOs},TE<:Matrix{ComplexF64}}
    Btier::Int
    Ftier::Int
    times::TT
    ados::TS
    expect::TE
    retcode::Union{Nothing,Enum}
    alg::Union{Nothing,OrdinaryDiffEqAlgorithm}
    abstol::Union{Nothing,Real}
    reltol::Union{Nothing,Real}
end

function Base.show(io::IO, sol::TimeEvolutionHEOMSol)
    print(io, "Solution of hierarchical EOM\n")
    print(io, "(return code: $(sol.retcode))\n")
    print(io, "----------------------------\n")
    print(io, "Btier = $(sol.Btier)\n")
    print(io, "Ftier = $(sol.Ftier)\n")
    print(io, "num_states = $(length(sol.ados))\n")
    print(io, "num_expect = $(size(sol.expect, 1))\n")
    print(io, "ODE alg.: $(sol.alg)\n")
    print(io, "abstol = $(sol.abstol)\n")
    print(io, "reltol = $(sol.reltol)\n")
    return nothing
end

@doc raw"""
    HEOMsolve(M, ρ0, Δt, steps; e_ops, threshold, nonzero_tol, verbose, filename)
Solve the time evolution for auxiliary density operators based on propagator (generated by `FastExpm.jl`).

# Parameters
- `M::AbstractHEOMLSMatrix` : the matrix given from HEOM model
- `ρ0::Union{QuantumObject,ADOs}` : system initial state (density matrix) or initial auxiliary density operators (`ADOs`)
- `Δt::Real` : A specific time step (time interval).
- `steps::Int` : The number of time steps
- `e_ops::Union{Nothing,AbstractVector}`: List of operators for which to calculate expectation values.
- `threshold::Real` : Determines the threshold for the Taylor series. Defaults to `1.0e-6`.
- `nonzero_tol::Real` : Strips elements smaller than `nonzero_tol` at each computation step to preserve sparsity. Defaults to `1.0e-14`.
- `verbose::Bool` : To display verbose output and progress bar during the process or not. Defaults to `true`.
- `filename::String` : If filename was specified, the ADOs at each time point will be saved into the JLD2 file "filename.jld2" after the solving process.

# Notes
- The [`ADOs`](@ref) will be saved depend on the keyword argument `e_ops`.
- If `e_ops` is specified, the solution will only save the final `ADOs`, otherwise, it will save all the `ADOs` corresponding to `tlist = 0:Δt:(Δt * steps)`.
- For more details of the propagator, please refer to [`FastExpm.jl`](https://github.com/fmentink/FastExpm.jl)

# Returns
- `sol::TimeEvolutionHEOMSol` : The solution of the hierarchical EOM. See also [`TimeEvolutionHEOMSol`](@ref)
"""
function HEOMsolve(
    M::AbstractHEOMLSMatrix,
    ρ0::T_state,
    Δt::Real,
    steps::Int;
    e_ops::Union{Nothing,AbstractVector} = nothing,
    threshold = 1.0e-6,
    nonzero_tol = 1.0e-14,
    verbose::Bool = true,
    filename::String = "",
) where {T_state<:Union{QuantumObject,ADOs}}

    # check filename
    if filename != ""
        FILENAME = filename * ".jld2"
        isfile(FILENAME) && error("FILE: $(FILENAME) already exist.")
    end

    # handle initial state
    ados = (T_state <: QuantumObject) ? ADOs(ρ0, M.N, M.parity) : ρ0
    _check_sys_dim_and_ADOs_num(M, ados)
    _check_parity(M, ados)
    ρvec = _HandleVectorType(M, ados.data)

    if e_ops isa Nothing
        expvals = Array{ComplexF64}(undef, 0, steps + 1)
        is_empty_e_ops = true
    else
        Id_sys = I(prod(M.dims))
        Id_HEOM = I(M.N)
        expvals = Array{ComplexF64}(undef, length(e_ops), steps + 1)
        tr_e_ops = _generate_Eops(M, e_ops, Id_sys, Id_HEOM)
        is_empty_e_ops = isempty(e_ops)
    end

    if is_empty_e_ops
        ADOs_list = Vector{ADOs}(undef, steps + 1)
    else
        ADOs_list = Vector{ADOs}(undef, 1)
    end

    # Generate propagator
    verbose && print("Generating propagator...")
    exp_Mt = Propagator(M, Δt; threshold = threshold, nonzero_tol = nonzero_tol)
    verbose && println("[DONE]")

    # start solving
    if verbose
        print("Solving time evolution for ADOs by propagator method...\n")
        flush(stdout)
    end
    prog = ProgressBar(steps + 1, enable = verbose)
    for n in 0:steps
        # calculate expectation values
        if !is_empty_e_ops
            _expect = op -> dot(op, ρvec)
            @. expvals[:, prog.counter[]+1] = _expect(tr_e_ops)
            n == steps ? ADOs_list[1] = ADOs(ρvec, M.dims, M.N, M.parity) : nothing
        else
            ADOs_list[n+1] = ADOs(ρvec, M.dims, M.N, M.parity)
        end

        ρvec = exp_Mt * ρvec
        next!(prog)
    end

    # save ADOs to file
    if filename != ""
        verbose && print("Saving ADOs to $(FILENAME) ... ")
        jldopen(FILENAME, "w") do file
            return file["ados"] = ADOs_list
        end
        verbose && println("[DONE]\n")
    end

    return TimeEvolutionHEOMSol(
        _getBtier(M),
        _getFtier(M),
        collect(0:Δt:(Δt*steps)),
        ADOs_list,
        expvals,
        nothing,
        nothing,
        nothing,
        nothing,
    )
end

@doc raw"""
    HEOMsolve(M, ρ0, tlist; e_ops, solver, Ht, params, verbose, filename, SOLVEROptions...)
Solve the time evolution for auxiliary density operators based on ordinary differential equations.

# Parameters
- `M::AbstractHEOMLSMatrix` : the matrix given from HEOM model
- `ρ0::Union{QuantumObject,ADOs}` : system initial state (density matrix) or initial auxiliary density operators (`ADOs`)
- `tlist::AbstractVector` : Denote the specific time points to save the solution at, during the solving process.
- `e_ops::Union{Nothing,AbstractVector}`: List of operators for which to calculate expectation values.
- `solver::OrdinaryDiffEqAlgorithm` : solver in package `DifferentialEquations.jl`. Default to `DP5()`.
- `Ht::Union{Nothing,QuantumObjectEvolution}`: The time-dependent system Hamiltonian or Liouvillian. Default to `nothing`.
- `params`: Parameters to pass to the solver. This argument is usually expressed as a `NamedTuple` or `AbstractVector` of parameters. For more advanced usage, any custom struct can be used.
- `verbose::Bool` : To display verbose output and progress bar during the process or not. Defaults to `true`.
- `filename::String` : If filename was specified, the ADOs at each time point will be saved into the JLD2 file "filename.jld2" after the solving process.
- `SOLVEROptions` : extra options for solver

# Notes
- The [`ADOs`](@ref) will be saved depend on the keyword argument `saveat` in `kwargs`.
- If `e_ops` is specified, the default value of `saveat=[tlist[end]]` (only save the final `ADOs`), otherwise, `saveat=tlist` (saving the `ADOs` corresponding to `tlist`). You can also specify `e_ops` and `saveat` separately.
- The default tolerances in `kwargs` are given as `reltol=1e-6` and `abstol=1e-8`.
- For more details about `solver` please refer to [`DifferentialEquations.jl` (ODE Solvers)](https://docs.sciml.ai/DiffEqDocs/stable/solvers/ode_solve/)
- For more details about `SOLVEROptions` please refer to [`DifferentialEquations.jl` (Keyword Arguments)](https://docs.sciml.ai/DiffEqDocs/stable/basics/common_solver_opts/)

# Returns
- sol::TimeEvolutionHEOMSol : The solution of the hierarchical EOM. See also [`TimeEvolutionHEOMSol`](@ref)
"""
function HEOMsolve(
    M::AbstractHEOMLSMatrix,
    ρ0::T_state,
    tlist::AbstractVector;
    e_ops::Union{Nothing,AbstractVector} = nothing,
    solver::OrdinaryDiffEqAlgorithm = DP5(),
    Ht::Union{Nothing,QuantumObjectEvolution} = nothing,
    params = NullParameters(),
    verbose::Bool = true,
    filename::String = "",
    SOLVEROptions...,
) where {T_state<:Union{QuantumObject,ADOs}}

    # check filename
    if filename != ""
        FILENAME = filename * ".jld2"
        isfile(FILENAME) && error("FILE: $(FILENAME) already exist.")
    end

    # handle initial state
    ados = (T_state <: QuantumObject) ? ADOs(ρ0, M.N, M.parity) : ρ0
    _check_sys_dim_and_ADOs_num(M, ados)
    _check_parity(M, ados)
    u0 = _HandleVectorType(M, ados.data)

    t_l = convert(Vector{_FType(M)}, tlist) # Convert it to support GPUs and avoid type instabilities for OrdinaryDiffEq.jl

    # handle e_ops
    if e_ops isa Nothing
        expvals = Array{ComplexF64}(undef, 0, length(t_l))
        tr_e_ops = typeof(M.data)[]
        is_empty_e_ops = true
    else
        Id_sys = I(prod(M.dims))
        Id_HEOM = I(M.N)
        expvals = Array{ComplexF64}(undef, length(e_ops), length(t_l))
        tr_e_ops = _generate_Eops(M, e_ops, Id_sys, Id_HEOM)
        is_empty_e_ops = isempty(e_ops)
    end

    # handle kwargs
    haskey(SOLVEROptions, :save_idxs) &&
        throw(ArgumentError("The keyword argument \"save_idxs\" is not supported in HierarchicalEOM.jl."))
    saveat = is_empty_e_ops ? t_l : [t_l[end]]
    default_values = (DEFAULT_ODE_SOLVER_OPTIONS..., saveat = saveat)
    kwargs = merge(default_values, SOLVEROptions)
    cb = PresetTimeCallback(t_l, _HEOM_evolution_callback, save_positions = (false, false))
    kwargs2 =
        haskey(kwargs, :callback) ? merge(kwargs, (callback = CallbackSet(kwargs.callback, cb),)) :
        merge(kwargs, (callback = cb,))

    p = (
        is_empty_e_ops = is_empty_e_ops,
        tr_e_ops = tr_e_ops,
        expvals = expvals,
        prog = ProgressBar(length(t_l), enable = verbose),
        params...
    )

    # define ODE problem
    L = (Ht isa Nothing) ? M.data : _make_L(M, Ht)
    prob = ODEProblem{true,FullSpecialize}(L, u0, (t_l[1], t_l[end]), p; kwargs2...)

    # start solving ode
    if verbose
        print("Solving time evolution for ADOs by Ordinary Differential Equations method...\n")
        flush(stdout)
    end
    sol = solve(prob, solver)
    ADOs_list = map(ρvec -> ADOs(Vector{ComplexF64}(ρvec), M.dims, M.N, M.parity), sol.u)

    # save ADOs to file
    if filename != ""
        verbose && print("Saving ADOs to $(FILENAME) ... ")
        jldopen(FILENAME, "w") do file
            return file["ados"] = ADOs_list
        end
        verbose && println("[DONE]\n")
    end

    return TimeEvolutionHEOMSol(
        _getBtier(M),
        _getFtier(M),
        sol.t,
        ADOs_list,
        sol.prob.p.expvals,
        sol.retcode,
        sol.alg,
        sol.prob.kwargs[:abstol],
        sol.prob.kwargs[:reltol],
    )
end

function _generate_Eops(M::AbstractHEOMLSMatrix, e_ops, Id_sys, Id_HEOM)
    MType = _get_SciML_matrix_wrapper(M)
    tr_e_ops =
        [transpose(_Tr(M)) * MType(HEOMSuperOp(spre(op, Id_sys), EVEN, M.dims, M.N; Id_cache = Id_HEOM)).data for op in e_ops]
    return tr_e_ops
end

function _HEOM_evolution_callback(integrator)
    p = integrator.p
    prog = p.prog
    expvals = p.expvals
    tr_e_ops = p.tr_e_ops

    if !p.is_empty_e_ops
        _expect = op -> dot(op, integrator.u)
        @. expvals[:, prog.counter[]+1] = _expect(tr_e_ops)
    end
    next!(prog)
    return u_modified!(integrator, false)
end

function _make_L(M::AbstractHEOMLSMatrix, Ht::QuantumObjectEvolution)
    return M.data
end