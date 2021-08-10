
"""
    ManifoldEuler

The manifold Euler algorithm for problems in the [`ExplicitManifoldODEProblemType`](@ref)
formulation.
"""
struct ManifoldEuler{TM<:AbstractManifold,TR<:AbstractRetractionMethod} <:
       OrdinaryDiffEqAlgorithm
    manifold::TM
    retraction_method::TR
end

alg_order(::ManifoldEuler) = 1

"""
    ManifoldEulerCache

Cache for [`ManifoldEuler`](@ref).
"""
struct ManifoldEulerCache <: OrdinaryDiffEqMutableCache end

"""
    ManifoldEulerConstantCache

Cache for [`ManifoldEuler`](@ref).
"""
struct ManifoldEulerConstantCache <: OrdinaryDiffEqConstantCache end

function alg_cache(
    alg::ManifoldEuler,
    u,
    rate_prototype,
    uEltypeNoUnits,
    uBottomEltypeNoUnits,
    tTypeNoUnits,
    uprev,
    uprev2,
    f,
    t,
    dt,
    reltol,
    p,
    calck,
    ::Val{true},
)
    return ManifoldEulerCache()
end

function perform_step!(integrator, cache::ManifoldEulerCache, repeat_step = false)
    @unpack t, dt, uprev, u, f, p, alg = integrator

    k = f(u, p, t)
    retract!(alg.manifold, u, u, dt * k, alg.retraction_method)

    return integrator.destats.nf += 1
end

function initialize!(integrator, cache::ManifoldEulerCache)
    integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t) # Pre-start fsal
    integrator.destats.nf += 1
    integrator.kshortsize = 1
    integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

    # Avoid undefined entries if k is an array of arrays
    integrator.fsallast = zero.(integrator.fsalfirst)
    return integrator.k[1] = integrator.fsalfirst
end


"""
    CG2

A Crouch-Grossmann algorithm of second order for problems in the
[`ExplicitManifoldODEProblemType`](@ref) formulation. See order 2 conditions discussed
in [^OwrenMarthinsen1999]. Tableau:

    0    | 0
    1/2  | 1/2  0
    ----------------
         | 0    1

[^OwrenMarthinsen1999]:
    > B. Owren and A. Marthinsen, “Runge-Kutta Methods Adapted to Manifolds and Based on
    > Rigid Frames,” BIT Numerical Mathematics, vol. 39, no. 1, pp. 116–142, Mar. 1999,
    > doi: 10.1023/A:1022325426017.

"""
struct CG2{TM<:AbstractManifold,TR<:AbstractRetractionMethod} <: OrdinaryDiffEqAlgorithm
    manifold::TM
    retraction_method::TR
end

alg_order(::CG2) = 2

"""
    CG2Cache

Cache for [`CG2`](@ref).
"""
struct CG2Cache{TX,TK2u} <: OrdinaryDiffEqMutableCache
    X1::TX
    X2u::TK2u
    X2::TX
end

function alg_cache(
    alg::CG2,
    u,
    rate_prototype,
    uEltypeNoUnits,
    uBottomEltypeNoUnits,
    tTypeNoUnits,
    uprev,
    uprev2,
    f,
    t,
    dt,
    reltol,
    p,
    calck,
    ::Val{true},
)
    return CG2Cache(allocate(rate_prototype), allocate(u), allocate(rate_prototype))
end

function initialize!(integrator, cache::CG2Cache)
    integrator.kshortsize = 2
    integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

    integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t)
    integrator.destats.nf += 1

    integrator.fsallast = zero.(integrator.fsalfirst)
    integrator.k[1] = integrator.fsalfirst
    integrator.k[2] = integrator.fsallast
    return nothing
end

function perform_step!(integrator, cache::CG2Cache, repeat_step = false)
    @unpack t, dt, uprev, u, f, p, alg = integrator

    M = alg.manifold
    f(cache.X1, u, p, t)
    dt2 = dt / 2
    retract!(M, cache.X2u, u, cache.X1 * dt2, alg.retraction_method)
    f(cache.X2, cache.X2u, p, t + dt2)
    k2t = f.f.operator_vector_transport(M, cache.X2u, cache.X2, u, p, t + dt2, t)
    retract!(M, u, u, dt * k2t, alg.retraction_method)

    return integrator.destats.nf += 2
