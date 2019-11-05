toSMatrix() = SMatrix{0,0,Float64}()
toSMatrix(ss::NTuple{N,Number}...) where {N} = toSMatrix(SVector{N}.(ss)...)
toSMatrix(ss::SVector{N}...) where {N} = hcat(ss...)
toSMatrix(::Type{T}, ss...) where {T} = _toSMatrix(T, toSMatrix(ss...))
_toSMatrix(::Type{T}, s::SMatrix{N,M}) where {N,M,T} = convert(SMatrix{N,M,T}, s)
# Dynamic dispatch
toSMatrix(ss::AbstractVector...) = toSMatrix(Tuple.(ss)...)
toSMatrix(s::AbstractMatrix) = SMatrix{size(s,1), size(s,2)}(s)

toSVector(::Tuple{}) = SVector{0,Float64}()
toSVectors(vs...) = [promote(toSVector.(vs)...)...]
toSVector(v::SVector) = v
toSVector(v::NTuple{N,Number}) where {N} = SVector(v)
toSVector(x::Number) = SVector{1}(x)
toSVector(::Type{T}, v) where {T} = T.(toSVector(v))
toSVector(::Type{T}, ::Tuple{}) where {T} = SVector{0,T}()
# Dynamic dispatch
toSVector(v::AbstractVector) = SVector(Tuple(v))

# ensureSMatrix(f::Function) = f
# ensureSMatrix(m::T) where T<:Number = SMatrix{1,1,T,1}(m)
# ensureSMatrix(m::SMatrix) = m
# ensureSMatrix(m::Array) =
#     throw(ErrorException("Write all model terms using scalars or @SMatrix[matrix]"))

_rdr(r1, r2) = (0.5 * (r1 + r2), r2 - r1)

# zerotuple(::Type{T}, ::Val{L}) where {T,L} = ntuple(_ -> zero(T), Val(L))

filltuple(x, ::Val{L}) where {L} = ntuple(_ -> x, Val(L))

function padright!(v::Vector, x, n::Integer)
    n0 = length(v)
    resize!(v, max(n, n0))
    for i in (n0 + 1):n
        v[i] = x
    end
    return v
end

padright(sv::StaticVector{E,T}, x::T, ::Val{E}) where {E,T} = sv
padright(sv::StaticVector{E1,T1}, x::T2, ::Val{E2}) where {E1,T1,E2,T2} =
    (T = promote_type(T1,T2); SVector{E2, T}(ntuple(i -> i > E1 ? x : convert(T, sv[i]), Val(E2))))
padright(sv::StaticVector{E,T}, ::Val{E2}) where {E,T,E2} = padright(sv, zero(T), Val(E2))
padright(sv::StaticVector{E,T}, ::Val{E}) where {E,T} = sv
padright(t::Tuple, x...) = Tuple(padright(SVector(t), x...))

@inline padtotype(s::SMatrix{E,L}, st::Type{S}) where {E,L,E2,L2,S<:SMatrix{E2,L2}} =
    S(SMatrix{E2,E}(I) * s * SMatrix{L,L2}(I))
@inline padtotype(s::UniformScaling, st::Type{S}) where {S<:SMatrix} = S(s)
@inline padtotype(s::Number, ::Type{S}) where {S<:SMatrix} = S(s*I)
@inline padtotype(s::Number, ::Type{T}) where {T<:Number} = T(s)
@inline padtotype(s::AbstractArray, ::Type{T}) where {T<:Number} = T(first(s))
@inline padtotype(s::UniformScaling, ::Type{T}) where {T<:Number} = T(s.λ)

## Work around BUG: -SVector{0,Int}() isa SVector{0,Union{}}
negative(s::SVector{L,<:Number}) where {L} = -s
negative(s::SVector{0,<:Number}) where {L} = s

empty_sparse(::Type{M}, n, m) where {M} = sparse(Int[], Int[], M[], n, m)

