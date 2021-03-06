#######################################################################
# Kernel Polynomial Method : momenta
#######################################################################
struct MomentaKPM{T,B<:Tuple}
    μlist::Vector{T}
    bandbracket::B
end
struct KPMBuilder{T,K}
    μlist::Vector{T}
    ket::K
    ket0::K
    ket1::K
    ket2::K
    ketL::K
end
KPMBuilder(μlist, ket) =
    KPMBuilder(μlist, ket, similar(ket), similar(ket), similar(ket), similar(ket))

ketundef(h::AbstractMatrix{T}) where {T<:Number} =
    Vector{T}(undef, size(h, 2))
ketundef(h::AbstractMatrix{S}) where {N,T,S<:SMatrix{N,N,T}} =
    Vector{SVector{N,T}}(undef, size(h, 2))

iscompatibleket(h::AbstractMatrix{T1}, ket::AbstractArray{T2}) where {T1,T2} =
    _iscompatibleket(T1, T2)
_iscompatibleket(::Type{T1}, ::Type{T2}) where {T1<:Real, T2<:Real} = true
_iscompatibleket(::Type{T1}, ::Type{T2}) where {T1<:Number, T2<:Complex} = true
_iscompatibleket(::Type{S1}, ::Type{S2}) where {N, S1<:SMatrix{N,N}, S2<:SVector{N}} =
    _iscompatibleket(eltype(S1), eltype(S2))
_iscompatibleket(::Type{S1}, ::Type{S2}) where {N, S1<:SMatrix{N,N}, S2<:SMatrix{N}} =
    _iscompatibleket(eltype(S1), eltype(S2))
_iscompatibleket(t1, t2) = false

"""
    momentaKPM(h::AbstractMatrix, A = I; ket = missing, order = 10, randomkets = 1, bandrange = missing)

Compute the Kernel Polynomial Method (KPM) momenta `μ_n = ⟨ket|A T_n(h)|ket⟩/⟨ket|ket⟩` where `T_n(x)`
is the Chebyshev polynomial of order `n`, for a given `ket::AbstractVector`, hamiltonian `h`, and
observable `A`. If `ket` is `missing`, momenta are computed by means of a stochastic trace
`μ_n = Tr[A T_n(h)] ≈ ∑ₐ⟨a|A T_n(h)|a⟩/N` over `N = randomkets` normalized random `|a⟩`.
Furthermore, the trace over a specific set of kets can also be computed; in this case
`ket::AbstractMatrix` must be a matrix where the columns are the kets involved in the calculation.

The order of the Chebyshev expansion is `order`. The `bandbrange = (ϵmin, ϵmax)` should completely encompass
the full bandwidth of `hamiltonian`. If `missing` it is computed automatically using `ArnoldiMethods` (must be loaded).

# Example
```
julia> h = LatticePresets.cubic() |> hamiltonian(hopping(1)) |> unitcell(region = RegionPresets.sphere(10));

julia> momentaKPM(bloch(h), bandrange = (-6,6))
Elsa.MomentaKPM{Float64}([0.9594929736144973, -0.005881595972403821, -0.4933354572913581, 0.00359537502632597, 0.09759451291347333, -0.0008081453185250322, -0.00896262538765363, 0.00048205637037715177, -0.0003705198310034668, 9.64901673962623e-20, 9.110915988898614e-18], (0.0, 6.030150753768845))
```
"""
function momentaKPM(h::AbstractMatrix{Tv}, A = one(Tv) * I;
                    ket = missing, randomkets = 1, order = 10, bandrange = missing) where {Tv}
    eh = eltype(eltype(h))
    aA = eltype(eltype(A))
    μlist = zeros(promote_type(eh, aA), order + 1)
    bandbracket = bandbracketKPM(h, bandrange)
    ket´ = ket === missing ? ketundef(h) : ket
    iscompatibleket(h, ket´) || throw(ArgumentError("ket is incomatible with Hamiltonian"))
    builder = KPMBuilder(μlist, ket´)
    if ket === missing
        pmeter = Progress(order * randomkets, "Averaging moments: ")
        for n in 1:randomkets
            randomize!(builder.ket)
            addmomentaKPM!(builder, h, A, bandbracket, pmeter)
        end
        μlist ./= randomkets
    else
        pmeter = Progress(order, "Computing moments: ")
        addmomentaKPM!(builder, h, A, bandbracket, pmeter)
    end
    return MomentaKPM(jackson!(μlist), bandbracket)
