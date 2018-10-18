module ModelTest

using Test
using QBox

@test Onsite(1) isa QBox.OnsiteConst{Missing,1,Int,1}
@test Onsite(1, 1) isa QBox.OnsiteConst{Tuple{Int64},1,Int64,1}
@test Onsite([1 2; 3 4], 1) isa QBox.OnsiteConst{Tuple{Int64},2,Int64,4}
@test Onsite([1 2; 3 4.0], 1) isa QBox.OnsiteConst{Tuple{Int64},2,Float64,4}
@test Onsite(@SMatrix[1 2; 3 4.0], 1) isa QBox.OnsiteConst{Tuple{Int64},2,Float64,4}

@test Hopping(@SMatrix[1 2.0; 3 4], (1,1)) isa QBox.HoppingConst{Tuple{Tuple{Int,Int}},2,2,Float64,4}
@test Hopping(@SMatrix[1 2.0; 3 4]) isa QBox.HoppingConst{Missing,2,2,Float64,4}

@test_throws ErrorException Model(Onsite([1 2], 3)) # Non-square onsite matrix!
@test_throws MethodError Model(Onsite(@SMatrix[1 2])) # Non-square onsite matrix!
@test_throws DimensionMismatch Model(Hopping(@SMatrix[1 2], (1,1)))  # Non-square intra-sublattice hopping matrix!
@test_throws DimensionMismatch Model(Hopping([1 2]))  # Non-square intra-sublattice hopping matrix!

@test isempty(QBox.nzonsites(Model()))

end