end


"""
    CG3

A Crouch-Grossmann algorithm of second order for problems in the
[`ExplicitManifoldODEProblemType`](@ref) formulation. See tableau 6.1 of [^OwrenMarthinsen1999]:

    0     | 0
    3/4   | 3/4      0
    17/24 | 119/216  17/108  0
    ------------------------------
          | 13/51    -2/3    24/17

[^OwrenMarthinsen1999]:
    > B. Owren and A. Marthinsen, “Runge-Kutta Methods Adapted to Manifolds and Based on
    > Rigid Frames,” BIT Numerical Mathematics, vol. 39, no. 1, pp. 116–142, Mar. 1999,
    > doi: 10.1023/A:1022325426017.

"""
struct CG3{TM<:AbstractManifold,TR<:AbstractRetractionMethod} <: OrdinaryDiffEqAlgorithm
    manifold::TM
    retraction_method::TR
end

alg_order(::CG3) = 3

"""
    CG3Cache

Cache for [`CG3`](@ref).
"""
struct CG3Cache{TX,TP} <: OrdinaryDiffEqMutableCache
    X1::TX
    X2::TX
    X3::TX
    X2u::TP
    X3u::TP
end


function alg_cache(
    alg::CG3,
    u,
    rate_prototype,
    uEltypeNoUnits,
    uBottomEltypeNoUnits,
    tTypeNoUnits,
    uprev,
    uprev2,
    f,
    t,
    dt,
    reltol,
    p,
    calck,
    ::Val{true},
)
    return CG3Cache(
        allocate(rate_prototype),
        allocate(rate_prototype),
        allocate(rate_prototype),
        allocate(u),
        allocate(u),
    )
end

function perform_step!(integrator, cache::CG3Cache, repeat_step = false)
    @unpack t, dt, uprev, u, f, p, alg = integrator
    M = alg.manifold

    f(cache.X1, u, p, t)
    c2h = (3 // 4) * dt
    c3h = (17 // 24) * dt
    a21h = (3 // 4) * dt
    a31h = (119 // 216) * dt
    a32h = (17 // 108) * dt
    b1 = (13 // 51) * dt
    b2 = (-2 // 3) * dt
    b3 = (24 // 17) * dt
    retract!(M, cache.X2u, u, cache.X1 * a21h, alg.retraction_method)
    f(cache.X2, cache.X2u, p, t + c2h)
    retract!(M, cache.X3u, u, a31h * cache.X1)
    k2tk3u = f.f.operator_vector_transport(M, cache.X2u, cache.X2, cache.X3u, p, t, t + c2h)
    retract!(M, cache.X3u, cache.X3u, a32h * k2tk3u)
    f(cache.X3, cache.X3u, p, t + c3h)

    retract!(M, u, u, b1 * cache.X1, alg.retraction_method)
    X2tu = f.f.operator_vector_transport(M, cache.X2u, cache.X2, u, p, t + c2h, t)
    retract!(M, u, u, b2 * X2tu, alg.retraction_method)
    X3tu = f.f.operator_vector_transport(M, cache.X3u, cache.X3, u, p, t + c3h, t)
    retract!(M, u, u, b3 * X3tu, alg.retraction_method)

    return integrator.destats.nf += 3
end

function initialize!(integrator, cache::CG3Cache)
    integrator.kshortsize = 2
    integrator.k = typeof(integrator.k)(undef, integrator.kshortsize)

    integrator.fsalfirst = integrator.f(integrator.uprev, integrator.p, integrator.t)
    integrator.destats.nf += 1

    integrator.fsallast = zero.(integrator.fsalfirst)
    integrator.k[1] = integrator.fsalfirst
    integrator.k[2] = integrator.fsallast
    return nothing
end