end

function addmomentaKPM!(b::KPMBuilder, h, A::UniformScaling, bandbracket, pmeter)
    μlist, ket, ket0, ket1, ket2 = b.μlist, b.ket, b.ket0, b.ket1, b.ket2
    order = length(μlist) - 1
    ket0 .= ket
    mulscaled!(ket1, h, ket0, bandbracket)
    μlist[1]  += μ0 = 1.0
    μlist[2]  += μ1 = proj(ket0, ket1)
    for n in 3:2:(order+1)
        μlist[n] += 2 * proj(ket1, ket1) - μ0
        n + 1 > order + 1 && break
        mulscaled!(ket2, h, ket1, bandbracket)
        @. ket2 = 2 * ket2 - ket0
        μlist[n + 1] += 2 * proj(ket2, ket1) - μ1
        ket0, ket1, ket2 = ket1, ket2, ket0
        ProgressMeter.next!(pmeter; showvalues = ())
        ProgressMeter.next!(pmeter; showvalues = ()) # twice because of 2-step
    end
    A.λ ≈ 1 || (μlist .*= A.λ)
    return μlist
end

function addmomentaKPM!(b::KPMBuilder, h, A::AbstractMatrix, bandbracket, pmeter)
    μlist, ket, ket0, ket1, ket2, ketL = b.μlist, b.ket, b.ket0, b.ket1, b.ket2, b.ketL
    order = length(μlist) - 1
    ket0 .= ket
    mul!(ketL, A', ket)
    mulscaled!(ket1, h, ket0, bandbracket)
    μlist[1] += proj(ketL, ket0)
    μlist[2] += proj(ketL, ket1)
    for n in 3:(order+1)
        mulscaled!(ket2, h, ket1, bandbracket)
        @. ket2 = 2 * ket2 - ket0
        μlist[n] += proj(ketL, ket2)
        n + 1 > order + 1 && break
        ket0, ket1, ket2 =  ket1, ket2, ket0
        ProgressMeter.next!(pmeter; showvalues = ())
    end
    return μlist
end

function mulscaled!(y, h, x, (center, halfwidth))
    mul!(y, h, x)
    @. y = (y - center * x) / halfwidth
    return y
end

# This is equivalent to tr(ket1'*ket2) for matrices, and ket1'*ket2 for vectors
proj(ket1, ket2) = dot(vec(ket1), vec(ket2))

function randomize!(v::AbstractVector{T}) where {T}
    for i in eachindex(v)
        v[i] = _isreal(T) ? randn(T) : exp.((2π * im) .* rand(T))
    end
    normalize!(v)
    return v
end

_isreal(::Type{<:Real}) = true
_isreal(::Type{<:Complex}) = false
_isreal(::Type{S}) where {S<:SArray} = _isreal(eltype(S))

function jackson!(μ::AbstractVector)
    order = length(μ) - 1
    for n in eachindex(μ)
        μ[n] *= ((order - n + 1) * cos(π * n / (order + 1)) +
                sin(π * n / (order + 1)) * cot(π / (order + 1))) / (order + 1)
    end
    return μ
end

function bandbracketKPM(h, ::Missing)
    @warn "Computing spectrum bounds... Consider using the `bandrange` kwargs for faster performance."
    checkloaded(:ArnoldiMethod)
    decompl, _ = Main.ArnoldiMethod.partialschur(h, nev=1, tol=1e-4, which = Main.ArnoldiMethod.LR());
    decomps, _ = Main.ArnoldiMethod.partialschur(h, nev=1, tol=1e-4, which = Main.ArnoldiMethod.SR());
    ϵmax = real(decompl.eigenvalues[1])
    ϵmin = real(decomps.eigenvalues[1])
    @warn  "Computed bandrange = ($ϵmin, $ϵmax)"
    return bandbracketKPM(h, (ϵmin, ϵmax))
end

bandbracketKPM(h, (ϵmin, ϵmax), pad = 0.01) = ((ϵmax + ϵmin) / 2.0, (ϵmax - ϵmin) / (2.0 - pad))

#######################################################################
# Kernel Polynomial Method : observables
#######################################################################
"""
    dosKPM(h::AbstractMatrix; resolution = 2, kw...)

Compute, using the Kernel Polynomial Method (KPM), the local density of states `ρ(ϵ) =
⟨ket|δ(ϵ-h)|ket⟩/⟨ket|ket⟩` for a given `ket::AbstractVector` and hamiltonian `h`, or the
global density of states `ρ(ϵ) = Tr[δ(ϵ-h)]` if `ket` is `missing`.

If `ket` is an `AbstractMatrix` it evaluates the trace over the set of kets in `ket` (see
`momentaKPM` and its options `kw` for further details). The result is a tuple of energy
points `xk::Vector` and real `ρ::Vector` values (any imaginary part in ρ is dropped), where
the number of energy points `xk` is `order * resolution`, rounded to the closest integer.

    dosKPM(μ::MomentaKPM; resolution = 2)

Same as above with momenta `μ` as input.

    dosKPM(h::Hamiltonian; kw...)

Equivalent to `dosKPM(bloch(h); kw...)` for finite hamiltonians (zero dimensional).
"""
dosKPM(h::AbstractMatrix; resolution = 2, kw...) =
    dosKPM(momentaKPM(h; kw...), resolution = resolution)

dosKPM(μ::MomentaKPM; resolution = 2) = real.(densityKPM(μ; resolution = resolution))

function dosKPM(h::Hamiltonian{<:Lattice,L}; kw...) where {L}
    iszero(L) ||
        throw(ArgumentError("Hamiltonian is defined on an infinite lattice. Convert it to a matrix first using `bloch(h, φs...)`"))
    return dosKPM(bloch(h); kw...)
end

"""
    densityKPM(h::AbstractMatrix, A; resolution = 2, kw...)

Compute, using the Kernel Polynomial Method (KPM), the local spectral density of an operator
`A` `ρ_A(ϵ) = ⟨ket|A δ(ϵ-h)|ket⟩/⟨ket|ket⟩` for a given `ket::AbstractVector` and
hamiltonian `h`, or the global spectral density `ρ_A(ϵ) = Tr[A δ(ϵ-h)]` if `ket` is
`missing`. If `ket` is an `AbstractMatrix` it evaluates the trace over the set of kets in
`ket` (see `momentaKPM` and its options `kw` for further details). A tuple of energy points
`xk` and `ρ_A` values is returned where the number of energy points `xk` is `order *
resolution`, rounded to the closest integer.

    densityKPM(momenta::MomentaKPM; resolution = 2)

Same as above with the KPM momenta as input (see `momentaKPM`).

    densityKPM(h::Hamiltonian, A::Hamiltonian; kw...)

Equivalent to `densityKPM(bloch(h), bloch(A); kw...)` for finite Hamiltonians (zero dimensional).
"""
densityKPM(h::AbstractMatrix, A; resolution = 2, kw...) =
    densityKPM(momentaKPM(h, A; kw...); resolution = resolution)

function densityKPM(h::Hamiltonian{<:Lattice,L1}, A::Hamiltonian{<:Lattice,L2}; kw...) where {L1,L2}
    (iszero(L1) && iszero(L2)) ||
        throw(ArgumentError("Hamiltonians are defined on an infinite lattice. Convert them to matrices first using `bloch(h, φs...)`"))
    return densityKPM(bloch(h), bloch(A); kw...)
end

function densityKPM(momenta::MomentaKPM{T}; resolution = 2) where {T}
    checkloaded(:FFTW)
    (center, halfwidth) = momenta.bandbracket
    numpoints = round(Int, length(momenta.μlist) * resolution)
    ρlist = zeros(T, numpoints)
    copyto!(ρlist, momenta.μlist)
    Main.FFTW.r2r!(ρlist, Main.FFTW.REDFT01, 1)  # DCT-III in FFTW
    xk = [cos(π * (k + 0.5) / numpoints) for k in 0:numpoints - 1]
    @. ρlist = center + halfwidth * ρlist / (π * sqrt(1.0 - xk^2))
    @. xk = center + halfwidth * xk
    return xk, ρlist
end

"""
    averageKPM(h::AbstractMatrix, A; kBT = 0, Ef = 0, kw...)

Compute, using the Kernel Polynomial Method (KPM), the thermal expectation value `<A> = Σ_k
f(E_k) <k|A|k> =  ∫dE f(E) Tr [A δ(E-H)] = Tr [A f(H)]` for a given hermitian operator `A`
and a hamiltonian `h` (see `momentaKPM` and its options `kw` for further details).
`f(E)` is the Fermi-Dirac distribution function, `kBT` is the temperature in energy
units and `Ef` the Fermi energy.

    averageKPM(μ::MomentaKPM, A; kBT = 0, Ef = 0)

Same as above with the KPM momenta as input (see `momentaKPM`).

    averageKPM(h::Hamiltonian, A::Hamiltonian; kw...)

Equivalent to `averageKPM(bloch(h), bloch(A); kw...)` for finite Hamiltonians (zero
dimensional).
"""
averageKPM(h::AbstractMatrix, A; kBT = 0, Ef = 0, kw...) = averageKPM(momentaKPM(h, A; kw...); kBT = kBT, Ef = Ef)

function averageKPM(h::Hamiltonian{<:Lattice,L1}, A::Hamiltonian{<:Lattice,L2};  kw...) where {L1,L2}
    (iszero(L1) && iszero(L2)) ||
        throw(ArgumentError("Hamiltonians are defined on an infinite lattice. Convert them to matrices first using `bloch(h, φs...)`"))
    return averageKPM(bloch(h), bloch(A); kw...)
end

function averageKPM(momenta::MomentaKPM{T}; kBT = 0.0, Ef = 0.0) where {T}
    (center, halfwidth) = momenta.bandbracket
    order = length(momenta.μlist) - 1
    if !iszero(kBT)
        @warn "Finite temperature requires numerical evaluation of the integrals"
        checkloaded(:QuadGK)
    end
    average = sum(n -> momenta.μlist[n + 1] * fermicheby(n, Ef, kBT, center, halfwidth), 0:order)
    return average
end

# Pending issue: Unexpected behaviour with center != 0.
function fermicheby(n, Ef, kBT, center, halfwidth)
    kBT´ = kBT / halfwidth;
    Ef´ = (Ef - center) / halfwidth;
    if kBT´ == 0
        int = n == 0 ? 0.5+asin(Ef´)/π : -2.0*sin(n*acos(Ef´))/(n*π)
    else
        η = 1e-10
        int = Main.QuadGK.quadgk(E´ -> _intfermi(n, E´, Ef´, kBT´), -1.0+η, 1.0-η, atol= 1e-10, rtol=1e-10)[1]
    end
    return int
end

_intfermi(n, E´, Ef´, kBT´) = fermifun(E´, Ef´, kBT´) * 2/(π*(1-E´^2)^(1/2)) * chebypol(n, E´) / (1+(n == 0 ? 1 : 0))

fermifun(E´, Ef´, kBT´) = kBT´ == 0 ? (E´<Ef´ ? 1 : 0) : (1/(1+exp((E´-Ef´)/(kBT´))))

function chebypol(m::Int, x::T) where {T<:Number}
    cheby0 = one(T)
    cheby1 = x
    if m == 0
        chebym = cheby0
    elseif m == 1
        chebym = cheby1
    else
        for i in 2:m
            chebym = 2x * cheby1 - cheby0
            cheby0, cheby1 = cheby1, chebym
        end
    end
    return chebym
end
