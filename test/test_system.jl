module SystemTest

using Test
using Elsa, SparseArrays, LinearAlgebra
using Elsa: nlinks, nsites

@testset "operators" begin
    @test begin
        sys = System(LatticePresets.square(), Model(Hopping(@SMatrix[1 2; 2 1]))) |> grow(supercell = 3)
        h = sys.hamiltonian
        v = Elsa.boundaryoperator(h)
        nnz(h.matrix) == 144 && nnz(v.matrix) == 48 && v.inters == h.inters
    end
end

@testset "system" begin
    @test System(LatticePresets.honeycomb(), dim = Val(3), htype = Float64, ptype = Float32) isa System{3,2,Float32,Float64}
    @test nsites(System(LatticePresets.honeycomb()) |> grow(region = RegionPresets.square(300))) == 207946
    @test nsites(System(LatticePresets.square()) |> grow(supercell = 31)) == 961
    @test nsites(System(LatticePresets.bcc()) |> grow(region = RegionPresets.spheroid((10,4,4)))) == 1365

    @test nlinks(System(LatticePresets.honeycomb(), Model(Hopping(1, sublats = (1,2)))) |> grow(region = RegionPresets.square(30))) == 6094
    @test nlinks(System(LatticePresets.honeycomb(), Model(Hopping(1, ndists = (0,1)))) |> grow(region = RegionPresets.square(30))) == 3960
    @test nlinks(System(LatticePresets.honeycomb(), Model(Hopping(1, ndists = ((0,1),)))) |> grow(region = RegionPresets.square(30))) == 3960
    @test nlinks(System(LatticePresets.honeycomb(), Model(Hopping(1, sublats = (1,2), ndists = ((0,1), (0,1))))) |> 
        grow(region = Region(:square, 30))) == 2040
    @test nlinks(System(LatticePresets.square(), Model(Hopping(1, range = 2))) |> grow(supercell = 31)) == 11532
    @test nlinks(System(LatticePresets.bcc(), Model(Hopping(1, range = 1))) |> 
        grow(supercell = ((1, 2, 0),), region = RegionPresets.sphere(10))) == 10868
    @test nlinks(System(LatticePresets.bcc(), Model(Hopping(1, range = 1))) |> 
        grow(supercell = (10, 20, 30), region = RegionPresets.sphere(4))) == 326
    @test nlinks(System(LatticePresets.bcc(), Model(Hopping(1, range = 1))) |> grow(supercell = (10, 20, 30))) == 84000

    @test nsites(SystemPresets.graphene_bilayer(twistindex = 31)) == 11908
end

@testset "system api" begin
    @test begin
        sys1 = System(LatticePresets.honeycomb(), Model(Hopping(1, sublats = (1,2))), dim = Val(3)) |> grow(region = RegionPresets.square(4)) |> 
            transform(r -> r + SVector(0,0,1)) 
        sys2 = System(LatticePresets.square(), Model(Hopping(1, range = 2)), dim = Val(3)) |> grow(region = RegionPresets.square(4)) 
        sys3 = combine(sys1, sys2)
        (nlinks(sys3) == nlinks(sys1) + nlinks(sys2) == 294) &&
        (nsites(sys3) == nsites(sys1) + nsites(sys2) == 61)
    end

    @test begin
        sys1 = System(LatticePresets.honeycomb(), Model(Hopping(1, sublats = (1,2)))) |> grow(region = RegionPresets.circle(7))
        sys2 = System(LatticePresets.square(), Model(Hopping(1, range = 2))) |> grow(region = RegionPresets.circle(6))
        sys3 = combine(sys1, sys2, Model(Hopping(1, range = 1)))
        nlinks(sys3) == 5494
    end

    @test begin
        sys1 = System(LatticePresets.honeycomb())
        sys2 = transform(sys1, r -> 2r)
        sys2.lattice.sublats[1].sites[1] ≈ 2 * sys1.lattice.sublats[1].sites[1]
    end

    @test begin
        sys1 = System(LatticePresets.honeycomb())
        sys2 = System(LatticePresets.honeycomb())
        sys3 = System(LatticePresets.honeycomb())
        sys4 = combine(sys1, combine(sys2, sys3))
        allunique(sys4.sysinfo.names)
    end

    @test begin
        sys1 = System(LatticePresets.honeycomb(), Model(Onsite(@SMatrix[1 0; 0 2], sublats = :A), 
                                        Onsite(@SMatrix[2 0; 0 3], sublats = :B)))
        sys2 = grow(sys1, region = RegionPresets.circle(1))
        sum(sys2.hamiltonian.matrix) == tr(sys2.hamiltonian.matrix) == 24
    end

    @test begin
        sys = System(LatticePresets.bcc(), Model(Hopping(1))) |> grow(supercell = 3) |> bound(except = 1)
        sys isa System{3,1}
    end

    @test begin
        sys = System(LatticePresets.cubic(), Model(Hopping(1, range = 3))) |> grow(supercell = (3,1,3)) |> 
              bound(except = (1,3))
        sys isa System{3,2} && Elsa.nlinks(sys) == 252
    end

    @test begin
        sys = System(LatticePresets.honeycomb()) |> bound()
        sys isa System{2,0}
    end
end

# @test Elsa.nlinks(wrap(Lattice(:square, LinkRule(√2), Supercell(2)), exceptaxes = (1,))) == 14
# @test Elsa.nlinks(wrap(Lattice(:square, LinkRule(√2), Supercell(2)), exceptaxes = (2,))) == 14
# @test Elsa.nlinks(wrap(Lattice(:square, LinkRule(√2), Supercell(2)))) == 6

# @test begin
#     lat = mergesublats(Lattice(Preset(LatticePresets.honeycomb()_bilayer, twistindex = 2)), (2,1,1,1))
#     Elsa.nlinks(lat) == 32 && Elsa.nsublats(lat) == 2
# end

# @test begin
#     sys = System(Lattice(:square, LinkRule(2), Supercell(3)), Model(Onsite(1), Hopping(.3)))
#     nnz(sys.hbloch.matrix) == 81 && size(sys.vbloch.matrix) == (9, 9)
# end

# @test begin
#     sys = System(Lattice(LatticePresets.honeycomb(), LinkRule(1), Supercell(3)), Model(Onsite(1), Hopping(.3, (1,2))))
#     vel = velocity!(sys, k = (.2,.3))
#     ishermitian(vel) && size(vel) == (18, 18)
# end

# @test begin
#     sys = System(Lattice(LatticePresets.honeycomb(), LinkRule(1), Region(:square, 5)), Model(Onsite(1), Hopping(.3, (1,2))))
#     iszero(velocity!(sys))
# end

end # module
