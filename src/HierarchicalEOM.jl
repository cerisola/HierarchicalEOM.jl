module HierarchicalEOM
    import Reexport: @reexport
    
    export 
        Bath, HeomAPI, Spectrum

    # sub-module HeomBase for HierarchicalEOM
    module HeomBase
        import Pkg
        import LinearAlgebra: BLAS
        import Crayons: Crayon

        include("HeomBase.jl")
    end
    import .HeomBase.versioninfo as versioninfo
    import .HeomBase.print_logo  as print_logo
    
    # sub-module Bath for HierarchicalEOM
    module Bath
        import Base: show, length, getindex, lastindex, iterate, checkbounds
        import LinearAlgebra: I, kron, ishermitian, eigvals
        import SparseArrays: sparse, SparseMatrixCSC
        import ..HeomBase: HandleMatrixType

        export 
            AbstractBath, BosonBath, BosonBathRWA, FermionBath, Exponent, C,
            AbstractBosonBath, bosonReal, bosonImag, bosonRealImag, bosonAbsorb, bosonEmit,
            AbstractFermionBath, fermionAbsorb, fermionEmit,
            spre, spost,
            Boson_DrudeLorentz_Matsubara, Boson_DrudeLorentz_Pade, 
            Fermion_Lorentz_Matsubara, Fermion_Lorentz_Pade

        include("Bath.jl")
        include("bath_correlation_functions/bath_correlation_func.jl")
    end
    @reexport using .Bath
    
    # sub-module HeomAPI for HierarchicalEOM
    module HeomAPI
        using ..Bath
        import Base: ==, show, length, size, getindex, keys, setindex!, lastindex, iterate, checkbounds, hash, copy, eltype
        import Base.Threads: @threads, threadid, nthreads, lock, unlock, SpinLock
        import LinearAlgebra: I, kron, tr
        import SparseArrays: sparse, spzeros, sparsevec, reshape, SparseVector, SparseMatrixCSC, AbstractSparseMatrix
        import ProgressMeter: Progress, next!
        import FastExpm: fastExpm
        import ..HeomBase: PROGBAR_OPTIONS, HandleMatrixType, _HandleFloatType, _check_sys_dim_and_ADOs_num

        # for solving time evolution
        import SciMLOperators: MatrixOperator
        import OrdinaryDiffEq: ODEProblem, init, DP5, step!
        import JLD2: jldopen

        # for solving steady state
        import LinearSolve: LinearProblem, init, solve!, UMFPACKFactorization
        import OrdinaryDiffEq: SteadyStateProblem, solve
        import SteadyStateDiffEq: DynamicSS

        export
            AbstractHEOMLSMatrix, M_S, M_Boson, M_Fermion, M_Boson_Fermion,
            AbstractParity, OddParity, EvenParity, value, ODD, EVEN,
            ADOs, getRho, getADO, Expect,
            Nvec, AbstractHierarchyDict, HierarchyDict, MixHierarchyDict, getIndexEnsemble,
            Propagator, addBosonDissipator, addFermionDissipator, addTerminator,
            evolution, SteadyState

        include("heom_api.jl")
    end
    @reexport using .HeomAPI

    # sub-module Spectrum for HierarchicalEOM
    module Spectrum
        import ..HeomAPI: AbstractHEOMLSMatrix, OddParity, ADOs, spre, _HandleVectorType
        import LinearAlgebra: I, kron
        import SparseArrays: sparse, sparsevec, SparseMatrixCSC
        import LinearSolve: LinearProblem, init, solve!, UMFPACKFactorization
        import ProgressMeter: Progress, next!        
        import ..HeomBase: PROGBAR_OPTIONS, HandleMatrixType, _HandleFloatType, _check_sys_dim_and_ADOs_num

        export spectrum, PowerSpectrum, DensityOfStates

        include("Spectrum.jl")
    end
    @reexport using .Spectrum

    include("precompile.jl")
end