display_as_tuple(v, prefix = "") = isempty(v) ? "()" :
    string("(", prefix, join(v, string(", ", prefix)), ")")

displayvectors(mat::SMatrix{E,L,<:AbstractFloat}; kw...) where {E,L} =
    ntuple(l -> round.(Tuple(mat[:,l]); kw...), Val(L))
displayvectors(mat::SMatrix{E,L,<:Integer}; kw...) where {E,L} =
    ntuple(l -> Tuple(mat[:,l]), Val(L))

# pseudoinverse of s times an integer n, so that it is an integer matrix (for accuracy)
pinvmultiple(s::SMatrix{L,0}) where {L} = (SMatrix{0,0,Int}(), 0)
function pinvmultiple(s::SMatrix{L,L´}) where {L,L´}
    L < L´ && throw(DimensionMismatch("Supercell dimensions $(L´) cannot exceed lattice dimensions $L"))
    qrfact = qr(s)
    n = det(qrfact.R)
    # Cannot check det(s) ≈ 0 because s can be non-square
    abs(n) ≈ 0 && throw(ErrorException("Supercell appears to be singular"))
    pinverse = inv(qrfact.R) * qrfact.Q'
    return round.(Int, n * inv(qrfact.R) * qrfact.Q'), round(Int, n)
end

@inline tuplejoin() = ()
@inline tuplejoin(x) = x
@inline tuplejoin(x, y) = (x..., y...)
@inline tuplejoin(x, y, z...) = (x..., tuplejoin(y, z...)...)

function isgrowing(vs::AbstractVector, i0 = 1)
    i0 > length(vs) && return true
    vprev = vs[i0]
    for i in i0 + 1:length(vs)
        v = vs[i]
        v <= vprev && return false
        vprev = v
    end
    return true
end

function ispositive(ndist)
    result = false
    for i in ndist
        i == 0 || (result = i > 0; break)
    end
    return result
end

isnonnegative(ndist) = iszero(ndist) || ispositive(ndist)

_copy!(dest, src) = copy!(dest, src)
function _copy!(dst::Matrix{T}, src::SparseMatrixCSC) where {T}
    axes(dst) == axes(src) || throw(ArgumentError(
        "arrays must have the same axes for copy!"))
    fill!(dst, zero(T))
    for col in 1:size(src,1)
        for p in nzrange(src, col)
            dst[rowvals(src)[p], col] = nonzeros(src)[p]
        end
    end
    return dst
end

approxruns(list::AbstractVector{T}, degtol = sqrt(eps(real(T)))) where {T} = approxruns!(UnitRange{Int}[], list)
function approxruns!(runs::AbstractVector{<:UnitRange}, list::AbstractVector{T}, degtol = sqrt(eps(real(T)))) where {T}
    resize!(runs, 0)
    len = length(list)
    len < 2 && return runs
    rmin = rmax = 1
    prev = list[1]
    @inbounds for i in 2:len
        next = list[i]
        if abs(next - prev) < degtol
            rmax = i
        else
            rmin < rmax && push!(runs, rmin:rmax)
            rmin = rmax = i
        end
        prev = next
    end
    rmin < rmax && push!(runs, rmin:rmax)
    return runs
end

# pinverse(s::SMatrix) = (qrfact = qr(s); return inv(qrfact.R) * qrfact.Q')

# padrightbottom(m::Matrix{T}, im, jm) where {T} = padrightbottom(m, zero(T), im, jm)

# function padrightbottom(m::Matrix{T}, zeroT::T, im, jm) where T
#     i0, j0 = size(m)
#     [i <= i0 && j<= j0 ? m[i,j] : zeroT for i in 1:im, j in 1:jm]
# end


# tuplesort((a,b)::Tuple{<:Number,<:Number}) = a > b ? (b, a) : (a, b)
# tuplesort(t::Tuple) = t
# tuplesort(::Missing) = missing

# collectfirst(s::T, ss...) where {T} = _collectfirst((s,), ss...)
# _collectfirst(ts::NTuple{N,T}, s::T, ss...) where {N,T} = _collectfirst((ts..., s), ss...)
# _collectfirst(ts::Tuple, ss...) = (ts, ss)
# _collectfirst(ts::NTuple{N,System}, s::System, ss...) where {N} = _collectfirst((ts..., s), ss...)
# collectfirsttolast(ss...) = tuplejoin(reverse(collectfirst(ss...))...)



# allorderedpairs(v) = [(i, j) for i in v, j in v if i >= j]

# Like copyto! but with potentially different tensor orders (adapted from Base.copyto!)
function copyslice!(dest::AbstractArray{T1,N1}, Rdest::CartesianIndices{N1},
                    src::AbstractArray{T2,N2}, Rsrc::CartesianIndices{N2}) where {T1,T2,N1,N2}
    isempty(Rdest) && return dest
    if length(Rdest) != length(Rsrc)
        throw(ArgumentError("source and destination must have same length (got $(length(Rsrc)) and $(length(Rdest)))"))
    end
    checkbounds(dest, first(Rdest))
    checkbounds(dest, last(Rdest))
    checkbounds(src, first(Rsrc))
    checkbounds(src, last(Rsrc))
    src′ = Base.unalias(dest, src)
    @inbounds for (Is, Id) in zip(Rsrc, Rdest)
        @inbounds dest[Id] = src′[Is]
    end
    return dest
end

######################################################################
# Permutations (taken from Combinatorics.jl)
#######################################################################

struct Permutations{T}
    a::T
    t::Int
end

Base.eltype(::Type{Permutations{T}}) where {T} = Vector{eltype(T)}

Base.length(p::Permutations) = (0 <= p.t <= length(p.a)) ? factorial(length(p.a), length(p.a)-p.t) : 0

"""
    permutations(a)
Generate all permutations of an indexable object `a` in lexicographic order. Because the number of permutations
can be very large, this function returns an iterator object.
Use `collect(permutations(a))` to get an array of all permutations.
"""
permutations(a) = Permutations(a, length(a))

"""
    permutations(a, t)
Generate all size `t` permutations of an indexable object `a`.
"""
function permutations(a, t::Integer)
    if t < 0
        t = length(a) + 1
    end
    Permutations(a, t)
end

function Base.iterate(p::Permutations, s = collect(1:length(p.a)))
    (!isempty(s) && max(s[1], p.t) > length(p.a) || (isempty(s) && p.t > 0)) && return
    nextpermutation(p.a, p.t ,s)
end

function nextpermutation(m, t, state)
    perm = [m[state[i]] for i in 1:t]
    n = length(state)
    if t <= 0
        return(perm, [n+1])
    end
    s = copy(state)
    if t < n
        j = t + 1
        while j <= n &&  s[t] >= s[j]; j+=1; end
    end
    if t < n && j <= n
        s[t], s[j] = s[j], s[t]
    else
        if t < n
            reverse!(s, t+1)
        end
        i = t - 1
        while i>=1 && s[i] >= s[i+1]; i -= 1; end
        if i > 0
            j = n
            while j>i && s[i] >= s[j]; j -= 1; end
            s[i], s[j] = s[j], s[i]
            reverse!(s, i+1)
        else
            s[1] = n+1
        end
    end
    return (perm, s)
end

# Taken from Combinatorics.jl
# TODO: This should really live in Base, otherwise it's type piracy
"""
    factorial(n, k)

Compute ``n!/k!``.
"""
function Base.factorial(n::T, k::T) where T<:Integer
    if k < 0 || n < 0 || k > n
        throw(DomainError((n, k), "n and k must be nonnegative with k ≤ n"))
    end
    f = one(T)
    while n > k
        f = Base.checked_mul(f, n)
        n -= 1
    end
    return f
end

Base.factorial(n::Integer, k::Integer) = factorial(promote(n, k)...)
