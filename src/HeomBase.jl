abstract type AbstractHEOMMatrix end
size(A::AbstractHEOMMatrix) = size(A.data)

include("ADOs.jl")

spre(q::AbstractMatrix)        = kron(Matrix(I, size(q)[1], size(q)[1]), q)
spre(q::AbstractOperator)      = sparse(kron(sparse(I, size(q)[1], size(q)[1]), q.data))
spre(q::AbstractSparseMatrix)  = sparse(kron(sparse(I, size(q)[1], size(q)[1]), q))
spost(q::AbstractMatrix)       = kron(transpose(q), Matrix(I, size(q)[1], size(q)[1]))
spost(q::AbstractOperator)     = sparse(kron(transpose(q.data), sparse(I, size(q)[1], size(q)[1])))
spost(q::AbstractSparseMatrix) = sparse(kron(transpose(q), sparse(I, size(q)[1], size(q)[1])))

# generate liouvillian matrix
function liouvillian(Hsys, Jump_Ops::Vector=[], progressBar::Bool=false)
        
    N, = size(Hsys)

    L = -1im * (spre(Hsys) - spost(Hsys))
    if progressBar
        prog = Progress(length(Jump_Ops) + 1, start=1; desc="Construct Liouvillian     : ", PROGBAR_OPTIONS...)
    end
    for J in Jump_Ops
        L += spre(J) * spost(J') - 0.5 * (spre(J' * J) + spost(J' * J))
        if progressBar
            next!(prog)
        end
    end
    return L
end

# func. for solving evolution ODE
function hierachy!(dρ, ρ, L, t)
    @inbounds dρ .= L * ρ
end

"""
# `evolution(M, ρ0, tlist; [solver, reltol, abstol, maxiters, progressBar, SOLVEROptions...])`
Solve the evolution (ODE problem) using HEOM model.

## Parameters
- `M::AbstractHEOMMatrix` : the matrix given from HEOM model
- `ρ0::Union{AbstractMatrix, AbstractOperator}` : initial state (density matrix)
- `tlist::AbstractVector` : Denote the specific time points to save the solution at, during the solving process.
- `solver` : solver in package `DifferentialEquations.jl`. Default to `DP5()`.
- `reltol` : Relative tolerance in adaptive timestepping. Default to 1.0e-6.
- `abstol` : Absolute tolerance in adaptive timestepping. Default to 1.0e-8.
- `maxiters` : Maximum number of iterations before stopping. Default to 1e5.
- `progressBar::Bool` : Display progress bar during the process or not. Defaults to `true`.
- `SOLVEROptions` : extra options for solver 

## Returns
- `ρ_list`    : The reduced density matrices in each time point.
- `ADOs_list` : The auxiliary density operators in each time point.
"""
function evolution(
        M::AbstractHEOMMatrix, 
        ρ0::Union{AbstractMatrix, AbstractOperator}, 
        tlist::AbstractVector;
        solver = DP5(),
        reltol = 1.0e-6,
        abstol = 1.0e-8,
        maxiters = 1e5,
        progressBar::Bool = true,
        SOLVEROptions...
    )

    (N1, N2) = size(ρ0)
    if (N1 != M.N_sys) || (N2 != M.N_sys)
        error("The size of initial state ρ0 is incorrect.")
    end

    # setup ρ_he and ρlist
    ρ_list::Vector{SparseMatrixCSC{ComplexF64, Int64}} = []
    ADOs_list::Vector{SparseMatrixCSC{ComplexF64, Int64}} = []
    ρ_he::SparseVector{ComplexF64, Int64} = spzeros(M.N_he * M.sup_dim)
    if typeof(ρ0) <: AbstractMatrix
        push!(ρ_list, ρ0)

        ρ_he[1:(M.sup_dim)] .= sparsevec(ρ0)
    else
        push!(ρ_list, ρ0.data)

        ρ_he[1:(M.sup_dim)] .= sparsevec(ρ0.data)
    end
    push!(ADOs_list, reshape(ρ_he, M.sup_dim, M.N_he))
    
    # setup integrator
    dt_list = diff(tlist)
    integrator = init(
            ODEProblem(hierachy!, ρ_he, (tlist[1], tlist[end]), M.data),
            solver;
            reltol = reltol,
            abstol = abstol,
            maxiters = maxiters,
            SOLVEROptions...
    )
    
    # start solving ode
    print("Start solving hierachy equation of motions...")
    if progressBar
        print("\n")
        prog = Progress(length(tlist); start=1, desc="Progress : ", PROGBAR_OPTIONS...)
    end
    flush(stdout)
    for dt in dt_list
        step!(integrator, dt, true)
        
        # save the reduced density matrix and ADOs
        ρ_ADOs = reshape(integrator.u, M.sup_dim, M.N_he)
        push!(ρ_list, reshape(ρ_ADOs[:,1], M.N_sys, M.N_sys))
        push!(ADOs_list, ρ_ADOs)
    
        if progressBar
            next!(prog)
        end
    end

    println("[DONE]\n")
    flush(stdout)

    return ρ_list, ADOs_list
end