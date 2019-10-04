#######################################################################
# TightbindingModelTerm
#######################################################################
abstract type AbstractTightbindingModel end
abstract type TightbindingModelTerm <: AbstractTightbindingModel end

struct OnsiteTerm{F,
                  S<:Union{Missing,Tuple{Vararg{NameType}}},
                  C} <: TightbindingModelTerm
    o::F
    sublats::S
    coefficient::C
    forcehermitian::Bool
end

struct HoppingTerm{F,
                   S<:Union{Missing,Tuple{Vararg{Tuple{NameType,NameType}}}},
                   D<:Union{Missing,Tuple{Vararg{SVector{L,Int}}} where L},
                   R<:Union{Missing,Real},
                   C} <: TightbindingModelTerm
    h::F
    sublats::S
    dns::D
    range::R
    coefficient::C
    forcehermitian::Bool
end

(o::OnsiteTerm{<:Function})(r,dr) = o.o(r)
(o::OnsiteTerm)(r,dr) = o.o

(h::HoppingTerm{<:Function})(r, dr) = h.h(r, dr)
(h::HoppingTerm)(r, dr) = h.h

sanitize_sublats(s::Missing) = missing
sanitize_sublats(s::Integer) = (nametype(s),)
sanitize_sublats(s::NameType) = (s,)
sanitize_sublats(s::Tuple) where {N} = nametype.(s)
sanitize_sublats(n) = throw(ErrorException(
    "`sublats` for `onsite` must be either `missing`, an `s` or a tuple of `s`s, with `s::$NameType` is a sublattice name"))

sanitize_sublatpairs(s::Missing) = missing
sanitize_sublatpairs((s1, s2)::Tuple{2,Union{Integer,NameType}}) = ((nametype(s1), nametype(s2)),)
sanitize_sublatpairs((s2, s1)::Pair) = (sanitize_sublatpairs(s1, s2),)
sanitize_sublatpairs(s::Union{Integer,NameType}) = (sanitize_sublatpairs(s,s),)
sanitize_sublatpairs(s::NTuple{N,Any}) where {N} =
    ntuple(n -> first(sanitize_sublatpairs(s[n])), Val(N))
sanitize_sublatpairs(s) = throw(ErrorException(
    "`sublats` for `hopping` must be either `missing`, a tuple `(s₁, s₂)`, or a tuple of such tuples, with `sᵢ::$NameType` a sublattice name"))

sanitize_dn(dn::Missing) = missing
sanitize_dn(dn::Tuple{Vararg{Tuple}}) = SVector.(dn)
sanitize_dn(dn::Tuple{Vararg{Integer}}) = (SVector(dn),)

sublats(t::OnsiteTerm{<:Any,Missing}, lat::AbstractLattice) = collect(1:nsublats(lat))
function sublats(t::OnsiteTerm{<:Any,<:Tuple}, lat::AbstractLattice)
    names = lat.unitcell.names
    s = Int[]
    for name in t.terms
        i = findfirst(isequal(name), names)
        i !== nothing && push!(s, i)
    end
    return s
end

sublats(t::HoppingTerm{<:Any,Missing}, lat::AbstractLattice) =
    collect(Iterators.product(1:nsublats(lat), 1:nsublats(lat)))
function sublats(t::HoppingTerm{<:Any,<:Tuple}, lat::AbstractLattice)
    names = lat.unitcell.names
    s = Tuple{Int,Int}[]
    for (n1, n2) in t.terms
        i1 = findfirst(isequal(n1), names)
        i2 = findfirst(isequal(n2), names)
        i1 !== nothing && i2 !== nothing && push!(s, (i1, i2))
    end
    return s
end

displayparameter(::Type{<:Function}) = "Function"
displayparameter(::Type{T}) where {T} = "$T"

