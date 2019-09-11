#######################################################################
# Hamiltonian
#######################################################################
struct HamiltonianHarmonic{L,Tv,A<:AbstractMatrix{<:SMatrix{N,N,Tv} where N}}
    dn::SVector{L,Int}
    h::A
end

struct Hamiltonian{L,Tv,H<:HamiltonianHarmonic{L,Tv},D<:Domain{L}}
    harmonics::Vector{H}
    domain::D
end

struct HamiltonianBuilder{L,Tv,H<:Hamiltonian{L,Tv},F<:Function,P<:NamedTuple}
    h::H
    field::F
    parameters::P
end

blocktype(::Type{Tv}, lat::Lattice) where {Tv} =
    blocktype(SMatrix{1,1,Tv,1}, lat.sublats...)
blocktype(::Type{S}, s::Sublat{E,T,D}, ss...) where {N,Tv,E,T,D,S<:SMatrix{N,N,Tv}} =
    (M = max(N,D); blocktype(SMatrix{M,M,Tv,M^2}, ss...))
blocktype(t) = t

Base.size(h::Hamiltonian) = (n = size(h.domain.bitmask)[end]; (n, n))

Base.show(io::IO, h::HamiltonianHarmonic{L,Tv,A}) where {L,Tv,N,A<:AbstractArray{<:SMatrix{N,N,Tv}}} =
    print(io, "HamiltonianHarmonic{$L,$Tv} with dn = $(Tuple(h.dn)) and elements:", h.h)

