struct DiffEqNLSolveTag end

immutable DiffCache{T<:AbstractArray, S<:AbstractArray}
    du::T
    dual_du::S
end

Base.@pure function DiffCache{chunk_size}(T, size, ::Type{Val{chunk_size}})
    DiffCache(zeros(T, size...), zeros(Dual{typeof(ForwardDiff.Tag(Void,T)),T,chunk_size}, size...))
end

Base.@pure DiffCache(u::AbstractArray) = DiffCache(eltype(u),size(u),Val{ForwardDiff.pickchunksize(length(u))})
Base.@pure DiffCache(u::AbstractArray,nlsolve) = DiffCache(eltype(u),size(u),Val{get_chunksize(nlsolve)})
Base.@pure DiffCache{CS}(u::AbstractArray,T::Type{Val{CS}}) = DiffCache(eltype(u),size(u),T)

get_du{T<:Dual}(dc::DiffCache, ::Type{T}) = dc.dual_du
get_du(dc::DiffCache, T) = dc.du

# Default nlsolve behavior, should move to DiffEqDiffTools.jl

Base.@pure determine_chunksize(u,alg::DEAlgorithm) = determine_chunksize(u,get_chunksize(alg))
Base.@pure function determine_chunksize(u,CS)
  if CS != 0
    return CS
  else
    return ForwardDiff.pickchunksize(length(u))
  end
end

function autodiff_setup{CS}(f!, initial_x::Vector,chunk_size::Type{Val{CS}})

    permf! = (fx, x) -> f!(x, fx)
    fx2 = copy(initial_x)
    jac_cfg = ForwardDiff.JacobianConfig(nothing,
                                         initial_x, initial_x,
                                         ForwardDiff.Chunk{CS}())
    g! = (x, gx) -> ForwardDiff.jacobian!(gx, permf!, fx2, x, jac_cfg)
    fg! = (x, fx, gx) -> begin
        jac_res = DiffBase.DiffResult(fx, gx)
        ForwardDiff.jacobian!(jac_res, permf!, fx2, x, jac_cfg)
        DiffBase.value(jac_res)
    end

    return DifferentiableMultivariateFunction(f!, g!, fg!)
end

function non_autodiff_setup(f!, initial_x::Vector)
  DifferentiableMultivariateFunction(f!)
end

immutable NLSOLVEJL_SETUP{CS,AD} end
Base.@pure NLSOLVEJL_SETUP(;chunk_size=0,autodiff=true) = NLSOLVEJL_SETUP{chunk_size,autodiff}()
(p::NLSOLVEJL_SETUP)(f,u0) = (res=NLsolve.nlsolve(f,u0); res.zero)
function (p::NLSOLVEJL_SETUP{CS,AD}){CS,AD}(::Type{Val{:init}},f,u0_prototype)
  if AD
    return autodiff_setup(f,u0_prototype,Val{determine_chunksize(u0_prototype,CS)})
  else
    return non_autodiff_setup(f,u0_prototype)
  end
end

get_chunksize(x) = 0
get_chunksize{CS,AD}(x::NLSOLVEJL_SETUP{CS,AD}) = CS

export NLSOLVEJL_SETUP