function Base.show(io::IO, o::OnsiteTerm{F}) where {F}
    i = get(io, :indent, "")
    print(io,
"$(i)OnsiteTerm{$(displayparameter(F))}:
$(i)  Sublattices      : $(o.sublats === missing ? "any" : o.sublats)
$(i)  Force Hermitian  : $(o.forcehermitian)
$(i)  Coefficient      : $(o.coefficient)")
end

function Base.show(io::IO, h::HoppingTerm{F}) where {F}
    i = get(io, :indent, "")
    print(io,
"$(i)HoppingTerm{$(displayparameter(F))}:
$(i)  Sublattice pairs : $(h.sublats === missing ? "any" : (t -> Pair(reverse(t)...)).(h.sublats))
$(i)  dn cell jumps    : $(h.dns === missing ? "any" : h.dns)
$(i)  Hopping range    : $(round(h.range, digits = 6))
$(i)  Force Hermitian  : $(h.forcehermitian)
$(i)  Coefficient      : $(h.coefficient)")
end

# External API #
"""
    onsite(o; sublats = missing, forcehermitian = true)

Create an `TightbindingModelTerm` that applies an onsite energy `o` to a `Lattice` when
creating a `Hamiltonian` with `hamiltonian`.

The onsite energy `o` can be a number, a matrix (preferably `SMatrix`) or a function of the
form `r -> ...` for a position-dependent onsite energy. If `sublats` is specified as a
sublattice name or tuple thereof, `onsite` is only applied to sublattices with said names.
If `forcehermitian` is true, the model will produce an Hermitian Hamiltonian.

`TightbindingModelTerm`s created with `onsite` or `hopping` can be added or substracted
together to build more complicated `TightbindingModel`s.

# Examples
```
julia> onsite(1, sublats = (1,2)) - hopping(2)
TightbindingModel{2}: model with 2 terms
  OnsiteTerm{Int64}:
    Sublattices      : (1, 2)
    Force Hermitian  : true
    Coefficient      : 1
  HoppingTerm{Int64}:
    Sublattice pairs : any
    dn cell jumps    : any
    Hopping range    : 1.0
    Force Hermitian  : true
    Coefficient      : -1

julia> hamiltonian(LatticePresets.honeycomb(orbitals = (:a, :b)), onsite(r->@SMatrix[1 2; 3 4]))
Hamiltonian{<:Lattice} : 2D Hamiltonian on a 2D Lattice in 2D space
  Bloch harmonics  : 1 (SparseMatrixCSC, sparse)
  Harmonic size    : 2 × 2
  Elements         : 2 × 2 blocks
  Onsites          : 2
  Hoppings         : 0
  Coordination     : 0.0
```

# See also:
    `hopping`
"""
function onsite(o; sublats = missing, forcehermitian::Bool = true)
    return OnsiteTerm(o, sanitize_sublats(sublats), 1, forcehermitian)
end

"""
    hopping(h; sublats = missing, range = 1, dn = missing, forcehermitian = true)

Create an `TightbindingModelTerm` that applies a hopping `h` to a `Lattice` when
creating a `Hamiltonian` with `hamiltonian`.

The maximum distance between coupled sites is given by `range::Real`. If a cell distance
`dn::NTuple{L,Int}` or distances `dn::NTuple{M,NTuple{L,Int}}` are given, only unit cells
at that distance will be coupled.

The hopping amplitude `h` can be a number, a matrix (preferably `SMatrix`) or a function
of the form `(r, dr) -> ...` for a position-dependent hopping (`r` is the bond center,
and `dr` the bond vector). If `sublats` is specified as a sublattice name pair, or tuple
thereof, `hopping` is only applied between sublattices with said names. If `forcehermitian`
is true, the model will produce an Hermitian Hamiltonian.

`TightbindingModelTerm`s created with `onsite` or `hopping` can be added or substracted
together to build more complicated `TightbindingModel`s.

# Examples
```
julia> onsite(1) - hopping(2, dn = ((1,2), (0,0)), sublats = (1,1))
TightbindingModel{2}: model with 2 terms
  OnsiteTerm{Int64}:
    Sublattices      : any
    Force Hermitian  : true
    Coefficient      : 1
  HoppingTerm{Int64}:
    Sublattice pairs : (1 => 1,)
    dn cell jumps    : ([1, 2], [0, 0])
    Hopping range    : 1.0
    Force Hermitian  : true
    Coefficient      : -1

julia> hamiltonian(LatticePresets.honeycomb(), hopping((r,dr) -> cos(r[1]), sublats = ((1,1), (2,2))))
Hamiltonian{<:Lattice} : 2D Hamiltonian on a 2D Lattice in 2D space
  Bloch harmonics  : 7 (SparseMatrixCSC, sparse)
  Harmonic size    : 2 × 2
  Elements         : scalars
  Onsites          : 0
  Hoppings         : 12
  Coordination     : 6.0
```

# See also:
    `onsite`
"""
function hopping(h; sublats = missing, range::Real = 1, dn = missing, forcehermitian::Bool = true)
    return HoppingTerm(h, sanitize_sublatpairs(sublats), sanitize_dn(dn),
                       range + sqrt(eps(Float64)), 1, forcehermitian)
end

Base.:*(x, o::OnsiteTerm) =
    OnsiteTerm(o.o, o.sublats, x * o.coefficient, o.forcehermitian)
Base.:*(x, t::HoppingTerm) =
    HoppingTerm(t.h, t.sublats, t.dns, t.range, x * t.coefficient, t.forcehermitian)
Base.:*(t::TightbindingModelTerm, x) = x * t
Base.:-(t::TightbindingModelTerm) = (-1) * t

Base.:+(t1::TightbindingModelTerm, t2::TightbindingModelTerm) = TightbindingModel((t1, t2))
Base.:-(t1::TightbindingModelTerm, t2::TightbindingModelTerm) = TightbindingModel((t1, -t2))


#######################################################################
# TightbindingModel
#######################################################################
struct TightbindingModel{N,T<:Tuple{Vararg{TightbindingModelTerm,N}}} <: AbstractTightbindingModel
    terms::T
end

terms(t::TightbindingModel) = t.terms
terms(t::TightbindingModelTerm) = (t,)

TightbindingModel(m::TightbindingModel) = m
TightbindingModel(t::AbstractTightbindingModel...) = TightbindingModel(tuplejoin(terms.(t)...))

# External API #

Base.:*(x, m::TightbindingModel) = TightbindingModel(x .* m.terms)
Base.:*(m::TightbindingModel, x) = x * m
Base.:-(m::TightbindingModel) = TightbindingModel((-1) .* m.terms)

Base.:+(m::TightbindingModel, t::TightbindingModelTerm) = TightbindingModel((m.terms..., t))
Base.:+(t::TightbindingModelTerm, m::TightbindingModel) = TightbindingModel((t, m.terms...))
Base.:-(m::TightbindingModel, t::TightbindingModelTerm) = m + (-t)
Base.:-(t::TightbindingModelTerm, m::TightbindingModel) = t + (-m)

function Base.show(io::IO, m::TightbindingModel{N}) where {N}
    ioindent = IOContext(io, :indent => "  ")
    print(io, "TightbindingModel{$N}: model with $N terms", "\n")
    foreach(t -> print(ioindent, t, "\n"), m.terms)
end