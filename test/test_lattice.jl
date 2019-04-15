module LatticeTest

using Test
using Elsa
using Elsa: nsites, nlinks

@test Bravais() isa Bravais{0,0,Float64,0}
@test Bravais((1,2),(3,3)) isa Bravais{2,2,Int,4}
@test Bravais(@SMatrix[1. 2.; 3 3]) isa Bravais{2,2,Float64,4}

@test Sublat((3, 3)) isa Sublat{2,Int64}
@test Sublat((3, 3.)) isa Sublat{2,Float64}
@test Sublat([3, 3.]) isa Sublat{2,Float64}
@test Sublat(@SVector[3, 3]) isa Sublat{2,Int64}
@test Sublat(@SVector[3., 3]) isa Sublat{2,Float64}
@test Sublat(@SVector[3., 3], (3, 3)) isa Sublat{2,Float64}
@test Sublat([3, 4.], [3, 3]) isa Sublat{2,Float64}
@test Sublat((3, 4.), [3, 3]) isa Sublat{2,Float64}
@test Sublat(@SVector[3f0, 3f0]) isa Sublat{2,Float32}

# @test Sublat(Elsa.cartesian([3,4.], [3,3], 1:3)) isa Sublat{Float64,3}

@test Sublat(@SVector[3f0, 3f0], (3, 4), name = :A) isa Sublat{2,Float32}
@test Sublat((3f0, 3.0), name = :A) isa Sublat{2,Float64}

end # module