Base.show(io::IO, ham::Hamiltonian{L,Tv,H}) where {L,Tv,N,
    H<:HamiltonianHarmonic{L,Tv,<:AbstractArray{<:SMatrix{N,N,Tv}}}} = print(io,
"Hamiltonian{$L,$Tv} : $(L)D Hamiltonian of element type SMatrix{$N,$N,$Tv}
  Bloch harmonics  : $(length(ham.harmonics))
  Harmonic size    : $(size(ham))")
#   Bravais vectors     : $(displayvectors(sys.lattice.bravais))
#   Sublattice names    : $((sublatnames(sys.lattice)... ,))
#   Sublattice orbitals : $((norbitals(sys)... ,))
#   Total sites         : $(nsites(sys)) [$T]
#   Total hoppings      : $(nlinks(sys)) [$Tv]
#   Coordination        : $(coordination(sys))")

# API #

hamiltonian(lat::Lattice, t::TightbindingModelTerm...; kw...) =
    hamiltonian(lat, TightbindingModel(t))
hamiltonian(lat::Lattice{E,L,T}, m::TightbindingModel; htype::Type = Complex{T}) where {E,L,T} =
    sparse_hamiltonian(blocktype(htype, lat), lat, m.terms...)

#######################################################################
# auxiliary types
#######################################################################
struct IJV{L,M}
    dn::SVector{L,Int}
    i::Vector{Int}
    j::Vector{Int}
    v::Vector{M}
end

struct IJVBuilder{L,M,E,T,LA<:Lattice{E,L,T}}
    lat::LA
    ijvs::Vector{IJV{L,M}}
    kdtrees::Vector{KDTree{SVector{E,T},Euclidean,T}}
end

IJV{L,M}(dn::SVector{L} = zero(SVector{L,Int})) where {L,M} =
    IJV(dn, Int[], Int[], M[])

function IJVBuilder{M}(lat::Lattice{E,L,T}) where {E,L,T,M}
    ijvs = IJV{L,M}[]
    kdtrees = Vector{KDTree{SVector{E,T},Euclidean,T}}(undef, nsublats(lat))
    return IJVBuilder(lat, ijvs, kdtrees)
end

function Base.getindex(b::IJVBuilder{L,M}, dn::SVector{L,Int}) where {L,M}
    for e in b.ijvs
        e.dn == dn && return e
    end
    e = IJV{L,M}(dn)
    push!(b.ijvs, e)
    return e
end

Base.length(h::IJV) = length(h.i)
Base.isempty(h::IJV) = length(h) == 0

function Base.resize!(h::IJV, n)
    resize!(h.i, n)
    resize!(h.j, n)
    resize!(h.v, n)
    return h
end

Base.push!(h::IJV, (i, j, v)) = (push!(h.i, i); push!(h.j, j); push!(h.v, v))

#######################################################################
# sparse_hamiltonian
#######################################################################
function sparse_hamiltonian(::Type{M}, lat::Lattice{E,L}, terms...) where {E,L,Tv,M<:SMatrix{D,D,Tv} where D}
    builder = IJVBuilder{M}(lat)
    applyterms!(builder, terms...)
    HT = HamiltonianHarmonic{L,Tv,SparseMatrixCSC{M,Int}}
    n = nsites(lat)
    harmonics = HT[HT(e.dn, sparse(e.i, e.j, e.v, n, n, (x, xc) -> 0.5 * (x + xc)))
                  for e in builder.ijvs if !isempty(e)]
    return Hamiltonian(harmonics, lat.domain)
end

applyterms!(builder, terms...) = foreach(term -> applyterm!(builder, term), terms)

function applyterm!(builder::IJVBuilder{L,M}, term::OnsiteTerm) where {L,M}
    for s in sublats(term, builder.lat)
        dn0 = zero(SVector{L,Int})
        ijv = builder[dn0]
        offset = builder.lat.offsets[s]
        for (n, r) in enumerate(builder.lat.sublats[s].sites)
            i = offset + n
            v = pad(term(r), M) # already Hermitian (if necessary) by term(r) definition
            push!(ijv, (i, i, v))
        end
    end
    return nothing
end

function applyterm!(builder::IJVBuilder{L,M}, term::HoppingTerm) where {L,M}
    checkinfinite(term)
    for (s1, s2) in sublats(term, builder.lat)
        offset1, offset2 = builder.lat.offsets[s1], builder.lat.offsets[s2]
        dns = dniter(term.dns, Val(L))
        for dn in dns
            addadjoint = term.forcehermitian
            foundlink = false
            ijv = builder[dn]
            addadjoint && (ijvc = builder[negative(dn)])
            for (j, site) in enumerate(builder.lat.sublats[s2].sites)
                rsource = site - builder.lat.bravais.matrix * dn
                itargets = targets(builder, term.range, rsource, s1)
                for i in itargets
                    isselfhopping((i, j), (s1, s2), dn) && continue
                    foundlink = true
                    rtarget = builder.lat.sublats[s1].sites[i]
                    r, dr = _rdr(rsource, rtarget)
                    v = pad(term(r, dr), M)
                    push!(ijv, (offset1 + i, offset2 + j, v))
                    addadjoint && push!(ijvc, (offset2 + j, offset1 + i, v'))
                end
            end
            foundlink && acceptcell!(dns, dn)
        end
    end
    return nothing
end

# If dns are specified in model term (not missing), iterate over them. Otherwise do a search.
dniter(dns::Missing, ::Val{L}) where {L} = BoxIterator(zero(SVector{L,Int}))
dniter(dns, ::Val) = dns

function targets(builder, range::Real, rsource, s1)
    isassigned(builder.kdtrees, s1) || (builder.kdtrees[s1] = KDTree(builder.lat.sublats[s1].sites))
    return inrange(builder.kdtrees[s1], rsource, range)
end

targets(builder, range::Missing, rsource, s1) = eachindex(builder.lat.sublats[s1].sites)

checkinfinite(term) = term.dns === missing && (term.range === missing || !isfinite(term.range)) &&
    throw(ErrorException("Tried to implement an infinite-range hopping on an unbounded lattice"))

isselfhopping((i, j), (s1, s2), dn) = i == j && s1 == s2 && iszero(dn)