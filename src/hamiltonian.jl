#######################################################################
# Hamiltonian
#######################################################################
struct HamiltonianHarmonic{L,M,A<:AbstractMatrix{M}}
    dn::SVector{L,Int}
    h::A
end

struct Hamiltonian{LA<:AbstractLattice,L,M,A<:Union{Missing,AbstractMatrix},H<:HamiltonianHarmonic{L,M,A},F<:Union{Missing,Field}}
    lattice::LA
    harmonics::Vector{H}
    field::F
    matrix::A
end

function Hamiltonian(lat, hs::Vector{H}, field, n::Int, m::Int) where {L,M,H<:HamiltonianHarmonic{L,M}}
    isempty(hs) && push!(hs, H(zero(SVector{L,Int}), empty_sparse(M, n, m)))
    sort!(hs, by = h -> abs.(h.dn))
    return Hamiltonian(lat, hs, field)
end
Hamiltonian(lat::Superlattice, hs, field) = Hamiltonian(lat, hs, field, missing)
Hamiltonian(lat::Lattice, hs, field) = Hamiltonian(lat, hs, field, optimized_h0(hs))

function Base.show(io::IO, ham::Hamiltonian)
    i = get(io, :indent, "")
    print(io, i, summary(ham), "\n",
"$i  Bloch harmonics  : $(length(ham.harmonics)) ($(displaymatrixtype(ham)))
$i  Harmonic size    : $((n -> "$n × $n")(nsites(ham)))
$i  Elements         : $(displayelements(ham))
$i  Onsites          : $(nonsites(ham))
$i  Hoppings         : $(nhoppings(ham))
$i  Coordination     : $(nhoppings(ham) / nsites(ham))")
end

Base.show(io::IO, h::HamiltonianHarmonic{L,M}) where {L,M} = print(io,
"HamiltonianHarmonic{$L,$(eltype(M))} with dn = $(Tuple(h.dn)) and elements:", h.h)

Base.summary(::Hamiltonian{LA}) where {E,L,LA<:Lattice{E,L}} =
    "Hamiltonian{<:Lattice} : $(L)D Hamiltonian on a $(L)D Lattice in $(E)D space"

Base.summary(::Hamiltonian{LA}) where {E,L,T,L´,LA<:Superlattice{E,L,T,L´}} =
    "Hamiltonian{<:Superlattice} : $(L)D Hamiltonian on a $(L´)D Superlattice in $(E)D space"

matrixtype(::Hamiltonian{LA,L,M,A}) where {LA,L,M,A} = A
displaymatrixtype(h::Hamiltonian) = displaymatrixtype(matrixtype(h))
displaymatrixtype(::Type{<:SparseMatrixCSC}) = "SparseMatrixCSC, sparse"
displaymatrixtype(::Type{<:Array}) = "Matrix, dense"
displaymatrixtype(A::Type{<:AbstractArray}) = string(A)
displayelements(h::Hamiltonian) = displayelements(blocktype(h))
displayelements(::Type{<:SMatrix{N,N}}) where {N} = "$N × $N blocks"
displayelements(::Type{<:Number}) = "scalars"

# work matrix to avoid reallocations when summing harmonics
function optimized_h0(hs::Vector{HamiltonianHarmonic{L,M,A}}) where {L,M,A<:SparseMatrixCSC}
    Tv = eltype(M)
    h0 = first(hs)
    n, m = size(h0.h)
    iszero(h0.dn) || throw(ArgumentError("First Hamiltonian harmonic is not the fundamental"))
    nh = length(hs)
    builder = SparseMatrixBuilder{M}(n, m)
    for col in 1:m
        for i in eachindex(hs)
            h = hs[i].h
            for p in nzrange(h, col)
                v = i == 1 ? nonzeros(h)[p] : zero(M)
                row = rowvals(h)[p]
                pushtocolumn!(builder, row, v, false) # skips repeated rows
            end
        end
        finalisecolumn!(builder)
    end
    ho = sparse(builder)
    return ho
end

# Internal API #

blocktype(h::Hamiltonian{LA,L,M}) where {LA,L,M} = M
isnumblocktype(h::Hamiltonian) = isnumblocktype(blocktype(h))
isnumblocktype(h::Number) = true
isnumblocktype(h) = false

function nhoppings(ham::Hamiltonian)
    count = 0
    for h in ham.harmonics
        count += iszero(h.dn) ? (_nnz(h.h) - _nnzdiag(h.h)) : _nnz(h.h)
    end
    return count
end

function nonsites(ham::Hamiltonian)
    count = 0
    for h in ham.harmonics
        iszero(h.dn) && (count += _nnzdiag(h.h))
    end
    return count
end

_nnz(h::SparseMatrixCSC) = nnz(h)
_nnz(h::Matrix) = count(!iszero, h)

function _nnzdiag(s::SparseMatrixCSC)
    count = 0
    rowptrs = rowvals(s)
    for col in 1:size(s,2)
        for ptr in nzrange(s, col)
            rowptrs[ptr] == col && (count += 1; break)
        end
    end
    return count
end
_nnzdiag(s::Matrix) = count(!iszero, s[i,i] for i in 1:minimum(size(s)))

nsites(h::Hamiltonian) = isempty(h.harmonics) ? 0 : size(first(h.harmonics).h, 1)

# External API #
"""
    hamiltonian(lat, models...; type, field = missing)

Create a `Hamiltonian` by additively applying `models` to the lattice `lat` (see `hopping`
and `onsite` for details on building tightbinding models).

The elements of the Hamiltonian are of type `type` (`Complex{T}` by default), or
`SMatrix{N,N,type}`, depending on the maximum number `N` of orbitals in the sublattice of
`lat`. The `model` must match said orbitals.

Advanced use: if a `field = f(r,dr,h)` function is given, it will modify the hamiltonian
element `h` operating on sites `r₁` and `r₂`, where `r = (r₁ + r₂)/2` and `dr = r₂ - r₁`.
In combination with `supercell`, it allows to do matrix-free operations including position-
dependent perturbations (e.g. disorder, gauge fields).

    h(ϕ₁, ϕ₂, ...)
    h((ϕ₁, ϕ₂, ...))

Yields the Bloch Hamiltonian matrix `bloch(h, (ϕ₁, ϕ₂, ...))` of a `h::Hamiltonian` on an
`L`D lattice. See also `bloch!` for a non-allocating version of `bloch`.

    hamiltonian(lat, func::Function, models...; kw...)

For a function of the form `func(;params...)::AbstractTightbindingModel`, this produces a
`h::ParametricHamiltonian` that efficiently generates a `Hamiltonian` when calling it as in
`h(;params...)` with specific parameters as keyword arguments `params`. Additionally,
`h(ϕ₁, ϕ₂, ...; params...)` generates the corresponding Bloch Hamiltonian matrix.

    lat |> hamiltonian([func, ] models...)

Functional form of `hamiltonian`, equivalent to `hamiltonian(lat, args...)`

# Examples
```jldoctest
julia> hamiltonian(LatticePresets.honeycomb(), hopping(1, range = 1/√3))
Hamiltonian{<:Lattice} : 2D Hamiltonian on a 2D Lattice in 2D space
  Bloch harmonics  : 5 (SparseMatrixCSC, sparse)
  Harmonic size    : 2 × 2
  Elements         : scalars
  Onsites          : 0
  Hoppings         : 6
  Coordination     : 3.0

julia> hopfunc(;k = 0) = hopping(k);

julia> hamiltonian(LatticePresets.square(), hopfunc, onsite(1) + hopping(2))
Parametric Hamiltonian{<:Lattice} : 2D Hamiltonian on a 2D Lattice in 2D space
  Bloch harmonics  : 5 (SparseMatrixCSC, sparse)
  Harmonic size    : 1 × 1
  Elements         : scalars
  Onsites          : 1
  Hoppings         : 4
  Coordination     : 4.0
```
"""
hamiltonian(lat::AbstractLattice, t::AbstractTightbindingModel...; kw...) =
    hamiltonian(lat, TightbindingModel(t...); kw...)
hamiltonian(lat::AbstractLattice, m::TightbindingModel; type::Type = Complex{numbertype(lat)}, kw...) =
    hamiltonian_sparse(blocktype(lat, type), lat, m; kw...)

hamiltonian(lat::AbstractLattice, f::Function, ts::AbstractTightbindingModel...;
            type::Type = Complex{numbertype(lat)}, kw...) =
    parametric_hamiltonian(blocktype(lat, type), lat, f, TightbindingModel(ts...); kw...)

hamiltonian(t::AbstractTightbindingModel...; kw...) =
    z -> hamiltonian(z, t...; kw...)
hamiltonian(f::Function, t::AbstractTightbindingModel...; kw...) =
    z -> hamiltonian(z, f, t...; kw...)
hamiltonian(h::Hamiltonian) =
    z -> hamiltonian(z, h)

(h::Hamiltonian)(phases...) = bloch(h, phases...)

Base.Matrix(h::Hamiltonian) = Hamiltonian(h.lattice, Matrix.(h.harmonics), h.field, Matrix(h.matrix))
Base.Matrix(h::HamiltonianHarmonic) = HamiltonianHarmonic(h.dn, Matrix(h.h))

Base.copy(h::Hamiltonian) = Hamiltonian(h.lattice, copy.(h.harmonics), h.field)
Base.copy(h::HamiltonianHarmonic) = HamiltonianHarmonic(h.dn, copy(h.h))

Base.size(h::Hamiltonian, n) = size(first(h.harmonics).h, n)
Base.size(h::Hamiltonian) = size(first(h.harmonics).h)
Base.size(h::HamiltonianHarmonic, n) = size(h.h, n)
Base.size(h::HamiltonianHarmonic) = size(h.h)

#######################################################################
# auxiliary types
#######################################################################
struct IJV{L,M}
    dn::SVector{L,Int}
    i::Vector{Int}
    j::Vector{Int}
    v::Vector{M}
end

struct IJVBuilder{L,M,E,T,LA<:AbstractLattice{E,L,T}}
    lat::LA
    ijvs::Vector{IJV{L,M}}
    kdtrees::Vector{KDTree{SVector{E,T},Euclidean,T}}
end

IJV{L,M}(dn::SVector{L} = zero(SVector{L,Int})) where {L,M} =
    IJV(dn, Int[], Int[], M[])

function IJVBuilder{M}(lat::AbstractLattice{E,L,T}) where {E,L,T,M}
    ijvs = IJV{L,M}[]
    kdtrees = Vector{KDTree{SVector{E,T},Euclidean,T}}(undef, nsublats(lat))
    return IJVBuilder(lat, ijvs, kdtrees)
end

function Base.getindex(b::IJVBuilder{L,M}, dn::SVector{L2,Int}) where {L,L2,M}
    L == L2 || throw(error("Tried to apply an $L2-dimensional model to an $L-dimensional lattice"))
    for e in b.ijvs
        e.dn == dn && return e
    end
    e = IJV{L,M}(dn)
    push!(b.ijvs, e)
    return e
end

Base.length(h::IJV) = length(h.i)
Base.isempty(h::IJV) = length(h) == 0
Base.copy(h::IJV) = IJV(h.dn, copy(h.i), copy(h.j), copy(h.v))

function Base.resize!(h::IJV, n)
    resize!(h.i, n)
    resize!(h.j, n)
    resize!(h.v, n)
    return h
end

Base.push!(h::IJV, (i, j, v)) = (push!(h.i, i); push!(h.j, j); push!(h.v, v))

#######################################################################
# hamiltonian_sparse
#######################################################################
function hamiltonian_sparse(::Type{M}, lat::AbstractLattice{E,L}, model; field = missing) where {E,L,M}
    builder = IJVBuilder{M}(lat)
    applyterms!(builder, terms(model)...)
    HT = HamiltonianHarmonic{L,M,SparseMatrixCSC{M,Int}}
    n = nsites(lat)
    harmonics = HT[HT(e.dn, sparse(e.i, e.j, e.v, n, n)) for e in builder.ijvs if !isempty(e)]
    return Hamiltonian(lat, harmonics, Field(field, lat), n, n)
end

applyterms!(builder, terms...) = foreach(term -> applyterm!(builder, term), terms)

function applyterm!(builder::IJVBuilder{L,M}, term::OnsiteTerm) where {L,M}
    lat = builder.lat
    for s in sublats(term, lat)
        is = siterange(lat, s)
        dn0 = zero(SVector{L,Int})
        ijv = builder[dn0]
        offset = lat.unitcell.offsets[s]
        for i in is
            r = lat.unitcell.sites[i]
            vs = orbsized(term(r), lat.unitcell.orbitals[s])
            v = padtotype(vs, M)
            term.forcehermitian ? push!(ijv, (i, i, 0.5 * (v + v'))) : push!(ijv, (i, i, v))
        end
    end
    return nothing
end

function applyterm!(builder::IJVBuilder{L,M}, term::HoppingTerm) where {L,M}
    checkinfinite(term)
    lat = builder.lat
    for (s1, s2) in sublats(term, lat)
        is, js = siterange(lat, s1), siterange(lat, s2)
        dns = dniter(term.dns, Val(L))
        for dn in dns
            addadjoint = term.forcehermitian
            foundlink = false
            ijv = builder[dn]
            addadjoint && (ijvc = builder[negative(dn)])
            for j in js
                sitej = lat.unitcell.sites[j]
                rsource = sitej - lat.bravais.matrix * dn
                itargets = targets(builder, term.range, rsource, s1)
                for i in itargets
                    isselfhopping((i, j), (s1, s2), dn) && continue
                    foundlink = true
                    rtarget = lat.unitcell.sites[i]
                    r, dr = _rdr(rsource, rtarget)
                    vs = orbsized(term(r, dr), lat.unitcell.orbitals[s1], lat.unitcell.orbitals[s2])
                    v = padtotype(vs, M)
                    if addadjoint
                        v *= redundancyfactor(dn, (s1, s2), term)
                        push!(ijv, (i, j, v))
                        push!(ijvc, (j, i, v'))
                    else
                        push!(ijv, (i, j, v))
                    end
                end
            end
            foundlink && acceptcell!(dns, dn)
        end
    end
    return nothing
end

orbsized(m, orbs) = orbsized(m, orbs, orbs)
orbsized(m, o1::NTuple{D1}, o2::NTuple{D2}) where {D1,D2} =
    SMatrix{D1,D2}(m)
orbsized(m::Number, o1::NTuple{1}, o2::NTuple{1}) = m

dniter(dns::Missing, ::Val{L}) where {L} = BoxIterator(zero(SVector{L,Int}))
dniter(dns, ::Val) = dns

function targets(builder, range::Real, rsource, s1)
    if !isassigned(builder.kdtrees, s1)
        sites = view(builder.lat.unitcell.sites, siterange(builder.lat, s1))
        (builder.kdtrees[s1] = KDTree(sites))
    end
    targets = inrange(builder.kdtrees[s1], rsource, range)
    targets .+= builder.lat.unitcell.offsets[s1]
    return targets
end

targets(builder, range::Missing, rsource, s1) = eachindex(builder.lat.sublats[s1].sites)

checkinfinite(term) = term.dns === missing && (term.range === missing || !isfinite(term.range)) &&
    throw(ErrorException("Tried to implement an infinite-range hopping on an unbounded lattice"))

isselfhopping((i, j), (s1, s2), dn) = i == j && s1 == s2 && iszero(dn)

# Avoid double-counting hoppings when adding adjoint
redundancyfactor(dn, ss, term) =
    isnotredundant(dn, term) || isnotredundant(ss, term) ? 1.0 : 0.5
# (i,j,dn) and (j,i,-dn) will not both be added if any of the following is true
isnotredundant(dn::SVector, term) = term.dns !== missing && !iszero(dn)
isnotredundant((s1, s2)::Tuple{Int,Int}, term) = term.sublats !== missing && s1 != s2

#######################################################################
# unitcell/supercell
#######################################################################

function supercell(ham::Hamiltonian, args...; kw...)
    slat = supercell(ham.lattice, args...; kw...)
    return Hamiltonian(slat, ham.harmonics, ham.field)
end

function unitcell(ham::Hamiltonian{<:Lattice}, args...; kw...)
    sham = supercell(ham, args...; kw...)
    return unitcell(sham)
end

function unitcell(ham::Hamiltonian{LA,L,Tv}) where {E,L,T,L´,Tv,LA<:Superlattice{E,L,T,L´}}
    lat = ham.lattice
    mapping = similar(lat.supercell.cellmask, Int) # store supersite indices newi
    mapping .= 0
    foreach_supersite((s, oldi, olddn, newi) -> mapping[oldi, Tuple(olddn)...] = newi, lat)
    dim = nsites(lat.supercell)
    B = blocktype(ham)
    harmonic_builders = HamiltonianHarmonic{L´,Tv,SparseMatrixBuilder{B}}[]
    pinvint = pinvmultiple(lat.supercell.matrix)
    foreach_supersite(lat) do s, source_i, source_dn, newcol
        for oldh in ham.harmonics
            rows = rowvals(oldh.h)
            vals = nonzeros(oldh.h)
            target_dn = source_dn + oldh.dn
            super_dn = new_dn(target_dn, pinvint)
            wrapped_dn = wrap_dn(target_dn, super_dn, lat.supercell.matrix)
            newh = get_or_push!(harmonic_builders, super_dn, dim)
            for p in nzrange(oldh.h, source_i)
                target_i = rows[p]
                # check: wrapped_dn could exit bounding box along non-periodic direction
                checkbounds(Bool, mapping, target_i, Tuple(wrapped_dn)...) || continue
                newrow = mapping[target_i, Tuple(wrapped_dn)...]
                val = applyfield(ham.field, vals[p], target_i, source_i, source_dn)
                iszero(newrow) || pushtocolumn!(newh.h, newrow, val)
            end
        end
        foreach(h -> finalisecolumn!(h.h), harmonic_builders)
    end
    harmonics = [HamiltonianHarmonic(h.dn, sparse(h.h)) for h in harmonic_builders]
    field = ham.field
    unitlat = unitcell(lat)
    return Hamiltonian(unitlat, harmonics, field)
end

function get_or_push!(hs::Vector{HamiltonianHarmonic{L,Tv,SparseMatrixBuilder{B}}}, dn, dim) where {L,Tv,B}
    for h in hs
        h.dn == dn && return h
    end
    newh = HamiltonianHarmonic(dn, SparseMatrixBuilder{B}(dim, dim))
    push!(hs, newh)
    return newh
end

#######################################################################
# parametric hamiltonian
#######################################################################
struct ParametricHamiltonian{H,F,E,T}
    base::H
    hamiltonian::H
    pointers::Vector{Vector{Tuple{Int,SVector{E,T},SVector{E,T}}}} # val pointers to modify
    f::F                                                           # by f on each harmonic
end

Base.eltype(::ParametricHamiltonian{H}) where {L,M,H<:Hamiltonian{L,M}} = M

Base.show(io::IO, pham::ParametricHamiltonian) = print(io, "Parametric ", pham.hamiltonian)

function parametric_hamiltonian(::Type{M}, lat::AbstractLattice{E,L,T}, f::F, model; field = missing) where {M,E,L,T,F}
    builder = IJVBuilder{M}(lat)
    applyterms!(builder, terms(model)...)
    nels = length.(builder.ijvs) # element counters for each harmonic
    model_f = f()
    applyterms!(builder, terms(model_f)...)
    padright!(nels, 0, length(builder.ijvs)) # in case new harmonics where added
    nels_f = length.(builder.ijvs) # element counters after adding f model
    empties = isempty.(builder.ijvs)
    deleteat!(builder.ijvs, empties)
    deleteat!(nels, empties)
    deleteat!(nels_f, empties)

    base_ijvs = copy.(builder.ijvs) # ijvs for ham without f, but with structural zeros
    zeroM = zero(M)
    for (ijv, nel, nel_f) in zip(base_ijvs, nels, nels_f), p in nel+1:nel_f
        ijv.v[p] = zeroM
    end

    HT = HamiltonianHarmonic{L,M,SparseMatrixCSC{M,Int}}
    n = nsites(lat)
    base_harmonics = HT[HT(e.dn, sparse(e.i, e.j, e.v, n, n)) for e in base_ijvs]
    harmonics = HT[HT(e.dn, sparse(e.i, e.j, e.v, n, n)) for e in builder.ijvs]
    pointers = [getpointers(harmonics[k].h, builder.ijvs[k], nels[k], lat) for k in eachindex(harmonics)]
    base_h = Hamiltonian(lat, base_harmonics, missing, n, n)
    h = Hamiltonian(lat, harmonics, Field(field, lat), n, n)
    return ParametricHamiltonian(base_h, h, pointers, f)
end

function getpointers(h::SparseMatrixCSC, ijv, eloffset, lat::AbstractLattice{E,L,T}) where {E,L,T}
    rows = rowvals(h)
    sites = lat.unitcell.sites
    pointers = Tuple{Int,SVector{E,T},SVector{E,T}}[] # (pointer, r, dr)
    nelements = length(ijv)
    for k in eloffset+1:nelements
        row = ijv.i[k]
        col = ijv.j[k]
        for ptr in nzrange(h, col)
            if row == rows[ptr]
                r, dr = _rdr(sites[col], sites[row]) # _rdr(source, target)
                push!(pointers, (ptr, r, dr))
                break
            end
        end
    end
    unique!(first, pointers) # adjoint duplicates lead to repeated pointers... remove.
    return pointers
end

function (ph::ParametricHamiltonian)(;kw...)
    isempty(kw) && return ph.hamiltonian
    model = ph.f(;kw...)
    initialize!(ph)
    foreach(term -> applyterm!(ph, term), terms(model))
    return ph.hamiltonian
end

(ph::ParametricHamiltonian)(arg, args...; kw...) = ph(;kw...)(arg, args...)

function initialize!(ph::ParametricHamiltonian)
    for (bh, h, prdrs) in zip(ph.base.harmonics, ph.hamiltonian.harmonics, ph.pointers)
        vals = nonzeros(h.h)
        vals_base = nonzeros(bh.h)
        for (p,_,_) in prdrs
            vals[p] = vals_base[p]
        end
    end
    return nothing
end

function applyterm!(ph::ParametricHamiltonian{H}, term::TightbindingModelTerm) where {L,M,LA,H<:Hamiltonian{LA,L,M}}
    for (h, prdrs) in zip(ph.hamiltonian.harmonics, ph.pointers)
        vals = nonzeros(h.h)
        for (p, r, dr) in prdrs
            v = term(r, dr) # should perhaps be v = orbsized(term(r, dr), orb1, orb2)
            vals[p] += padtotype(v, M)
        end
    end
    return nothing
end

#######################################################################
# Bloch routines
#######################################################################
bloch!(h::Hamiltonian, phases::Number...) where {L} = bloch!(h, toSVector(phases))
bloch!(h::Hamiltonian, phases::Tuple) where {L} = bloch!(h, toSVector(phases))
function bloch!(h::Hamiltonian{<:Lattice,L,M,<:SparseMatrixCSC}, phases::SVector{L}) where {L,M}
    h0 = first(h.harmonics).h
    matrix = h.matrix
    if length(h0.nzval) == length(matrix.nzval) # rewrite matrix from previous calls
        copy!(matrix.nzval, h0.nzval)
    else # first call, align first harmonic h0 with optimized matrix
        copy!(h0.colptr, matrix.colptr)
        copy!(h0.rowval, matrix.rowval)
        copy!(h0.nzval, matrix.nzval)
    end
    for ns in 2:length(h.harmonics)
        hh = h.harmonics[ns]
        ephi = cis(phases' * hh.dn)
        muladd_optsparse(matrix, ephi, hh.h)
    end
    return matrix
end

function muladd_optsparse(matrix, ephi, h)
    for col in 1:size(h,2)
        range = nzrange(h, col)
        for ptr in range
            row = h.rowval[ptr]
            matrix[row, col] = ephi * h.nzval[ptr]
        end
    end
    return nothing
end

function bloch!(h::Hamiltonian{<:Lattice,L,M,<:Matrix}, phases::SVector{L}) where {L,M}
    matrix = h.matrix
    fill!(matrix, zero(eltype(matrix)))
    for hh in h.harmonics
        ephi = cis(phases' * hh.dn)
        matrix .+= ephi .* hh.h
    end
    return matrix
end

bloch(h::Hamiltonian{<:Lattice}, phases...) = copy(bloch!(h, phases...))
bloch(h::Hamiltonian{<:Superlattice}, phases::Number...) = SupercellBloch(h, toSVector(phases))
bloch(h::Hamiltonian{<:Superlattice}, phases::Tuple) = SupercellBloch(h, toSVector(phases))

function blochflat!(matrix, h::Hamiltonian{<:Lattice,L,M,<:Matrix}, phases...) where {L,M<:SMatrix}
    bloch!(h, phases...)
    lat = h.lattice
    offsets = flatoffsets(lat)
    numorbs = numorbitals(lat)
    for s2 in 1:nsublats(lat), s1 in 1:nsublats(lat)
        offset1, offset2 = offsets[s1], offsets[s2]
        norb1, norb2 = numorbs[s1], numorbs[s2]
        for (m, j) in enumerate(siterange(lat, s2)), (n, i) in enumerate(siterange(lat, s1))
            ioffset, joffset = offset1 + (n-1)*norb1, offset2 + (m-1)*norb2
            el = h.matrix[i, j]
            for sj in 1:norb2, si in 1:norb1
                matrix[ioffset + si, joffset + sj] = el[si, sj]
            end
        end
    end
    return matrix
end

function blochflat!(matrix, h::Hamiltonian{<:Lattice,L,<:Number}, phases...) where {L}
    bloch!(h, phases...)
    copy!(matrix, h.matrix)
    return matrix
end

function blochflat!(h::Hamiltonian{<:Lattice,L,<:Number}, phases...) where {L}
    bloch!(h, phases...)
    return h.matrix
end

function blochflat(h::Hamiltonian{<:Lattice,L,M,<:Matrix}, phases...) where {L,M<:SMatrix}
    dim = flatdim(h.lattice)
    return blochflat!(similar(h.matrix, eltype(M), (dim, dim)), h, phases...)
end

function blochflat(h::Hamiltonian{<:Lattice,L,<:Number}, phases...) where {L}
    bloch!(h, phases...)
    return copy(h.matrix)
end

function blochflat(h::Hamiltonian{<:Lattice,L,M,<:SparseMatrixCSC}, phases...) where {L,M<:SMatrix}
    bloch!(h, phases...)
    lat = h.lattice
    offsets = flatoffsets(lat)
    numorbs = numorbitals(lat)
    dim = flatdim(h.lattice)
    builder = SparseMatrixBuilder{eltype(M)}(dim, dim)
    for s2 in 1:nsublats(lat)
        norb2 = numorbs[s2]
        for col in siterange(lat, s2), sj in 1:norb2
            for ptr in nzrange(h.matrix, col)
                row = rowvals(h.matrix)[ptr]
                val = nonzeros(h.matrix)[ptr]
                fo, s1 = flatoffset_sublat(lat, row, numorbs, offsets)
                norb1 = numorbs[s1]
                for si in 1:norb1
                    flatrow = fo + si
                    pushtocolumn!(builder, flatrow, val[si, sj])
                end
            end
            finalisecolumn!(builder)
        end
    end
    matrix = sparse(builder)
    return matrix
end

function flatoffset_sublat(lat, i, no = numorbitals(lat), fo = flatoffsets(lat), o = offsets(lat))
    s = sublat(lat, i)
    return (fo[s] + (i - o[s] - 1) * no[s]), s
end